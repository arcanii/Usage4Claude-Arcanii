//
//  OAuthCallbackServer.swift
//  Usage4Claude
//
//  Provider-neutral local OAuth callback server (Network.framework, no
//  third-party dependency).
//

import Foundation
import Network
import OSLog

/// Local OAuth callback server.
///
/// Listens on a localhost port, captures the `/callback?code=...&state=...`
/// redirect the system browser sends back, returns a small success page to the
/// browser, and delivers the query parameters to the caller via `onCallback`.
final class OAuthCallbackServer {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.arcanii.Usage4Claude.oauth.callback")
    private(set) var port: UInt16 = 0
    private var onCallback: (([String: String]) -> Void)?
    private var didDeliver = false

    /// Release the bound port if this server is deallocated without `stop()`.
    ///
    /// The ordinary paths already call `stop()` — the coordinator's `cleanup()` runs on
    /// success, failure, timeout, and the login view's `onDisappear`. This covers the
    /// one that doesn't: if the window is torn down mid-flow and SwiftUI never delivers
    /// `onDisappear`, the coordinator (which has no `deinit` of its own) is released and
    /// takes this server with it, leaving the listener bound for the app's lifetime and
    /// a retry reporting "port busy".
    ///
    /// Safe from a nonisolated `deinit`: `NWListener` is `Sendable`, so `cancel()`
    /// crosses no isolation boundary even though this class is implicitly `@MainActor`
    /// (SWIFT_DEFAULT_ACTOR_ISOLATION). Do NOT rewrite this as `deinit { stop() }` — the
    /// shape used elsewhere in this codebase — because `stop()` is MainActor-isolated
    /// and that form is an error under the Swift 6 language mode.
    deinit {
        listener?.cancel()
    }

    /// Try each port in order, binding the first available one.
    /// - Returns: The bound port, or nil if all fail.
    func start(ports: [UInt16], onCallback: @escaping ([String: String]) -> Void) -> UInt16? {
        self.onCallback = onCallback
        // Reset the one-shot delivery latch: the coordinator reuses one server
        // instance across retry logins. Without this, a retry after a first failure
        // would silently drop the callback even when the browser really got a code.
        self.didDeliver = false
        for p in ports where startListener(on: p) {
            self.port = p
            return p
        }
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func startListener(on port: UInt16) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // `requiredLocalEndpoint` is deliberately NOT pinned: doing so binds a single
        // address, and a browser may resolve `localhost` to either 127.0.0.1 or ::1.
        // The cost is that this binds the WILDCARD address, so the port is briefly
        // reachable on every interface (en0, awdl0, …) — not just loopback.
        // `handle(_:)` therefore drops any peer that isn't loopback before parsing
        // a single byte. See `isLoopbackPeer`.

        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            Logger.settings.error("OAuthCallbackServer: failed to create listener on port \(port) - \(error.localizedDescription, privacy: .public)")
            return false
        }

        let sema = DispatchSemaphore(value: 0)
        var ready = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready = true
                sema.signal()
            case .waiting(let error):
                // When the port is busy, NWListener enters .waiting (keeps retrying)
                // rather than .failed. Signal immediately so we can move on to the
                // next port, and log the real reason.
                Logger.settings.error("OAuthCallbackServer: port \(port) unavailable (\(error.localizedDescription, privacy: .public)), trying next")
                sema.signal()
            case .failed(let error):
                Logger.settings.error("OAuthCallbackServer: listener failed on port \(port) - \(error.localizedDescription, privacy: .public)")
                sema.signal()
            case .cancelled:
                sema.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)

        // Wait up to 2 seconds to confirm the bind result.
        _ = sema.wait(timeout: .now() + 2)
        if ready {
            self.listener = listener
            Logger.settings.info("OAuthCallbackServer: listening on localhost:\(port)")
            return true
        }
        listener.cancel()
        Logger.settings.error("OAuthCallbackServer: port \(port) did not become ready within the timeout")
        return false
    }

    /// Whether an IPv4 address is loopback.
    ///
    /// RFC 1122 reserves the whole `127.0.0.0/8` block, but `IPv4Address.isLoopback`
    /// only matches `127.0.0.1` exactly — so a host that resolves `localhost` to
    /// another address in that block (e.g. `127.0.0.53`) would be wrongly rejected.
    /// Test the leading octet instead.
    private static func isLoopbackIPv4(_ address: IPv4Address) -> Bool {
        address.rawValue.first == 127
    }

    /// Whether an inbound peer is on the loopback interface.
    ///
    /// The listener binds the wildcard address (see `startListener`), so LAN hosts
    /// can also connect. Because the socket is dual-stack, an IPv4 peer arrives as
    /// an IPv4-mapped IPv6 address (`::ffff:127.0.0.1`), which `IPv6Address.isLoopback`
    /// reports as `false` — unwrap via `asIPv4` before deciding.
    private static func isLoopbackPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return isLoopbackIPv4(address)
        case .ipv6(let address):
            if address.isLoopback { return true }           // ::1
            if let mapped = address.asIPv4 { return isLoopbackIPv4(mapped) }
            return false
        default:
            return false
        }
    }

    private func handle(_ connection: NWConnection) {
        // Drop non-loopback peers before reading any bytes. The OAuth code itself is
        // safe from theft (it is delivered to the user's own browser, and PKCE + the
        // `state` nonce gate acceptance), but `didDeliver` latches on the first request
        // carrying `code` or `error` — so without this check any host on the LAN could
        // hit /callback?error=x mid-sign-in and kill a legitimate login.
        guard Self.isLoopbackPeer(connection.endpoint) else {
            Logger.settings.error("OAuthCallbackServer: rejected non-loopback connection from \(String(describing: connection.endpoint), privacy: .public)")
            connection.cancel()
            return
        }

        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self,
                  let data = data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let query = self.parseQuery(fromRequestLine: request)

            let body = Self.responseHTML(success: query["code"] != nil)
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            // Only deliver the first valid callback (code or error).
            if !self.didDeliver, query["code"] != nil || query["error"] != nil {
                self.didDeliver = true
                DispatchQueue.main.async { self.onCallback?(query) }
            }
        }
    }

    /// Parse query parameters from the HTTP request line.
    /// e.g. `GET /callback?code=...&state=... HTTP/1.1`
    private func parseQuery(fromRequestLine request: String) -> [String: String] {
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return [:] }
        let path = String(parts[1])
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }

        let queryString = String(path[path.index(after: qIndex)...])
        var result: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let k = kv.first else { continue }
            let key = String(k).removingPercentEncoding ?? String(k)
            let rawValue = kv.count > 1 ? String(kv[1]) : ""
            result[key] = rawValue.removingPercentEncoding ?? rawValue
        }
        return result
    }

    private static func responseHTML(success: Bool) -> String {
        let title = success ? "Signed in" : "Sign-in failed"
        let heading = success ? "✅ Signed in successfully" : "⚠️ Sign-in failed"
        let message = success
            ? "You can close this tab and return to Usage4Claude."
            : "Something went wrong. Please return to Usage4Claude and try again."
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;text-align:center;padding-top:80px;color:#1d1d1f;background:#f5f5f7">
        <h2>\(heading)</h2>
        <p>\(message)</p>
        </body></html>
        """
    }
}
