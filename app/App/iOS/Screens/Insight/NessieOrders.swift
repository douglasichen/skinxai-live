import Foundation
import EczemaKit

/// Claude's `order_history` tool backed by Capital One Nessie (see Integrations/nessie).
///
/// The server's `GET /api/orders?days=N` reads the purchases from Nessie (the key stays on the server)
/// and joins each one with our product catalog for ingredients. It returns the same JSON shape as
/// `StageStory.runToolJSON("order_history")`, so the rest of the chat doesn't change.
///
/// Off by default: the demo keeps its bundled orders. Turn on with the launch argument `-nessieOrders 1`.
/// If the request fails or times out, the caller falls back to the bundled orders, so the chat never stalls.
enum NessieOrders {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "nessieOrders") }

    /// `.../api/chat` → `.../api/orders`.
    static var endpoint: URL {
        ChatWire.endpoint.deletingLastPathComponent().appendingPathComponent("orders")
    }

    /// The tool result from Nessie, or nil (not enabled, not this tool, or the request failed).
    static func result(for call: ChatToolCall) async -> String? {
        guard enabled, call.name == "order_history" else { return nil }
        var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        if let days = call.argumentsObject["days"] as? Int, days > 0 {
            url.queryItems = [URLQueryItem(name: "days", value: String(days))]
        }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8), text.contains("\"orders\"") else { return nil }
            return text
        } catch {
            return nil
        }
    }
}
