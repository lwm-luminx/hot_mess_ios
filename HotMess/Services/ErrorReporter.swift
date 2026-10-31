//
//  ErrorReporter.swift
//  HotMess
//

import AudienceKit
import Foundation
@preconcurrency import MetricKit
import UIKit

/// Sends crashes and errors to the AudienceKit API (`POST /v1/client_errors`),
/// which logs each one as a `[client_error]` line in its Heroku log, and keeps
/// the last few so "Report a Problem" can attach them.
///
/// Crashes come from MetricKit: iOS hands the app a crash's diagnostic, call
/// stacks included, on a later launch, so nothing has to survive the crash
/// itself. Errors are API failures that point at a bug rather than at the
/// network: a response the app couldn't decode, or a server error.
@MainActor
final class ErrorReporter: NSObject {
    static let shared = ErrorReporter()

    /// One thing that went wrong, as "Report a Problem" attaches it.
    struct Entry: Codable, Equatable, Sendable {
        var kind: String
        var message: String
        var at: Date
    }

    /// What `/v1/client_errors` takes.
    struct Report: Encodable, Equatable, Sendable {
        var app = "ios"
        var kind: String
        var message: String
        var stack: String?
        var screen: String?
        var version: String?
        var build: String?
        var osVersion: String?
        var device: String?

        enum CodingKeys: String, CodingKey {
            case app, kind, message, stack, screen, version, build, device
            case osVersion = "os_version"
        }
    }

    static let maxRecent = 20
    static let maxSentPerLaunch = 30

    private(set) var recent: [Entry] = []
    private var sentFingerprints: Set<String> = []
    private var audienceKit: AudienceKitClient?
    private var configuration: AppConfiguration?

    /// Starts listening for MetricKit diagnostics. Reports go nowhere before this.
    func start(audienceKit: AudienceKitClient, configuration: AppConfiguration) {
        guard self.audienceKit == nil else { return }
        self.audienceKit = audienceKit
        self.configuration = configuration
        MXMetricManager.shared.add(self)
    }

    /// Notes a failed API call. Every failure is kept for "Report a Problem";
    /// only the ones that point at a bug are sent.
    func record(_ error: APIError, operation: String) {
        remember(kind: "api", message: "\(operation): \(error.reportDescription)")
        guard error.isReportable else { return }
        send(Report(kind: "error", message: "\(operation): \(error.reportDescription)"))
    }

    /// Notes something that went wrong outside the API, e.g. a failed sign-in.
    func record(kind: String, message: String, send shouldSend: Bool = false) {
        remember(kind: kind, message: message)
        if shouldSend { send(Report(kind: kind, message: message)) }
    }

    // MARK: - Private

    private func remember(kind: String, message: String) {
        recent.append(Entry(kind: kind, message: String(message.prefix(500)), at: .now))
        if recent.count > Self.maxRecent { recent.removeFirst(recent.count - Self.maxRecent) }
    }

    private func send(_ report: Report) {
        let fingerprint = "\(report.kind):\(report.message)"
        guard let audienceKit, let configuration,
              !sentFingerprints.contains(fingerprint),
              sentFingerprints.count < Self.maxSentPerLaunch else { return }
        sentFingerprints.insert(fingerprint)

        var completed = report
        // A crash names only its own build, so it isn't given this build's version.
        completed.version = report.version ?? (report.build == nil ? configuration.version : nil)
        completed.build = report.build ?? String(configuration.build)
        completed.osVersion = report.osVersion ?? "iOS \(UIDevice.current.systemVersion)"
        completed.device = report.device ?? DeviceInfo.model

        let signedIn = SessionStore.credentialStore.hasCredential
        let body = try? JSONEncoder().encode(completed)
        Task.detached(priority: .utility) {
            guard let body else { return }
            let request = APIRequest(method: "POST", path: "/v1/client_errors", body: body, authenticated: signedIn)
            // Reporting must never cause an error of its own.
            _ = try? await audienceKit.data(for: request)
        }
    }

    fileprivate func sendCrashes(_ reports: [Report]) {
        for report in reports {
            remember(kind: report.kind, message: report.message)
            send(report)
        }
    }
}

// MARK: - MetricKit

extension ErrorReporter: MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map(Self.report(for:))
        }
        guard !reports.isEmpty else { return }
        Task { @MainActor in ErrorReporter.shared.sendCrashes(reports) }
    }

    /// A crash as `/v1/client_errors` takes it: what killed the app as the
    /// message, and MetricKit's call stack tree, as JSON, as the stack.
    nonisolated static func report(for crash: MXCrashDiagnostic) -> Report {
        let metadata = crash.metaData
        return crashReport(
            exceptionType: crash.exceptionType?.intValue,
            exceptionCode: crash.exceptionCode?.intValue,
            signal: crash.signal?.intValue,
            terminationReason: crash.terminationReason,
            stack: String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self),
            // The crash may be from an earlier build, so its build number is the crash's own.
            version: nil,
            build: metadata.applicationBuildVersion,
            osVersion: metadata.osVersion,
            device: metadata.deviceType
        )
    }

    nonisolated static func crashReport(
        exceptionType: Int?,
        exceptionCode: Int?,
        signal: Int?,
        terminationReason: String?,
        stack: String?,
        version: String?,
        build: String?,
        osVersion: String?,
        device: String?
    ) -> Report {
        var parts: [String] = []
        if let exceptionType { parts.append("exception \(exceptionType)") }
        if let exceptionCode { parts.append("code \(exceptionCode)") }
        if let signal { parts.append("signal \(signal)") }
        if let terminationReason, !terminationReason.isEmpty { parts.append(terminationReason) }

        return Report(
            kind: "crash",
            message: parts.isEmpty ? "Crash" : "Crash: " + parts.joined(separator: ", "),
            stack: stack,
            version: version,
            build: build,
            osVersion: osVersion,
            device: device
        )
    }
}

// MARK: - API errors

extension APIError {
    /// Whether this failure points at a bug worth sending, rather than at the
    /// network or the session.
    var isReportable: Bool {
        switch self {
        case .decoding, .invalidURL: true
        case let .server(status): status >= 500
        case .offline, .unauthorized, .notFound, .transport, .termsNotAccepted: false
        }
    }

    var reportDescription: String {
        switch self {
        case let .decoding(detail): "decoding failed: \(detail)"
        case let .server(status): "HTTP \(status)"
        case let .transport(message): message
        default: String(describing: self)
        }
    }
}

extension CredentialStore {
    var hasCredential: Bool { (try? load()) != nil }
}
