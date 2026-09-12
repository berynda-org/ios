import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APIRequestMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public actor BeryndaAPIClient {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let language: @Sendable () -> String
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let jitter: @Sendable () -> Double
    private let authorizationSession: (any AuthorizationSession)?

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        language: @escaping @Sendable () -> String = { "uk" },
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) },
        authorizationSession: (any AuthorizationSession)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.language = language
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
        self.jitter = jitter
        self.authorizationSession = authorizationSession
        self.decoder = JSONDecoder()
    }

    public func request<Response: Decodable & Sendable>(
        _ endpoint: APIEndpoint,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let payload = try await data(
            endpoint,
            accept: "application/json",
            maximumBytes: 5 * 1_024 * 1_024
        )
        guard payload.contentType == "application/json"
                || payload.contentType?.hasSuffix("+json") == true
        else {
            throw APIError.unsupportedContentType(payload.contentType)
        }
        do {
            return try decoder.decode(Response.self, from: payload.data)
        } catch {
            throw APIError.decoding
        }
    }

    public func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        _ endpoint: APIEndpoint,
        method: APIRequestMethod,
        body: Body,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw APIError.invalidConfiguration
        }
        guard encoded.count <= 1 * 1_024 * 1_024 else {
            throw APIError.responseTooLarge
        }
        let payload = try await performData(
            endpoint,
            method: method,
            body: encoded,
            accept: "application/json",
            maximumBytes: 5 * 1_024 * 1_024
        )
        guard payload.contentType == "application/json"
                || payload.contentType?.hasSuffix("+json") == true
        else {
            throw APIError.unsupportedContentType(payload.contentType)
        }
        do {
            return try decoder.decode(Response.self, from: payload.data)
        } catch {
            throw APIError.decoding
        }
    }

    @discardableResult
    public func send(
        _ endpoint: APIEndpoint,
        method: APIRequestMethod
    ) async throws -> HTTPPayload {
        try await performData(
            endpoint,
            method: method,
            body: nil,
            accept: "application/json",
            maximumBytes: 1 * 1_024 * 1_024
        )
    }

    public func data(
        _ endpoint: APIEndpoint,
        accept: String = "*/*",
        maximumBytes: Int = 5 * 1_024 * 1_024
    ) async throws -> HTTPPayload {
        // The API negotiates its JSON renderer before a view returns a binary
        // file response. Image/PDF/EPUB-only Accept headers therefore get 406.
        // Still validate the successful payload's MIME type in the repository.
        let responseTypes = accept == "*/*" || accept.contains("application/json")
            ? accept
            : "\(accept), application/json"
        return try await performData(
            endpoint,
            method: .get,
            body: nil,
            accept: responseTypes,
            maximumBytes: maximumBytes
        )
    }

    private func performData(
        _ endpoint: APIEndpoint,
        method: APIRequestMethod,
        body: Data?,
        accept: String,
        maximumBytes: Int
    ) async throws -> HTTPPayload {
        guard let url = endpoint.url(relativeTo: baseURL) else {
            throw APIError.invalidConfiguration
        }
        guard maximumBytes > 0 else { throw APIError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(language(), forHTTPHeaderField: "Accept-Language")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        var bearerToken = await authorizationSession?.accessToken()
        if let token = bearerToken, AuthTokens.isValidJWT(token) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            bearerToken = nil
        }

        var attempt = 1
        var attemptedSessionRefresh = false
        while true {
            try Task.checkCancellation()

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.data(
                    for: request,
                    maximumBytes: maximumBytes
                )
            } catch let error as APIError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                throw APIError.transport
            }

            guard data.count <= maximumBytes else {
                throw APIError.responseTooLarge
            }
            if response.expectedContentLength > Int64(maximumBytes) {
                throw APIError.responseTooLarge
            }

            if (response.statusCode == 429 || Self.retryableServerStatuses.contains(response.statusCode)),
               method == .get || method == .put || method == .delete,
               attempt < retryPolicy.maximumAttempts {
                let retryAfter = response.statusCode == 429 ? parseRetryAfter(response) : nil
                let delay = retryPolicy.delay(
                    afterAttempt: attempt,
                    retryAfter: retryAfter,
                    jitter: jitter()
                )
                attempt += 1
                try await sleeper(delay)
                continue
            }

            let context = errorContext(data: data, response: response)
            switch response.statusCode {
            case 200..<300:
                return HTTPPayload(
                    data: data,
                    contentType: response.value(forHTTPHeaderField: "Content-Type")?
                        .split(separator: ";", maxSplits: 1)
                        .first
                        .map { String($0).lowercased() },
                    expectedLength: response.expectedContentLength >= 0
                        ? response.expectedContentLength
                        : nil
                )
            case 401:
                if let authorizationSession,
                   let rejectedAccessToken = bearerToken,
                   !attemptedSessionRefresh {
                    attemptedSessionRefresh = true
                    do {
                        let refreshed = try await authorizationSession.refreshAccessToken(
                            rejectedAccessToken: rejectedAccessToken
                        )
                        guard AuthTokens.isValidJWT(refreshed) else {
                            throw SessionError.invalidToken
                        }
                        bearerToken = refreshed
                        request.setValue(
                            "Bearer \(refreshed)",
                            forHTTPHeaderField: "Authorization"
                        )
                        attempt = 1
                        continue
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw APIError.unauthorized(context)
                    }
                }
                throw APIError.unauthorized(context)
            case 403:
                throw APIError.forbidden(context)
            case 404:
                throw APIError.notFound(context)
            case 429:
                throw APIError.rateLimited(
                    retryAfter: parseRetryAfter(response),
                    context: context
                )
            default:
                throw APIError.server(status: response.statusCode, context: context)
            }
        }
    }

    private static let retryableServerStatuses: Set<Int> = [500, 502, 503, 504]

    private func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(raw),
              seconds >= 0
        else { return nil }
        return seconds
    }

    private func errorContext(data: Data, response: HTTPURLResponse) -> APIErrorContext {
        let envelope = try? decoder.decode(
            APIErrorEnvelope.self,
            from: Data(data.prefix(64 * 1_024))
        )
        return APIErrorContext(
            code: sanitize(envelope?.code, maximumLength: 64),
            requestID: sanitize(
                response.value(forHTTPHeaderField: "X-Request-ID") ?? envelope?.requestID,
                maximumLength: 128
            )
        )
    }

    private func sanitize(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maximumLength))
    }
}

private struct APIErrorEnvelope: Decodable {
    let code: String?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code
        case requestID = "request_id"
    }
}

public struct HTTPPayload: Sendable, Equatable {
    public let data: Data
    public let contentType: String?
    public let expectedLength: Int64?

    public init(data: Data, contentType: String?, expectedLength: Int64?) {
        self.data = data
        self.contentType = contentType
        self.expectedLength = expectedLength
    }
}
