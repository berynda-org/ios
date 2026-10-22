import Foundation

public struct APIErrorContext: Equatable, Sendable {
    public let code: String?
    public let requestID: String?

    public init(code: String? = nil, requestID: String? = nil) {
        self.code = code
        self.requestID = requestID
    }
}

public enum APIError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case unauthorized(APIErrorContext)
    case forbidden(APIErrorContext)
    case notFound(APIErrorContext)
    case rateLimited(retryAfter: TimeInterval?, context: APIErrorContext)
    case server(status: Int, context: APIErrorContext)
    case decoding
    case transport
    case unsupportedContentType(String?)
    case responseTooLarge
}

public extension APIError {
    var context: APIErrorContext? {
        switch self {
        case let .unauthorized(context), let .forbidden(context), let .notFound(context):
            context
        case let .rateLimited(_, context), let .server(_, context):
            context
        case .invalidConfiguration, .invalidResponse, .decoding, .transport,
             .unsupportedContentType, .responseTooLarge:
            nil
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration, .invalidResponse:
            return CoreLocalization.string("Некоректна конфігурація сервісу.")
        case .unauthorized:
            return CoreLocalization.string("Потрібно увійти в обліковий запис.")
        case .forbidden:
            return CoreLocalization.string("Немає дозволу на цю дію.")
        case .notFound:
            return CoreLocalization.string("Матеріал не знайдено.")
        case .rateLimited:
            return CoreLocalization.string("Забагато запитів. Спробуйте трохи пізніше.")
        case .server:
            return CoreLocalization.string("Сервіс тимчасово недоступний.")
        case .decoding:
            return CoreLocalization.string("Сервіс повернув неочікувану відповідь.")
        case .transport:
            return CoreLocalization.string("Не вдалося з’єднатися з мережею.")
        case .unsupportedContentType:
            return CoreLocalization.string("Сервіс повернув непідтримуваний тип матеріалу.")
        case .responseTooLarge:
            return CoreLocalization.string("Матеріал завеликий для безпечного відкриття.")
        }
    }
}
