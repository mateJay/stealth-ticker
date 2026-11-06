import AppKit
import Carbon
import Foundation

// MARK: - 南向资金面板

/// 可点击的一行：hover 高亮，松手触发回调。
final class ClickableRow: NSView {
    var onTap: (() -> Void)?
    private var tracking: NSTrackingArea?

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = tracking { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onTap?()
    }
}

final class SouthboundViewController: NSViewController {
    private enum Mode {
        case history
        case detail(String)
    }

    private let titleLabel = NSTextField(labelWithString: "南向资金")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let bodyStack = NSStackView()
    private let moreButton = NSButton(title: "查看更多", target: nil, action: nil)
    private let backButton = NSButton(title: "‹ 返回", target: nil, action: nil)

    private var days: [SouthboundDay] = []
    private var message: String? = "加载中…"
    private var mode: Mode = .history
    private var expanded = false

    private var stocksByDate: [String: [SouthboundStock]] = [:]
    private var failedDates: Set<String> = []

    var onRequestDetail: ((String) -> Void)?
    var upColor: NSColor = .systemRed
    var downColor: NSColor = .systemGreen

    override func loadView() {
        let root = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .inline
        backButton.isBordered = false
        backButton.font = .systemFont(ofSize: 11)
        backButton.contentTintColor = .controlAccentColor
        backButton.isHidden = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .tertiaryLabelColor

        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 1

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 6
        bodyStack.widthAnchor.constraint(equalToConstant: 292).isActive = true

        moreButton.target = self
        moreButton.action = #selector(toggleExpanded)
        moreButton.bezelStyle = .inline
        moreButton.isBordered = false
        moreButton.font = .systemFont(ofSize: 11)
        moreButton.contentTintColor = .controlAccentColor

        stack.addArrangedSubview(backButton)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(bodyStack)
        stack.addArrangedSubview(moreButton)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 320),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
        rebuild()
    }

    func update(days: [SouthboundDay], message: String?) {
        self.days = days
        self.message = message
        self.mode = .history
        rebuild()
    }

    func setStocks(_ stocks: [SouthboundStock], for date: String) {
        stocksByDate[date] = stocks
        failedDates.remove(date)
        if case .detail(let current) = mode, current == date { rebuild() }
    }

    func showDetailError(date: String) {
        failedDates.insert(date)
        if case .detail(let current) = mode, current == date { rebuild() }
    }

    @objc private func toggleExpanded() {
        expanded.toggle()
        rebuild()
    }

    @objc private func goBack() {
        mode = .history
        rebuild()
    }

    private func openDetail(_ date: String) {
        mode = .detail(date)
        guard stocksByDate[date] == nil else {
            rebuild()
            return
        }
        failedDates.remove(date)
        rebuild()
        onRequestDetail?(date)
    }

    private func rebuild() {
        bodyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch mode {
        case .history:
            backButton.isHidden = true
            titleLabel.stringValue = "南向资金"
            buildHistory()
        case .detail(let date):
            backButton.isHidden = false
            titleLabel.stringValue = "十大成交股"
            buildDetail(date: date)
        }

        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 320, height: view.fittingSize.height)
    }

    private func buildHistory() {
        guard !days.isEmpty else {
            moreButton.isHidden = true
            subtitleLabel.stringValue = "港股通 · 盘后更新"
            addMessage(message ?? "暂无数据")
            return
        }

        let visible = Array(days.prefix(expanded ? 10 : 3))
        for day in visible {
            bodyStack.addArrangedSubview(makeDayRow(day))
        }
        subtitleLabel.stringValue = "近 \(visible.count) 日 · 盘后更新 · 点某天看榜单"
        moreButton.isHidden = days.count <= 3
        moreButton.title = expanded ? "收起" : "查看更多（近 10 日）"
    }

    private func buildDetail(date: String) {
        moreButton.isHidden = true

        if let day = days.first(where: { $0.date == date }) {
            subtitleLabel.stringValue = "\(day.shortDate) · 沪+深合并 · 净买入（亿）"
        } else {
            subtitleLabel.stringValue = "沪+深合并 · 净买入（亿）"
        }

        if let stocks = stocksByDate[date], !stocks.isEmpty {
            for (index, stock) in stocks.enumerated() {
                bodyStack.addArrangedSubview(makeStockRow(stock, rank: index + 1))
            }
        } else if failedDates.contains(date) {
            addMessage("获取失败，返回后重试")
        } else {
            addMessage("加载中…")
        }
    }

    private func addMessage(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        bodyStack.addArrangedSubview(label)
    }

    private func makeDayRow(_ day: SouthboundDay) -> NSView {
        let dateLabel = NSTextField(labelWithString: day.shortDate)
        dateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dateLabel.textColor = .secondaryLabelColor

        let splitLabel = NSTextField(
            labelWithString: String(format: "沪 %+.2f · 深 %+.2f", day.shanghai, day.shenzhen)
        )
        splitLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        splitLabel.textColor = .tertiaryLabelColor

        let left = NSStackView(views: [dateLabel, splitLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 0

        let totalLabel = NSTextField(labelWithString: String(format: "%+.2f", day.total))
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        totalLabel.textColor = day.total >= 0 ? upColor : downColor
        totalLabel.alignment = .right

        let chevron = NSTextField(labelWithString: "›")
        chevron.font = .systemFont(ofSize: 12, weight: .regular)
        chevron.textColor = .tertiaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let content = NSStackView(views: [left, spacer, totalLabel, chevron])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 6

        let row = ClickableRow(content: content)
        row.widthAnchor.constraint(equalToConstant: 292).isActive = true
        row.onTap = { [weak self] in self?.openDetail(day.date) }
        return row
    }

    private func makeStockRow(_ stock: SouthboundStock, rank: Int) -> NSView {
        let rankLabel = NSTextField(labelWithString: "\(rank)")
        rankLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        rankLabel.textColor = .tertiaryLabelColor
        rankLabel.alignment = .right
        rankLabel.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let nameLabel = NSTextField(labelWithString: stock.name)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingTail

        let ratioLabel = NSTextField(labelWithString: String(format: "占成交 %.1f%%", stock.ratio))
        ratioLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        ratioLabel.textColor = .tertiaryLabelColor

        let left = NSStackView(views: [nameLabel, ratioLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 0

        let netLabel = NSTextField(labelWithString: String(format: "%+.2f", stock.netBuy / 1e8))
        netLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        netLabel.textColor = stock.netBuy >= 0 ? upColor : downColor
        netLabel.alignment = .right

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView(views: [rankLabel, left, spacer, netLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 6
        row.widthAnchor.constraint(equalToConstant: 292).isActive = true
        return row
    }
}
