import Foundation

public protocol ReaderRepository: Sendable {
    func info(fileID: UUID) async throws -> ReaderInfo
    func text(fileID: UUID) async throws -> TextReaderContent
    func epubDocument(fileID: UUID) async throws -> Data
    func fullDocument(fileID: UUID) async throws -> Data
    func pagePDF(fileID: UUID, page: Int) async throws -> Data
    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data
    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool
}

public struct ReadingPositionUpdate: Codable, Sendable, Equatable {
    public let positionType: String
    public let positionValue: String
    public let progressPercent: Int?
    public let totalPages: Int?
    /// ISO 8601 time the reader was really at this position, sent for writes
    /// that were queued offline so a newer position is not overwritten.
    public let clientUpdatedAt: String?

    public init(
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?,
        clientUpdatedAt: String? = nil
    ) {
        self.positionType = positionType
        self.positionValue = positionValue
        self.progressPercent = progressPercent
        self.totalPages = totalPages
        self.clientUpdatedAt = clientUpdatedAt
    }

    func stamped(_ date: Date) -> ReadingPositionUpdate {
        ReadingPositionUpdate(
            positionType: positionType,
            positionValue: positionValue,
            progressPercent: progressPercent,
            totalPages: totalPages,
            clientUpdatedAt: Self.timestamp(date)
        )
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case positionType = "position_type"
        case positionValue = "position_value"
        case progressPercent = "progress_percent"
        case totalPages = "total_pages"
        case clientUpdatedAt = "client_updated_at"
    }
}

public actor LiveReaderRepository: ReaderRepository {
    private let client: BeryndaAPIClient
    private let decoder = JSONDecoder()

    public init(client: BeryndaAPIClient) {
        self.client = client
    }

    public func info(fileID: UUID) async throws -> ReaderInfo {
        try await client.request(.readerInfo(fileID: fileID))
    }

    public func text(fileID: UUID) async throws -> TextReaderContent {
        let payload = try await client.data(
            .readerContent(fileID: fileID, structuredText: true),
            accept: "application/json",
            maximumBytes: 20 * 1_024 * 1_024
        )
        try validate(payload, accepted: ["application/json"], maxBytes: 20 * 1_024 * 1_024)
        do {
            return try decoder.decode(TextReaderContent.self, from: payload.data)
        } catch {
            throw APIError.decoding
        }
    }

    public func fullDocument(fileID: UUID) async throws -> Data {
        let payload = try await client.data(
            .readerContent(fileID: fileID, structuredText: false),
            accept: "application/pdf",
            maximumBytes: 15 * 1_024 * 1_024
        )
        try validate(payload, accepted: ["application/pdf"], maxBytes: 15 * 1_024 * 1_024)
        guard payload.data.starts(with: Data("%PDF-".utf8)) else {
            throw APIError.invalidResponse
        }
        return payload.data
    }

    public func epubDocument(fileID: UUID) async throws -> Data {
        let payload = try await client.data(
            .readerContent(fileID: fileID, structuredText: false),
            accept: "application/epub+zip",
            maximumBytes: 100 * 1_024 * 1_024
        )
        try validate(
            payload,
            accepted: ["application/epub+zip"],
            maxBytes: 100 * 1_024 * 1_024
        )
        guard payload.data.starts(with: Data([0x50, 0x4b, 0x03, 0x04])) else {
            throw APIError.invalidResponse
        }
        return payload.data
    }

    public func pagePDF(fileID: UUID, page: Int) async throws -> Data {
        let payload = try await client.data(
            .pagePDF(fileID: fileID, page: page),
            accept: "application/pdf",
            maximumBytes: 10 * 1_024 * 1_024
        )
        try validate(payload, accepted: ["application/pdf"], maxBytes: 10 * 1_024 * 1_024)
        guard payload.data.starts(with: Data("%PDF-".utf8)) else {
            throw APIError.invalidResponse
        }
        return payload.data
    }

    public func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        let payload = try await client.data(
            .pageImage(fileID: fileID, page: page, width: width),
            accept: "image/*",
            maximumBytes: 10 * 1_024 * 1_024
        )
        guard let contentType = payload.contentType, contentType.hasPrefix("image/") else {
            throw APIError.unsupportedContentType(payload.contentType)
        }
        try validateSize(payload, maxBytes: 10 * 1_024 * 1_024)
        return payload.data
    }

    public func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool {
        let response: ReadingPositionSaveResponse = try await client.request(
            .readingPosition(fileID: fileID),
            method: .put,
            body: ReadingPositionUpdate(
                positionType: positionType,
                positionValue: positionValue,
                progressPercent: progressPercent,
                totalPages: totalPages
            )
        )
        return response.recorded ?? true
    }

    private func validate(_ payload: HTTPPayload, accepted: Set<String>, maxBytes: Int) throws {
        guard let contentType = payload.contentType, accepted.contains(contentType) else {
            throw APIError.unsupportedContentType(payload.contentType)
        }
        try validateSize(payload, maxBytes: maxBytes)
    }

    private func validateSize(_ payload: HTTPPayload, maxBytes: Int) throws {
        if let expectedLength = payload.expectedLength, expectedLength > maxBytes {
            throw APIError.responseTooLarge
        }
        guard payload.data.count <= maxBytes else {
            throw APIError.responseTooLarge
        }
    }
}

private struct ReadingPositionSaveResponse: Decodable, Sendable {
    let recorded: Bool?
}
