import AppKit
import Carbon
import Foundation

// MARK: - 详情面板

final class QuoteViewController: NSViewController {
    private let nameLabel = NSTextField(labelWithString: "—")
    private let codeLabel = NSTextField(labelWithString: "")
    private let priceLabel = NSTextField(labelWithString: "--")
    private let changeLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    var upColor: NSColor = .systemRed
    var downColor: NSColor = .systemGreen

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 208, height: 124))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail

        codeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        codeLabel.textColor = .secondaryLabelColor

        priceLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .light)

        changeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .tertiaryLabelColor

        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(codeLabel)
        stack.setCustomSpacing(7, after: codeLabel)
        stack.addArrangedSubview(priceLabel)
        stack.setCustomSpacing(1, after: priceLabel)
        stack.addArrangedSubview(changeLabel)
        stack.setCustomSpacing(9, after: changeLabel)
        stack.addArrangedSubview(timeLabel)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
        preferredContentSize = root.frame.size
    }

    func update(quote: Quote?, offline: Bool) {
        guard let quote = quote else {
            nameLabel.stringValue = offline ? "获取失败" : "加载中…"
            codeLabel.stringValue = ""
            priceLabel.stringValue = "--"
            priceLabel.textColor = .secondaryLabelColor
            changeLabel.stringValue = ""
            timeLabel.stringValue = offline ? "检查网络后会自动重试" : ""
            return
        }

        let tint = offline ? NSColor.secondaryLabelColor : (quote.isUp ? upColor : downColor)

        nameLabel.stringValue = quote.name
        codeLabel.stringValue = quote.secid
        priceLabel.stringValue = quote.priceText
        priceLabel.textColor = tint
        changeLabel.stringValue = "\(quote.changeText)   \(quote.pctText)"
        changeLabel.textColor = tint

        let clock = Market.clock.string(from: quote.updatedAt)
        let state = offline ? "离线" : (Market.isTrading(secid: quote.secid) ? "交易中" : "已收盘")
        timeLabel.stringValue = "\(clock) · \(state)"
    }
}
