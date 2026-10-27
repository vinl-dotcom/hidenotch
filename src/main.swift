// HideNotch — 隐藏 MacBook 刘海的后台壁纸补丁工具
//
// 原理：把内置屏菜单栏背后那条区域涂黑。半透明的菜单栏采样到黑色后整条变黑，
// 物理刘海（本身是黑的）融入其中、视觉上消失；桌面其余部分保持浅色。
//
// 外接屏保护策略（三重防线）：
//   1. 通过 defaults 关闭 macOS 壁纸跨屏同步
//   2. 补丁前捕获外接屏原始壁纸 URL，补丁后立即恢复 + 延迟再恢复
//   3. 若外接屏已被同步为补丁图，生成无黑条的干净壁纸恢复
//
// 这是一个常驻后台 agent（LSUIElement，无 Dock / 无窗口），监听换壁纸、切 Space、
// 插拔显示器等事件并自动重新涂黑——这正是市面同类软件容易"失效"的原因。
// SPDX-License-Identifier: GPL-3.0-only

import Cocoa

final class NotchHider: NSObject, NSApplicationDelegate {

    /// 状态目录：~/Library/Application Support/HideNotch/
    private let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HideNotch", isDirectory: true)
    }()

    /// 生成的补丁壁纸（带黑条，仅用于内置屏）
    private var patchedURL: URL { supportDir.appendingPathComponent("patched.png") }
    /// 生成的干净壁纸（无黑条，用于外接屏被同步后的恢复）
    private var cleanURL: URL { supportDir.appendingPathComponent("clean.png") }
    /// 记录用户原始壁纸路径，用于卸载时还原
    private var sourceRecordURL: URL { supportDir.appendingPathComponent("source.txt") }

    /// 防止 setDesktopImageURL 触发的通知造成自循环
    private var isApplying = false
    private var pollTimer: Timer?

    /// 各外接屏的原始壁纸 URL（在内置屏被替换前捕获）
    private var externalOriginals: [CGDirectDisplayID: URL] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        // 关闭 macOS 壁纸跨屏同步（第一道防线）
        disableWallpaperSync()

        let ws = NSWorkspace.shared
        // 切 Space（每个 Space 可有独立壁纸）
        ws.notificationCenter.addObserver(
            self, selector: #selector(reapply),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // 唤醒后系统可能重置壁纸
        ws.notificationCenter.addObserver(
            self, selector: #selector(reapply),
            name: NSWorkspace.didWakeNotification, object: nil)
        // 插拔显示器 / 分辨率变化
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // 低频兜底：比对当前壁纸 URL，捕捉漏掉的换壁纸事件
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.applyPatch()
        }

        applyPatch()
    }

    @objc private func reapply() {
        // 给系统切换壁纸/屏幕配置留一点时间，再应用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.applyPatch()
        }
    }

    /// 找到带刘海的内置屏（safeAreaInsets.top > 0）。找不到则返回 nil。
    private func builtInNotchedScreen() -> NSScreen? {
        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            return screen
        }
        return nil
    }

    /// 黑条高度（screen points）。带刘海机型上即菜单栏高度。
    private func barHeightPoints(for screen: NSScreen) -> CGFloat {
        let inset = screen.safeAreaInsets.top
        if inset > 0 { return inset }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return max(menuBar, NSStatusBar.system.thickness)
    }

    // MARK: - 壁纸同步控制

    /// 关闭 macOS 壁纸跨屏同步。尝试多个已知的 defaults key。
    private func disableWallpaperSync() {
        let keys = [
            ("com.apple.wallpaper", "StretchyCropping"),
            ("com.apple.dock", "change-desktop-with-window"),
        ]
        for (domain, key) in keys {
            // 尝试设置为 false / 0 / NO 等不同形式
            let proc = Process()
            proc.launchPath = "/usr/bin/defaults"
            proc.arguments = ["write", domain, key, "-bool", "false"]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    // MARK: - 核心补丁逻辑

    @objc private func applyPatch() {
        guard !isApplying else { return }
        guard let builtIn = builtInNotchedScreen() else { return }

        let ws = NSWorkspace.shared

        // ── 第一步：在任何修改之前，捕获所有外接屏的当前壁纸 URL ──
        var newExternalOriginals: [CGDirectDisplayID: URL] = [:]
        for scr in NSScreen.screens where scr != builtIn {
            guard let displayID = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if let url = ws.desktopImageURL(for: scr),
               url.standardizedFileURL != patchedURL.standardizedFileURL {
                newExternalOriginals[displayID] = url
            }
        }
        if !newExternalOriginals.isEmpty {
            externalOriginals = newExternalOriginals
        }

        // ── 第二步：为内置屏生成并应用补丁壁纸 ──
        guard let currentURL = ws.desktopImageURL(for: builtIn) else { return }

        // 已经是补丁图 → 仍需确保外接屏不被同步污染
        if currentURL.standardizedFileURL == patchedURL.standardizedFileURL {
            restoreExternalScreens(ws: ws, source: nil)
            return
        }

        // 视为用户真实壁纸：加载图像
        guard let source = NSImage(contentsOf: currentURL) else {
            // 取不到单张图（动态/Aerial/轮播壁纸等）→ 保留用户壁纸不动
            return
        }

        // 记录原始壁纸路径，供卸载还原
        try? currentURL.path.write(to: sourceRecordURL, atomically: true, encoding: .utf8)

        // 生成带黑条的补丁图
        guard let patched = makePatchedImage(source: source, screen: builtIn, withBlackBar: true) else { return }
        guard writePNG(patched, to: patchedURL) else { return }

        // 同时生成无黑条的干净图（用于外接屏被同步后的恢复）
        if let clean = makePatchedImage(source: source, screen: builtIn, withBlackBar: false) {
            writePNG(clean, to: cleanURL)
        }

        isApplying = true
        defer { isApplying = false }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            .allowClipping: true,
        ]

        // 先设内置屏（可能触发同步到外接屏）
        try? ws.setDesktopImageURL(patchedURL, for: builtIn, options: options)

        // 立即恢复外接屏（第二道防线）
        restoreExternalScreens(ws: ws, source: source)

        // 延迟 1 秒再恢复一次：覆盖异步同步（第三道防线）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restoreExternalScreens(ws: NSWorkspace.shared, source: source)
        }

        // 延迟 3 秒做最终兜底
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.restoreExternalScreens(ws: NSWorkspace.shared, source: source)
        }
    }

    /// 恢复外接屏壁纸。三重策略：
    ///   1. 有原始 URL → 直接恢复
    ///   2. 外接屏当前是补丁图 → 用干净版壁纸恢复
    ///   3. 都没有 → 用 source 生成干净壁纸恢复
    private func restoreExternalScreens(ws: NSWorkspace, source: NSImage?) {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            .allowClipping: true,
        ]

        for scr in NSScreen.screens {
            guard let displayID = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            // 跳过内置屏
            if scr.safeAreaInsets.top > 0 { continue }

            let currentExtURL = ws.desktopImageURL(for: scr)

            // 策略 1：外接屏壁纸已经是正确的原始壁纸 → 无需操作
            if let currentExtURL = currentExtURL,
               let origURL = externalOriginals[displayID],
               currentExtURL.standardizedFileURL == origURL.standardizedFileURL {
                continue
            }

            // 策略 2：有记录的原始 URL → 恢复
            if let origURL = externalOriginals[displayID] {
                try? ws.setDesktopImageURL(origURL, for: scr, options: options)
                continue
            }

            // 策略 3：外接屏被同步为补丁图 → 用干净版壁纸替换
            if let currentExtURL = currentExtURL,
               currentExtURL.standardizedFileURL == patchedURL.standardizedFileURL {
                // 尝试用已生成的 clean.png
                if FileManager.default.fileExists(atPath: cleanURL.path) {
                    try? ws.setDesktopImageURL(cleanURL, for: scr, options: options)
                }
                continue
            }

            // 策略 4：都没有 → 用 source 动态生成干净壁纸
            if let source = source {
                if let clean = makePatchedImage(source: source, screen: scr, withBlackBar: false) {
                    if writePNG(clean, to: cleanURL) {
                        try? ws.setDesktopImageURL(cleanURL, for: scr, options: options)
                    }
                }
            }
        }
    }

    // MARK: - 图像生成

    /// 生成屏幕原生像素尺寸的壁纸：原图按 fill 画入 + 可选顶部黑条。
    /// withBlackBar = true  → 内置屏用（带黑条，隐藏刘海）
    /// withBlackBar = false → 外接屏用（无黑条，干净壁纸）
    private func makePatchedImage(source: NSImage, screen: NSScreen, withBlackBar: Bool) -> NSImage? {
        let scale = screen.backingScaleFactor
        let pxW = Int((screen.frame.width * scale).rounded())
        let pxH = Int((screen.frame.height * scale).rounded())
        guard pxW > 0, pxH > 0 else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: CGFloat(pxW), height: CGFloat(pxH))

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = ctx
        defer { NSGraphicsContext.current = prev }

        let canvas = NSRect(x: 0, y: 0, width: CGFloat(pxW), height: CGFloat(pxH))

        // 先铺黑（图比例不符时四周不留白缝）
        NSColor.black.setFill()
        canvas.fill()

        // 按 fill（aspect-fill）绘制原图：缩放到铺满，居中裁剪
        let srcSize = source.size
        if srcSize.width > 0, srcSize.height > 0 {
            let s = max(canvas.width / srcSize.width, canvas.height / srcSize.height)
            let drawW = srcSize.width * s
            let drawH = srcSize.height * s
            let drawRect = NSRect(
                x: (canvas.width - drawW) / 2,
                y: (canvas.height - drawH) / 2,
                width: drawW, height: drawH)
            source.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        }

        // 顶部黑条（仅内置屏需要）
        if withBlackBar {
            let barPx = (barHeightPoints(for: screen) * scale).rounded(.up)
            let barRect = NSRect(x: 0, y: CGFloat(pxH) - barPx, width: CGFloat(pxW), height: barPx)
            NSColor.black.setFill()
            barRect.fill()
        }

        let img = NSImage(size: NSSize(width: CGFloat(pxW), height: CGFloat(pxH)))
        img.addRepresentation(rep)
        return img
    }

    private func writePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

let app = NSApplication.shared
let delegate = NotchHider()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 无 Dock 图标
app.run()
