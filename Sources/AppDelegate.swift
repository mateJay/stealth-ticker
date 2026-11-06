import AppKit
import Carbon
import Foundation

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var southboundPopover: NSPopover!
    private let quoteVC = QuoteViewController()
    private let southboundVC = SouthboundViewController()
    private let fetcher = QuoteFetcher()
    private let southboundService = SouthboundService()

    private var timer: Timer?
    private var hotKeyRef: EventHotKeyRef?

    private var currentSecid = "116.00700"
    private var mode = "dot"
    private var invertColors = false
    private var interval: TimeInterval = 3
    private var isHiddenByBoss = false
    private var offline = false
    private var quote: Quote?
    private var lastFetch = Date.distantPast
    private var isFetching = false

    private var southboundDays: [SouthboundDay] = []
    private var southboundFetchedAt = Date.distantPast
    private var southboundLoading = false
    private var southboundStocks: [String: [SouthboundStock]] = [:]
    private var southboundPendingDates: Set<String> = []

    private let defaults = UserDefaults.standard
    private struct Preset {
        let title: String
        let secid: String
    }

    private let presetGroups: [[Preset]] = [
        [
            Preset(title: "恒生指数", secid: "100.HSI"),
            Preset(title: "恒生科技指数", secid: "124.HSTECH"),
            Preset(title: "上证指数", secid: "1.000001"),
            Preset(title: "创业板指", secid: "0.399006"),
        ],
        [
            Preset(title: "腾讯控股", secid: "116.00700"),
            Preset(title: "阿里巴巴-W", secid: "116.09988"),
            Preset(title: "美团-W", secid: "116.03690"),
            Preset(title: "小米集团-W", secid: "116.01810"),
            Preset(title: "香港交易所", secid: "116.00388"),
        ],
    ]

    private var upColor: NSColor { invertColors ? .systemGreen : .systemRed }
    private var downColor: NSColor { invertColors ? .systemRed : .systemGreen }

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        loadDefaults()
        setupStatusItem()
        setupPopover()
        registerHotKey()

        quote = loadCachedQuote()
        applyDisplay()

        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker

        refresh()

        if ProcessInfo.processInfo.environment["STEALTH_TICKER_DEBUG"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.dumpDebugInfo() }
        }
    }

    private func dumpDebugInfo() {
        let button = statusItem.button
        let info: [String: Any] = [
            "isVisible": statusItem.isVisible,
            "length": statusItem.length,
            "buttonFrame": NSStringFromRect(button?.frame ?? .zero),
            "windowFrame": NSStringFromRect(button?.window?.frame ?? .zero),
            "hasWindow": button?.window != nil,
            "title": button?.attributedTitle.string ?? "<nil>",
            "screenFrame": NSStringFromRect(NSScreen.main?.frame ?? .zero),
            "screenSafeTop": NSScreen.main?.safeAreaInsets.top ?? -1,
            "screens": NSScreen.screens.map { NSStringFromRect($0.frame) },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/stealth-debug.json"))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    // MARK: 初始化

    private func loadDefaults() {
        if let value = defaults.string(forKey: "secid"), !value.isEmpty { currentSecid = value }
        if let value = defaults.string(forKey: "mode") { mode = value }
        invertColors = defaults.bool(forKey: "invertColors")
        let stored = defaults.double(forKey: "interval")
        if stored >= 1 { interval = stored }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = quoteVC
        _ = quoteVC.view

        southboundPopover = NSPopover()
        southboundPopover.behavior = .transient
        southboundPopover.animates = false
        southboundPopover.contentViewController = southboundVC
        _ = southboundVC.view
        southboundVC.onRequestDetail = { [weak self] date in
            self?.loadTopStocks(date: date)
        }
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { AppDelegate.shared?.toggleBossMode() }
            return noErr
        }, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x53544B52), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("StealthTicker: 快捷键注册失败 (\(status))")
        }
    }

    // MARK: 轮询

    private func tick() {
        let due = Market.isTrading(secid: currentSecid) ? interval : max(interval, 60)
        if Date().timeIntervalSince(lastFetch) >= due {
            refresh()
        }
    }

    private func refresh() {
        guard !isFetching else { return }
        isFetching = true
        lastFetch = Date()
        let requested = currentSecid

        fetcher.fetch(secid: requested) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false
                guard requested == self.currentSecid else { return }

                switch result {
                case .success(let fresh):
                    self.quote = fresh
                    self.offline = false
                    self.cache(fresh)
                case .failure:
                    self.offline = true
                }
                self.applyDisplay()
                if self.popover.isShown {
                    self.quoteVC.update(quote: self.quote, offline: self.offline)
                }
            }
        }
    }

    // MARK: 渲染

    private func applyDisplay() {
        guard let button = statusItem.button else { return }
        statusItem.isVisible = !isHiddenByBoss
        guard !isHiddenByBoss else { return }

        let tint: NSColor
        if offline || quote == nil {
            tint = .tertiaryLabelColor
        } else if let quote = quote {
            tint = quote.isUp ? upColor : downColor
        } else {
            tint = .tertiaryLabelColor
        }

        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let dotFont = NSFont.systemFont(ofSize: 9, weight: .regular)

        switch mode {
        case "pct":
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = NSAttributedString(
                string: quote.map { $0.pctText } ?? "--",
                attributes: [.font: mono, .foregroundColor: tint]
            )
        case "price":
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = NSAttributedString(
                string: quote.map { $0.priceText } ?? "--",
                attributes: [.font: mono, .foregroundColor: tint]
            )
        default:
            statusItem.length = 20
            button.attributedTitle = NSAttributedString(
                string: "●",
                attributes: [.font: dotFont, .foregroundColor: tint]
            )
        }

        button.toolTip = tooltipText()
    }

    private func tooltipText() -> String {
        guard let quote = quote else {
            return offline ? "行情获取失败，正在重试…" : "加载中…"
        }
        var text = "\(quote.name)  \(quote.priceText)  \(quote.changeText) (\(quote.pctText))"
        text += "  \(Market.clock.string(from: quote.updatedAt))"
        if offline { text += "  · 离线" }
        return text
    }

    // MARK: 交互

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        quoteVC.upColor = upColor
        quoteVC.downColor = downColor
        quoteVC.update(quote: quote, offline: offline)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func showSouthbound() {
        DispatchQueue.main.async { [weak self] in self?.toggleSouthboundPopover() }
    }

    private func toggleSouthboundPopover() {
        if southboundPopover.isShown {
            southboundPopover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        southboundVC.upColor = upColor
        southboundVC.downColor = downColor
        southboundVC.update(days: southboundDays, message: southboundDays.isEmpty ? "加载中…" : nil)

        NSApp.activate(ignoringOtherApps: true)
        southboundPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if Date().timeIntervalSince(southboundFetchedAt) > 600 {
            loadSouthbound()
        }
    }

    private func loadSouthbound() {
        guard !southboundLoading else { return }
        southboundLoading = true
        southboundService.fetch(limit: 12) { [weak self] result in
            guard let self = self else { return }
            self.southboundLoading = false
            switch result {
            case .success(let days):
                self.southboundDays = days
                self.southboundFetchedAt = Date()
                self.southboundVC.update(days: days, message: nil)
            case .failure:
                self.southboundVC.update(
                    days: self.southboundDays,
                    message: self.southboundDays.isEmpty ? "获取失败，请稍后重试" : nil
                )
            }
        }
    }

    private func loadTopStocks(date: String) {
        if let cached = southboundStocks[date] {
            southboundVC.setStocks(cached, for: date)
            return
        }
        guard !southboundPendingDates.contains(date) else { return }
        southboundPendingDates.insert(date)

        southboundService.fetchTopStocks(date: date) { [weak self] result in
            guard let self = self else { return }
            self.southboundPendingDates.remove(date)
            switch result {
            case .success(let stocks):
                self.southboundStocks[date] = stocks
                self.southboundVC.setStocks(stocks, for: date)
            case .failure:
                self.southboundVC.showDetailError(date: date)
            }
        }
    }

    private func toggleBossMode() {
        isHiddenByBoss.toggle()
        if isHiddenByBoss {
            popover.performClose(nil)
            southboundPopover.performClose(nil)
        }
        applyDisplay()
    }

    // MARK: 右键菜单

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: quote.map { "\($0.name)  \($0.priceText)" } ?? "行情加载中…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let southboundItem = NSMenuItem(title: "南向资金…", action: #selector(showSouthbound), keyEquivalent: "")
        southboundItem.target = self
        menu.addItem(southboundItem)
        menu.addItem(.separator())

        // 显示模式
        let modeItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        let modes: [(String, String)] = [("圆点（最隐蔽）", "dot"), ("涨跌幅", "pct"), ("价格", "price")]
        for (title, value) in modes {
            let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = (mode == value) ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // 股票
        let stockItem = NSMenuItem(title: "切换标的", action: nil, keyEquivalent: "")
        let stockMenu = NSMenu()
        for (groupIndex, group) in presetGroups.enumerated() {
            if groupIndex > 0 { stockMenu.addItem(.separator()) }
            for preset in group {
                let item = NSMenuItem(title: preset.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.secid
                item.state = (currentSecid == preset.secid) ? .on : .off
                stockMenu.addItem(item)
            }
        }
        stockMenu.addItem(.separator())
        let custom = NSMenuItem(title: "自定义代码…", action: #selector(promptCustomSecid), keyEquivalent: "")
        custom.target = self
        stockMenu.addItem(custom)
        stockItem.submenu = stockMenu
        menu.addItem(stockItem)

        // 刷新间隔
        let intervalItem = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for seconds in [2.0, 3.0, 5.0, 10.0] {
            let item = NSMenuItem(title: "\(Int(seconds)) 秒", action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = (interval == seconds) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let invert = NSMenuItem(title: "绿涨红跌（美股配色）", action: #selector(toggleInvert), keyEquivalent: "")
        invert.target = self
        invert.state = invertColors ? .on : .off
        menu.addItem(invert)

        let pause = NSMenuItem(title: isHiddenByBoss ? "恢复显示  ⌃⌥H" : "隐身  ⌃⌥H", action: #selector(menuToggleBossMode), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        mode = value
        defaults.set(mode, forKey: "mode")
        applyDisplay()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        switchSecurity(to: value)
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        interval = value
        defaults.set(value, forKey: "interval")
    }

    @objc private func toggleInvert() {
        invertColors.toggle()
        defaults.set(invertColors, forKey: "invertColors")
        applyDisplay()
    }

    @objc private func menuToggleBossMode() {
        toggleBossMode()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func promptCustomSecid() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "自定义标的"
        alert.informativeText = "港股填 5 位代码，如 00700。\n也支持完整 secid，如 116.00700、100.HSI。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = currentSecid
        field.placeholderString = "00700"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        switchSecurity(to: AppDelegate.normalize(raw))
    }

    private func switchSecurity(to secid: String) {
        currentSecid = secid
        defaults.set(secid, forKey: "secid")
        quote = nil
        offline = false
        lastFetch = .distantPast
        applyDisplay()
        refresh()
    }

    // MARK: 缓存

    private func cache(_ quote: Quote) {
        defaults.set([
            "secid": quote.secid,
            "name": quote.name,
            "price": quote.price,
            "prev": quote.prevClose,
            "ts": quote.updatedAt.timeIntervalSince1970,
        ], forKey: "lastQuote")
    }

    private func loadCachedQuote() -> Quote? {
        guard let dict = defaults.dictionary(forKey: "lastQuote"),
              let secid = dict["secid"] as? String,
              secid == currentSecid,
              let name = dict["name"] as? String,
              let price = dict["price"] as? Double,
              let prev = dict["prev"] as? Double,
              let ts = dict["ts"] as? Double else {
            return nil
        }
        return Quote(secid: secid, name: name, price: price, prevClose: prev, updatedAt: Date(timeIntervalSince1970: ts))
    }

    // MARK: 代码归一化

    static func normalize(_ raw: String) -> String {
        let text = raw.uppercased()
        if text.contains(".") { return text }

        let digits = text.filter { $0.isNumber }
        if digits.count == text.count {
            if digits.count == 5 { return "116.\(digits)" }          // 港股
            if digits.count == 6 {
                if digits.hasPrefix("6") { return "1.\(digits)" }    // 沪市
                return "0.\(digits)"                                 // 深市
            }
        }
        return "105.\(text)"                                         // 美股（纳斯达克）
    }
}
