import SwiftUI
import VisionKit

// MARK: - BarcodeScannerSheet
// Wrapper mit Close-Button — wird als .fullScreenCover präsentiert

struct BarcodeScannerSheet: View {
    let onBarcodeFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BarcodeScannerRepresentable { code in
                dismiss()
                onBarcodeFound(code)
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
            .padding(.top, 56)
            .padding(.trailing, 20)
        }
    }
}

// MARK: - BarcodeScannerRepresentable
// UIViewControllerRepresentable um DataScannerViewController

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcodeFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes:           [.barcode()],
            qualityLevel:                  .accurate,
            recognizesMultipleItems:       false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled:             true,
            isHighlightingEnabled:         true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // Scanning starten sobald der VC aktiv ist
        if !vc.isScanning {
            try? vc.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeFound: onBarcodeFound)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onBarcodeFound: (String) -> Void
        private var didFire = false  // verhindert doppelte Callbacks

        init(onBarcodeFound: @escaping (String) -> Void) {
            self.onBarcodeFound = onBarcodeFound
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFire else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    didFire = true
                    dataScanner.stopScanning()
                    onBarcodeFound(value)
                    return
                }
            }
        }
    }
}
