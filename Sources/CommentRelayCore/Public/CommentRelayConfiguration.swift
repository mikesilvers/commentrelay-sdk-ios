import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct CommentRelayConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let userIdentifier: String?
    public let locale: String?

    public let sdkVersionOverride: String?
    public let osVersionOverride: String?
    public let deviceModelOverride: String?
    public let appVersionOverride: String?

    public let offlineQueueingEnabled: Bool
    public let maxQueuedSubmissions: Int
    public let maxQueueAge: TimeInterval

    public init(baseURL: URL,
                apiKey: String,
                userIdentifier: String? = nil,
                locale: String? = nil,
                sdkVersionOverride: String? = nil,
                osVersionOverride: String? = nil,
                deviceModelOverride: String? = nil,
                appVersionOverride: String? = nil,
                offlineQueueingEnabled: Bool = true,
                maxQueuedSubmissions: Int = 50,
                maxQueueAge: TimeInterval = 30 * 24 * 60 * 60) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.userIdentifier = userIdentifier
        self.locale = locale
        self.sdkVersionOverride = sdkVersionOverride
        self.osVersionOverride = osVersionOverride
        self.deviceModelOverride = deviceModelOverride
        self.appVersionOverride = appVersionOverride
        self.offlineQueueingEnabled = offlineQueueingEnabled
        self.maxQueuedSubmissions = maxQueuedSubmissions
        self.maxQueueAge = maxQueueAge
    }

    public var effectiveSDKVersion: String {
        sdkVersionOverride ?? CommentRelay.version
    }

    public var effectiveOSVersion: String {
        if let v = osVersionOverride { return v }
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    public var effectiveDeviceModel: String {
        if let v = deviceModelOverride { return v }
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    public var effectiveAppVersion: String? {
        appVersionOverride
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
