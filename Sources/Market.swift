import AppKit
import Carbon
import Foundation

// MARK: - 交易时段

enum Market {
    static let timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    enum Kind {
        case hongKong
        case mainland
    }

    /// secid 前缀区分市场：1./0. 是沪深，其余（116./100./124./105.…）按港股时段
    static func kind(for secid: String) -> Kind {
        let prefix = secid.split(separator: ".").first.map(String.init) ?? ""
        return (prefix == "1" || prefix == "0") ? .mainland : .hongKong
    }

    /// 港股：09:10–12:00、13:00–16:10（含竞价）
    /// 沪深：09:15–11:30、13:00–15:05（含竞价与尾盘）
    static func isTrading(_ date: Date = Date(), secid: String) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }

        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)

        switch kind(for: secid) {
        case .hongKong:
            let morning = minutes >= 9 * 60 + 10 && minutes <= 12 * 60
            let afternoon = minutes >= 13 * 60 && minutes <= 16 * 60 + 10
            return morning || afternoon
        case .mainland:
            let morning = minutes >= 9 * 60 + 15 && minutes <= 11 * 60 + 30
            let afternoon = minutes >= 13 * 60 && minutes <= 15 * 60 + 5
            return morning || afternoon
        }
    }
}
