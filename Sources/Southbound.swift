import AppKit
import Carbon
import Foundation

// MARK: - 南向资金

struct SouthboundDay {
    let date: String        // "2026-11-05"
    let shanghai: Double    // 亿元
    let shenzhen: Double    // 亿元

    var total: Double { shanghai + shenzhen }

    var shortDate: String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])-\(parts[2])"
    }
}

/// 港股通日度资金流。MUTUAL_TYPE=002 沪、004 深，两边分别取再按日期合并。
/// 注意：接口金额单位是百万元，÷100 才是亿元。
final class SouthboundService {
    private let session: URLSession
    private let lock = NSLock()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh)"]
        session = URLSession(configuration: config)
    }

    func fetch(limit: Int = 12, completion: @escaping (Result<[SouthboundDay], Error>) -> Void) {
        let group = DispatchGroup()
        var merged: [String: (sh: Double, sz: Double)] = [:]
        var failure: Error?

        for (type, isShanghai) in [("002", true), ("004", false)] {
            let urlString = "https://datacenter-web.eastmoney.com/api/data/v1/get"
                + "?reportName=RPT_MUTUAL_DEAL_HISTORY&columns=ALL&pageSize=\(limit)"
                + "&sortColumns=TRADE_DATE&sortTypes=-1&filter=(MUTUAL_TYPE%3D%22\(type)%22)"
            guard let url = URL(string: urlString) else { continue }

            group.enter()
            session.dataTask(with: url) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self else { return }
                if let error = error {
                    self.lock.lock(); failure = error; self.lock.unlock()
                    return
                }
                guard let data = data, let rows = Self.rows(from: data) else { return }

                self.lock.lock()
                for row in rows {
                    guard let rawDate = row["TRADE_DATE"] as? String,
                          let net = row["NET_DEAL_AMT"] as? NSNumber else { continue }
                    let date = String(rawDate.prefix(10))
                    let amount = net.doubleValue / 100        // 百万元 → 亿元
                    var entry = merged[date] ?? (0, 0)
                    if isShanghai { entry.sh = amount } else { entry.sz = amount }
                    merged[date] = entry
                }
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard self != nil else { return }
            if let failure = failure {
                completion(.failure(failure))
                return
            }
            let days = merged
                .map { SouthboundDay(date: $0.key, shanghai: $0.value.sh, shenzhen: $0.value.sz) }
                .sorted { $0.date > $1.date }
            completion(.success(days))
        }
    }

    private static func rows(from data: Data) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let rows = result["data"] as? [[String: Any]] else { return nil }
        return rows
    }
}

struct SouthboundStock {
    let code: String
    let name: String
    let netBuy: Double      // 元
    let dealAmt: Double     // 元
    let ratio: Double       // 占该股成交额比例 %
}

extension SouthboundService {
    /// 某一天的十大成交股，沪/深两个通道合并后按净买入从高到低排。
    func fetchTopStocks(date: String, completion: @escaping (Result<[SouthboundStock], Error>) -> Void) {
        let group = DispatchGroup()
        var merged: [String: SouthboundStock] = [:]
        var failure: Error?

        for type in ["002", "004"] {
            let urlString = "https://datacenter-web.eastmoney.com/api/data/v1/get"
                + "?reportName=RPT_MUTUAL_TOP10DEAL&columns=ALL&pageSize=10&sortColumns=RANK&sortTypes=1"
                + "&filter=(MUTUAL_TYPE%3D%22\(type)%22)(TRADE_DATE%3D%27\(date)%27)"
            guard let url = URL(string: urlString) else { continue }

            group.enter()
            session.dataTask(with: url) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self else { return }
                if let error = error {
                    self.lock.lock(); failure = error; self.lock.unlock()
                    return
                }
                guard let data = data, let rows = Self.rows(from: data) else { return }

                self.lock.lock()
                for row in rows {
                    guard let code = row["SECURITY_CODE"] as? String,
                          let name = row["SECURITY_NAME"] as? String,
                          let net = row["NET_BUY_AMT"] as? NSNumber else { continue }
                    let deal = (row["DEAL_AMT"] as? NSNumber)?.doubleValue ?? 0
                    let ratio = (row["MUTUAL_RATIO"] as? NSNumber)?.doubleValue ?? 0

                    if let existing = merged[code] {
                        merged[code] = SouthboundStock(
                            code: code,
                            name: name,
                            netBuy: existing.netBuy + net.doubleValue,
                            dealAmt: existing.dealAmt + deal,
                            ratio: min(100, existing.ratio + ratio)
                        )
                    } else {
                        merged[code] = SouthboundStock(
                            code: code,
                            name: name,
                            netBuy: net.doubleValue,
                            dealAmt: deal,
                            ratio: min(100, ratio)
                        )
                    }
                }
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard self != nil else { return }
            if let failure = failure {
                completion(.failure(failure))
                return
            }
            let ranked = merged.values
                .filter { $0.netBuy != 0 || $0.dealAmt > 0 }
                .sorted { $0.netBuy > $1.netBuy }
            completion(.success(Array(ranked.prefix(10))))
        }
    }
}
