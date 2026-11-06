import AppKit
import Carbon
import Foundation

// MARK: - 行情模型

struct Quote {
    let secid: String
    let name: String
    let price: Double
    let prevClose: Double
    let updatedAt: Date

    var change: Double { price - prevClose }
    var changePct: Double { prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0 }
    var isUp: Bool { change >= 0 }

    var pctText: String { String(format: "%+.2f%%", changePct) }
    var changeText: String { String(format: "%+.2f", change) }

    var priceText: String {
        let digits = price < 10 ? 3 : 2
        return String(format: "%.\(digits)f", price)
    }
}
