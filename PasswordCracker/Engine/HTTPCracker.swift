import Foundation

// MARK: - HTTP Cracker

/// Tests passwords against HTTP endpoints using Basic Auth, POST forms, or GET parameters.
/// Uses URLSession for all requests. Supports success detection via status code and body matching.
enum HTTPCracker {

    /// Tries a single password against the configured HTTP target.
    /// Returns `true` if the password grants access.
    static func tryPassword(_ password: String, config: AttackConfig) async -> Bool {
        guard let request = buildRequest(password: password, config: config) else { return false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            return evaluateResponse(statusCode: http.statusCode, body: data, config: config)
        } catch {
            return false
        }
    }

    /// Validates that the HTTP target is reachable and returns a non-error response.
    static func validate(config: AttackConfig) async -> Result<Void, CrackerError> {
        guard let url = URL(string: config.httpURL), url.scheme != nil else {
            return .failure(.invalidFile("Invalid URL"))
        }

        // Test with a dummy password to ensure the endpoint responds
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.invalidFile("No HTTP response"))
            }
            // Expect 401/403 for auth-protected endpoints, or 200 for form-based
            if http.statusCode >= 500 {
                return .failure(.invalidFile("Server error: \(http.statusCode)"))
            }
            return .success(())
        } catch {
            return .failure(.invalidFile("Cannot reach: \(error.localizedDescription)"))
        }
    }

    // MARK: - Request Building

    private static func buildRequest(password: String, config: AttackConfig) -> URLRequest? {
        switch config.httpMethod {
        case .basicAuth:
            return buildBasicAuthRequest(password: password, config: config)
        case .postForm:
            return buildPostFormRequest(password: password, config: config)
        case .getParam:
            return buildGetParamRequest(password: password, config: config)
        }
    }

    private static func buildBasicAuthRequest(password: String, config: AttackConfig) -> URLRequest? {
        guard let url = URL(string: config.httpURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let credentials = "\(config.username):\(password)"
        if let credData = credentials.data(using: .utf8) {
            let base64 = credData.base64EncodedString()
            request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private static func buildPostFormRequest(password: String, config: AttackConfig) -> URLRequest? {
        guard let url = URL(string: config.httpURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let usernameEncoded = config.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.username
        let passwordEncoded = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        let body = "\(config.usernameField)=\(usernameEncoded)&\(config.passwordField)=\(passwordEncoded)"
        request.httpBody = body.data(using: .utf8)

        return request
    }

    private static func buildGetParamRequest(password: String, config: AttackConfig) -> URLRequest? {
        guard var components = URLComponents(string: config.httpURL) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: config.usernameField, value: config.username))
        items.append(URLQueryItem(name: config.passwordField, value: password))
        components.queryItems = items

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        return request
    }

    // MARK: - Response Evaluation

    private static func evaluateResponse(statusCode: Int, body: Data, config: AttackConfig) -> Bool {
        // If a success indicator string is configured, check the body
        if !config.successIndicator.isEmpty {
            if let bodyString = String(data: body, encoding: .utf8) {
                return bodyString.contains(config.successIndicator)
            }
            return false
        }

        // Default: 200 OK = success, 401/403 = wrong password
        switch statusCode {
        case 200...299:
            return true
        case 301, 302:
            // Redirects after login often indicate success
            return true
        default:
            return false
        }
    }
}
