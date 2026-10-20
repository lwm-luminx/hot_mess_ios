//
//  PairUpScanner.swift
//  HotMess
//

import AVFoundation
import SwiftUI
import VisionKit

/// Scans a Pair me up partner's QR code: a sheet that hands over the first
/// code it reads. The same camera Velvet's door uses (VisionKit).
struct PairUpScanner: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorized = false
    @State private var checking = true
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            Group {
                if checking {
                    ProgressView(String(localized: "Preparing camera…"))
                } else if let scannerError {
                    ContentUnavailableView(
                        String(localized: "Scanner unavailable"),
                        systemImage: "camera",
                        description: Text(scannerError)
                    )
                } else if authorized, DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    PairUpCamera(onCode: { code in
                        onCode(code)
                        dismiss()
                    }, onError: { scannerError = $0 })
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        String(localized: "Camera unavailable"),
                        systemImage: "camera",
                        description: Text("Allow camera access for Hot Mess in Settings to scan their code.")
                    )
                }
            }
            .navigationTitle(String(localized: "Scan their code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .task {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
            checking = false
        }
    }
}

private struct PairUpCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do {
            try controller.startScanning()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in onError(message) }
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onError(error.localizedDescription)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item, let value = barcode.payloadStringValue else { continue }
                delivered = true
                dataScanner.stopScanning()
                onCode(value)
                return
            }
        }
    }
}
