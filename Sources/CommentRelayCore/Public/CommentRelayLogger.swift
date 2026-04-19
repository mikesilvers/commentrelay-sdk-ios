// Sources/CommentRelayCore/Public/CommentRelayLogger.swift
import Foundation
import os

public protocol CommentRelayLogger: Sendable {
    func log(level: CommentRelayLogLevel, message: String, error: Error?)
}

public enum CommentRelayLogLevel: Sendable { case debug, info, warning, error }

public struct DefaultLogger: CommentRelayLogger {
    private let logger = Logger(subsystem: "com.commentrelay.sdk", category: "core")
    public init() {}
    public func log(level: CommentRelayLogLevel, message: String, error: Error?) {
        let detail = error.map { " error=\($0)" } ?? ""
        switch level {
        case .debug: logger.debug("\(message)\(detail, privacy: .public)")
        case .info: logger.info("\(message)\(detail, privacy: .public)")
        case .warning: logger.warning("\(message)\(detail, privacy: .public)")
        case .error: logger.error("\(message)\(detail, privacy: .public)")
        }
    }
}

public enum CommentRelayLoggerHolder {
    nonisolated(unsafe) public static var shared: CommentRelayLogger = DefaultLogger()
}
