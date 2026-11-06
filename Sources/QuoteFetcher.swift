import AppKit
import Carbon
import Foundation

// MARK: - 行情抓取

final class QuoteFetcher {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh)"]
        session = URLSession(configuration: config)
    }

    func fetch(secid: String, completion: @escaping (Result<Quote, Error>) -> Void) {
        let fields = "f43,f58,f59,f60"
        guard let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=\(fields)") else {
            completion(.failure(FetchError.badURL))
            return
        }
        session.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(FetchError.empty))
                return
            }
            do {
                completion(.success(try Self.parse(data, secid: secid)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    enum FetchError: Error { case badURL, empty, payload }

    private static func parse(_ data: Data, secid: String) throws -> Quote {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else {
            throw FetchError.payload
        }

        func number(_ key: String) -> Double? {
            if let value = payload[key] as? NSNumber { return value.doubleValue }
            if let text = payload[key] as? String { return Double(text) }
            return nil
        }

        guard let rawPrice = number("f43") else { throw FetchError.payload }
        let scale = number("f59") ?? 2
        let divisor = pow(10.0, scale)

        let price = rawPrice / divisor
        let prevClose = (number("f60") ?? rawPrice) / divisor
        let name = (payload["f58"] as? String) ?? secid

        guard price > 0 else { throw FetchError.payload }
        return Quote(secid: secid, name: name, price: price, prevClose: prevClose, updatedAt: Date())
    }
}
