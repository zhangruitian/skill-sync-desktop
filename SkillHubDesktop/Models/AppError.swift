import Foundation

// MARK: - App Error

/// Unified application error type with severity for consistent UI handling.
struct AppError: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let severity: Severity
    let domain: String
    let message: String
    let underlyingError: String?

    enum Severity: String, Comparable, CaseIterable {
        case info    = "info"
        case warning = "warning"
        case error   = "error"

        static func < (lhs: AppError.Severity, rhs: AppError.Severity) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    init(
        severity: Severity = .error,
        domain: String,
        message: String,
        underlyingError: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = severity
        self.domain = domain
        self.message = message
        self.underlyingError = underlyingError
    }
}

// MARK: - Convenience Factories

extension AppError {
    static func info(_ domain: String, _ message: String) -> AppError {
        AppError(severity: .info, domain: domain, message: message)
    }

    static func warning(_ domain: String, _ message: String) -> AppError {
        AppError(severity: .warning, domain: domain, message: message)
    }
}
