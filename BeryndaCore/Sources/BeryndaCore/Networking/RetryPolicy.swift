import Foundation

public struct RetryPolicy: Sendable, Equatable {
    public let maximumAttempts: Int
    public let baseDelay: TimeInterval
    public let maximumDelay: TimeInterval
    public let maximumRetryAfter: TimeInterval

    public init(
        maximumAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maximumDelay: TimeInterval = 2,
        maximumRetryAfter: TimeInterval = 5
    ) {
        self.maximumAttempts = min(max(maximumAttempts, 1), 5)
        self.baseDelay = min(max(baseDelay, 0), 10)
        self.maximumDelay = min(max(maximumDelay, self.baseDelay), 30)
        self.maximumRetryAfter = min(max(maximumRetryAfter, 0), 30)
    }

    func delay(afterAttempt attempt: Int, retryAfter: TimeInterval?, jitter: Double) -> TimeInterval {
        if let retryAfter {
            return min(max(retryAfter, 0), maximumRetryAfter)
        }
        let exponential = baseDelay * pow(2, Double(max(attempt - 1, 0)))
        return min(exponential * min(max(jitter, 0.8), 1.2), maximumDelay)
    }
}
