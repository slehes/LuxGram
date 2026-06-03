import Foundation

// Enables App Store reviewers to log in without manual SMS code entry.
// Flow:
//   1. User enters a special "demo" phone number (configured via demoPhonePrefix)
//   2. Client prompts for a password
//   3. Client calls POST /api/auth/init on your backend → receives {sessionId, realPhone}
//   4. Client starts real Telegram auth with realPhone
//   5. Client polls GET /api/auth/code/{sessionId} every N seconds
//   6. Backend userbot intercepts login code → returns it via poll
//   7. Client auto-enters the code

public final class GLEDemoLoginService {
    public static let shared = GLEDemoLoginService()

    // MARK: - Configuration

    /// Backend URL. Set via GLEDemoLoginService.shared.backendURL = "..."
    public var backendURL: String = ""

    /// Phone prefix that triggers demo login (e.g. "+10000"). Digits only compared.
    public var demoPhonePrefix: String = "+10000"

    /// Polling interval in seconds
    public var pollInterval: TimeInterval = 3.0

    /// Maximum polling duration before giving up
    public var pollTimeout: TimeInterval = 120.0

    // MARK: - State

    private(set) var currentSessionId: String?
    private(set) var realPhone: String?
    private(set) var cloudPassword: String?
    private var pollTimer: Timer?
    private var pollStartTime: Date?
    private var codeCallback: ((String) -> Void)?

    private init() {}

    // MARK: - Public API

    /// Check if a phone number is a demo login number
    public func isDemoNumber(_ phone: String) -> Bool {
        guard !backendURL.isEmpty, !demoPhonePrefix.isEmpty else { return false }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.hasPrefix(demoPhonePrefix)
    }

    /// Initialize demo session: validate credentials with backend, get real phone number
    public func initSession(
        testPhone: String,
        password: String,
        completion: @escaping (Result<(sessionId: String, realPhone: String), DemoLoginError>) -> Void
    ) {
        guard !backendURL.isEmpty else {
            completion(.failure(.notConfigured))
            return
        }

        let urlString = backendURL.hasSuffix("/")
            ? "\(backendURL)api/demo-auth/init"
            : "\(backendURL)/api/demo-auth/init"

        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "phone": testPhone,
            "password": password
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.encodingError))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.network(error.localizedDescription)))
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.invalidResponse))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let message = json["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
                    completion(.failure(.serverError(message)))
                    return
                }

                guard let sessionId = json["sessionId"] as? String,
                      let realPhone = json["realPhone"] as? String else {
                    completion(.failure(.invalidResponse))
                    return
                }

                self.currentSessionId = sessionId
                self.realPhone = realPhone
                self.cloudPassword = json["password"] as? String
                completion(.success((sessionId: sessionId, realPhone: realPhone)))
            }
        }.resume()
    }

    /// Start polling for the login code. Calls `onCode` once when code is received.
    public func startPolling(onCode: @escaping (String) -> Void) {
        stopPolling()
        guard let sessionId = currentSessionId, !backendURL.isEmpty else { return }

        self.codeCallback = onCode
        self.pollStartTime = Date()

        let urlString = backendURL.hasSuffix("/")
            ? "\(backendURL)api/demo-auth/code/\(sessionId)"
            : "\(backendURL)/api/demo-auth/code/\(sessionId)"

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            // Timeout check
            if let start = self.pollStartTime, Date().timeIntervalSince(start) > self.pollTimeout {
                self.stopPolling()
                return
            }

            guard let url = URL(string: urlString) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            URLSession.shared.dataTask(with: request) { data, _, _ in
                DispatchQueue.main.async {
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let code = json["code"] as? String, !code.isEmpty else {
                        return
                    }
                    self.codeCallback?(code)
                    self.stopPolling()
                }
            }.resume()
        }
    }

    /// Stop polling and reset state
    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        codeCallback = nil
    }

    /// Full reset
    public func reset() {
        stopPolling()
        currentSessionId = nil
        realPhone = nil
        cloudPassword = nil
    }

    // MARK: - Errors

    public enum DemoLoginError: Error {
        case notConfigured
        case invalidURL
        case encodingError
        case network(String)
        case invalidResponse
        case serverError(String)

        public var localizedDescription: String {
            switch self {
            case .notConfigured: return "Demo login not configured"
            case .invalidURL: return "Invalid backend URL"
            case .encodingError: return "Request encoding error"
            case .network(let msg): return "Network error: \(msg)"
            case .invalidResponse: return "Invalid server response"
            case .serverError(let msg): return msg
            }
        }
    }
}
