//
//  PingInvite.swift
//  HotMess
//

import Contacts
import ContactsUI
import MessageUI
import SwiftUI
import UIKit

/// Someone from the phone's contacts who gets a text with a link to the Ping
/// once it's sent. Picked per send and never sent to the server.
struct PingContact: Hashable, Sendable, Identifiable {
    let name: String
    let phone: String

    /// The number, so the same person picked twice is one recipient.
    var id: String { phone }

    /// `existing` with the people in `picked` it doesn't already have, in
    /// the order they were picked.
    static func merging(_ picked: [PingContact], into existing: [PingContact]) -> [PingContact] {
        var contacts = existing
        for contact in picked where !contacts.contains(where: { $0.phone == contact.phone }) {
            contacts.append(contact)
        }
        return contacts
    }

    /// The number to text out of a contact's numbers: a mobile one when
    /// there is one, else the first.
    static func preferredPhone(_ numbers: [(label: String?, value: String)]) -> String? {
        let mobile = [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone]
        let numbers = numbers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        return (numbers.first { mobile.contains($0.label ?? "") } ?? numbers.first)?.value
    }
}

/// The text the picked contacts get from the sender's own Messages, with the
/// Ping's signed link.
struct PingInvitation: Identifiable, Hashable, Sendable {
    let id = UUID()
    let recipients: [String]
    let body: String

    /// "I'm going out tonight: Drag Bingo or The Wildrose. Come with? <url>",
    /// or without the picks for a Ping that's "anywhere". The note stays out,
    /// as the link shows it.
    static func message(placeNames: [String], url: URL) -> String {
        let names = placeNames.filter { !$0.isEmpty }
        guard let last = names.last else {
            return String(localized: "I'm going out tonight. Come with? \(url.absoluteString)")
        }
        let places = names.count == 1
            ? last
            : String(localized: "\(names.dropLast().joined(separator: ", ")) or \(last)")
        return String(localized: "I'm going out tonight: \(places). Come with? \(url.absoluteString)")
    }

    static func message(for ping: Ping, url: URL) -> String {
        message(placeNames: ping.targets.map(\.name), url: url)
    }
}

/// The system contact picker, phone numbers only and several people at once.
/// It needs no Contacts permission: the user hands over only who they pick.
///
/// `CNContactPickerViewController` doesn't work embedded in a SwiftUI sheet,
/// so this sits in the background and presents it from UIKit.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([PingContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ presenter: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, presenter.presentedViewController == nil else { return }

        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        presenter.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var parent: ContactPicker

        init(parent: ContactPicker) {
            self.parent = parent
        }

        /// Implementing the plural form is what lets the user pick several.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let picked = contacts.compactMap { contact -> PingContact? in
                // Reading a key the picker didn't fetch throws an Objective-C
                // exception, so check first.
                guard contact.isKeyAvailable(CNContactPhoneNumbersKey) else { return nil }
                let numbers = contact.phoneNumbers.map { (label: $0.label, value: $0.value.stringValue) }
                guard let phone = PingContact.preferredPhone(numbers) else { return nil }
                let nameKeys = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
                let name = contact.areKeysAvailable([nameKeys])
                    ? CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                    : ""
                return PingContact(name: name.isEmpty ? phone : name, phone: phone)
            }
            parent.isPresented = false
            parent.onPick(picked)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// Messages, pre-addressed with the invitation, or the share sheet with the
/// same text where the device can't text (an iPad, no SIM). `onFinish` runs
/// once it's sent, cancelled or shared.
struct PingInvitationComposer: UIViewControllerRepresentable {
    let invitation: PingInvitation
    let onFinish: () -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> UIViewController {
        if Self.canSendText {
            let controller = MFMessageComposeViewController()
            controller.recipients = invitation.recipients
            controller.body = invitation.body
            controller.messageComposeDelegate = context.coordinator
            return controller
        }

        let controller = UIActivityViewController(activityItems: [invitation.body], applicationActivities: nil)
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { coordinator.onFinish() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            onFinish()
        }
    }
}
