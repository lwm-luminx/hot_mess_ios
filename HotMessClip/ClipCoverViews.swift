import CoreImage.CIFilterBuiltins
import SwiftUI

struct ClipDetailsView: View {
    let details: ClipDetails
    @Bindable var checkout: CoverCheckout
    @State private var tier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let event = details.event {
                Text(event.name).font(.title2.bold())
                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                if let description = event.description { Text(description) }
            }
            if let venue = details.venue {
                Text(venue.name).font(.title2.bold())
                if let description = venue.description { Text(description) }
                if let pass = venue.tickets?.cover?.viewerAdmission, pass.isPaid {
                    Button("Show your pass") { checkout.show(pass) }.buttonStyle(.borderedProminent)
                } else if let charge = venue.tickets?.cover?.coverCharge, charge.payable {
                    // buyCover purchases the venue's current night, not necessarily
                    // the event whose link was opened. Show the night explicitly.
                    Text("Cover · \(CoverFormat.night(charge.night))").font(.headline)
                    if let tiers = charge.tiers, !tiers.isEmpty {
                        Picker("Admission", selection: $tier) {
                            Text("General admission · \(charge.price)").tag(String?.none)
                            ForEach(tiers) { item in
                                Text("\(item.name) · \(item.price)").tag(Optional(item.id))
                            }
                        }
                    }
                    let price = charge.tiers?.first(where: { $0.id == tier })?.price ?? charge.price
                    Text("\(price) total, including fees · 1 person")
                    Button(checkout.isBusy ? "Processing…" : "Pay cover \(price)") {
                        Task { await checkout.pay(venueID: venue.id, venueName: venue.name, tier: tier) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checkout.isBusy)
                }
            }
        }
    }
}

struct ClipPassView: View {
    let admission: Admission
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(admission.venueName).font(.title.bold())
                if let name = admission.profile?.name { Text(name).font(.headline) }
                Text(admission.nightTitle)
                Text("\(admission.quantity) admission · \(admission.price)")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let code = admission.passCode(at: context.date), let image = qr(code) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 280).padding().background(.white)
                            .accessibilityLabel("Admission QR code")
                        Text("Refreshes in \(CoverPass.secondsRemaining(at: context.date)) seconds")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Your pass is not ready. Please try again.")
                    }
                }
                Text("Show this pass at the door.")
            }
            .padding()
            .navigationTitle("Your pass")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func qr(_ code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
