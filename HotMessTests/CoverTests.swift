//
//  CoverTests.swift
//  HotMessTests
//

import Foundation
import Testing

@testable import HotMess

private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
    try JSONDecoder.hotMess.decode(type, from: Data(json.utf8))
}

@Suite("Cover pass codes")
struct CoverPassTests {
    static let admissionID = "7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b"
    static let secret = "c2VjcmV0LWtleS1mb3ItaG90LW1lc3MtY292ZXI="
    static let start = Date(timeIntervalSince1970: 1_791_331_200)

    /// Computed with the API's own recipe (app/services/cover_pass.rb):
    ///
    ///     ruby -ropenssl -rbase64 -e 'k = Base64.strict_decode64(SECRET); w = 1791331200 / 30
    ///       puts Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", k, "#{ID}.#{w}"), padding: false)[0, 16]'
    @Test("Matches the API's code for the same pass and time")
    func matchesTheAPI() {
        #expect(CoverPass.window(at: Self.start) == 59_711_040)
        #expect(
            CoverPass.code(admissionID: Self.admissionID, secret: Self.secret, at: Self.start)
                == "HMC1.7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b.59711040.HOStwur5mLjF7zvb"
        )
    }

    @Test("Holds for the window, then changes, with URL-safe signatures")
    func changesEveryThirtySeconds() {
        #expect(
            CoverPass.code(admissionID: Self.admissionID, secret: Self.secret, at: Self.start.addingTimeInterval(29.9))
                == "HMC1.7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b.59711040.HOStwur5mLjF7zvb"
        )
        // This window's signature has a "-", which plain Base64 would write as "+".
        #expect(
            CoverPass.code(admissionID: Self.admissionID, secret: Self.secret, at: Self.start.addingTimeInterval(30))
                == "HMC1.7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b.59711041.p2tYO-g5T45lRFzN"
        )
        #expect(CoverPass.secondsRemaining(at: Self.start) == 30)
        #expect(CoverPass.secondsRemaining(at: Self.start.addingTimeInterval(12)) == 18)
    }

    @Test("Makes nothing from a secret that isn't Base64")
    func badSecret() {
        #expect(CoverPass.code(admissionID: Self.admissionID, secret: "not base64!", at: Self.start) == nil)
    }

    @Test("Only paid passes with a secret have a code")
    func admissionCode() {
        let paid = Admission(id: Self.admissionID, status: .paid, night: "2026-10-09", total: Money(cents: 1112), passSecret: Self.secret)
        #expect(paid.passCode(at: Self.start)?.hasSuffix(".HOStwur5mLjF7zvb") == true)

        let refunded = Admission(id: Self.admissionID, status: .refunded, night: "2026-10-09", total: Money(cents: 1112), passSecret: Self.secret)
        #expect(refunded.passCode(at: Self.start) == nil)
    }
}

@Suite("Cover decoding")
struct CoverDecodingTests {
    static let admission = """
    {
      "id": "7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b",
      "status": "PAID",
      "night": "2026-10-09",
      "total": { "cents": 1112, "currency": "usd" },
      "is_refundable": true,
      "pass_secret": "c2VjcmV0LWtleS1mb3ItaG90LW1lc3MtY292ZXI=",
      "scan_count": 0,
      "checked_in_at": null,
      "profile": { "id": "0A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "name": "Rick Mark", "avatar_url": "https://cdn.hotmess.social/users/rick.jpg" },
      "venue": { "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11", "name": "The Stud", "photo_url": null },
      "event": { "id": "e-1", "name": "Club Some Thing" }
    }
    """

    @Test("Reads a pass, keeping its ID as sent")
    func admission() throws {
        let admission = try decode(Admission.self, from: Self.admission)

        #expect(admission.id == "7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b")
        #expect(admission.isPaid)
        #expect(admission.isRefundable)
        #expect(admission.venueName == "The Stud")
        #expect(admission.venueID == UUID(uuidString: "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11"))
        #expect(admission.eventName == "Club Some Thing")
        #expect(admission.total == Money(cents: 1112, currency: "usd"))
        #expect(admission.profile?.name == "Rick Mark")
        #expect(admission.profile?.avatarURL?.lastPathComponent == "rick.jpg")
    }

    @Test("A status from a newer API doesn't break the pass")
    func unknownStatus() throws {
        let admission = try decode(Admission.self, from: Self.admission.replacingOccurrences(of: "\"PAID\"", with: "\"ON_HOLD\""))
        #expect(admission.status == .unknown)
        #expect(!admission.isPaid)
    }

    @Test("Reads a venue's cover and the user's pass on Now")
    func nowCover() throws {
        let json = """
        {
          "title": "The Stud",
          "venue": {
            "id": "8B4F1B60-9A5D-4D0E-9B3F-2C6B3E5D8A11",
            "name": "The Stud",
            "tickets": {
              "cover": {
                "cover_charge": {
                  "amount": { "cents": 1000, "currency": "usd" }, "fee": { "cents": 112, "currency": "usd" },
                  "total": { "cents": 1112, "currency": "usd" },
                  "night": "2026-10-09", "from": "21:00", "until": null, "payable": true
                },
                "viewer_admission": \(Self.admission)
              }
            }
          }
        }
        """
        let now = try decode(Now.self, from: json)

        #expect(now.coverCharge?.total.cents == 1112)
        #expect(now.coverCharge?.fee.cents == 112)
        #expect(now.coverCharge?.payable == true)
        #expect(now.viewerAdmission?.isPaid == true)
    }

    @Test("Reads a pass with quantity and tier, defaulting quantity to 1 when omitted")
    func admissionQuantityAndTier() throws {
        let defaultAdmission = try decode(Admission.self, from: Self.admission)
        #expect(defaultAdmission.quantity == 1)
        #expect(defaultAdmission.tier == nil)

        let multipleJson = """
        {
          "id": "7d9f2c1e-3b4a-4e5f-8a6b-1c2d3e4f5a6b",
          "status": "PAID",
          "night": "2026-10-09",
          "total": { "cents": 2224, "currency": "usd" },
          "quantity": 2,
          "tier": "vip"
        }
        """
        let multipleAdmission = try decode(Admission.self, from: multipleJson)
        #expect(multipleAdmission.quantity == 2)
        #expect(multipleAdmission.tier == "vip")
    }

    @Test("Reads payment mechanisms and tiers on cover charge")
    func coverChargeMechanismsAndTiers() throws {
        let json = """
        {
          "amount": { "cents": 1000, "currency": "usd" },
          "fee": { "cents": 112, "currency": "usd" },
          "total": { "cents": 1112, "currency": "usd" },
          "night": "2026-10-09",
          "payable": true,
          "payment_mechanisms": ["apple_pay"],
          "tiers": [
            {
              "id": "general",
              "name": "General Admission",
              "description": "Standard entry",
              "amount": { "cents": 1000, "currency": "usd" },
              "fee": { "cents": 112, "currency": "usd" },
              "total": { "cents": 1112, "currency": "usd" }
            },
            {
              "id": "vip",
              "name": "VIP",
              "amount": { "cents": 2500, "currency": "usd" },
              "fee": { "cents": 250, "currency": "usd" },
              "total": { "cents": 2750, "currency": "usd" }
            }
          ]
        }
        """
        let cover = try decode(CoverCharge.self, from: json)
        #expect(cover.paymentMechanisms == ["apple_pay"])
        #expect(cover.supportsApplePay)
        #expect(!cover.hasOtherPaymentMechanisms)
        #expect(cover.tiers?.count == 2)
        #expect(cover.tiers?[1].id == "vip")
        #expect(cover.tiers?[1].total(for: 2) == Money(cents: 5500, currency: "usd"))
        #expect(cover.total(for: 3) == Money(cents: 3336, currency: "usd"))
    }

    @Test("Reads coat check on cover charge and coat check pass on Now")
    func coatCheckDecoding() throws {
        let json = """
        {
          "amount": { "cents": 1000, "currency": "usd" },
          "fee": { "cents": 112, "currency": "usd" },
          "total": { "cents": 1112, "currency": "usd" },
          "night": "2026-10-09",
          "payable": true,
          "coat_check": {
            "amount": { "cents": 500, "currency": "usd" },
            "fee": { "cents": 50, "currency": "usd" },
            "total": { "cents": 550, "currency": "usd" },
            "night": "2026-10-09",
            "payable": true,
            "payment_mechanisms": ["apple_pay", "card"]
          }
        }
        """
        let cover = try decode(CoverCharge.self, from: json)
        let coatCheck = try #require(cover.coatCheck)
        #expect(coatCheck.amount == Money(cents: 500, currency: "usd"))
        #expect(coatCheck.fee == Money(cents: 50, currency: "usd"))
        #expect(coatCheck.total == Money(cents: 550, currency: "usd"))
        #expect(coatCheck.payable)
        #expect(coatCheck.supportsApplePay)
        #expect(coatCheck.hasOtherPaymentMechanisms)
        #expect(coatCheck.price(for: 2).contains("11"))
        #expect(coatCheck.total(for: 2) == Money(cents: 1100, currency: "usd"))
    }

    @Test("Reads coat check admission with kind and claim check number")
    func coatCheckAdmission() throws {
        let json = """
        {
          "id": "cc-pass-123",
          "status": "PAID",
          "night": "2026-10-09",
          "total": { "cents": 550, "currency": "usd" },
          "quantity": 2,
          "kind": "COAT_CHECK",
          "claim_check_number": "42"
        }
        """
        let admission = try decode(Admission.self, from: json)
        #expect(admission.id == "cc-pass-123")
        #expect(admission.kind == .coatCheck)
        #expect(admission.isCoatCheck)
        #expect(admission.claimCheckNumber == "42")
        #expect(admission.quantity == 2)
    }
}

@Suite("Paying cover")
struct CoverPaymentTests {
    static let pending = CoverDecodingTests.admission.replacingOccurrences(of: "\"PAID\"", with: "\"PENDING\"")

    private func decodePurchase(_ fields: String, admission: String = CoverPaymentTests.pending) throws -> CoverPurchase {
        try decode(CoverPurchase.self, from: "{ \"admission\": \(admission), \(fields) }")
    }

    @Test("Stripe venues pay with the payment sheet on the venue's account")
    func stripe() throws {
        let purchase = try decodePurchase("""
        "provider": "STRIPE", "payment_intent_client_secret": "pi_1_secret_2",
        "publishable_key": "pk_live_1", "stripe_account_id": "acct_1",
        "square_application_id": null, "square_location_id": null
        """)

        #expect(!purchase.isSquare)
        #expect(purchase.nextStep == .stripe(clientSecret: "pi_1_secret_2", publishableKey: "pk_live_1", accountID: "acct_1"))
    }

    @Test("A Stripe payment with no client secret is paid already")
    func stripePaid() throws {
        let purchase = try decodePurchase("""
        "provider": "STRIPE", "payment_intent_client_secret": null,
        "publishable_key": "pk_live_1", "stripe_account_id": "acct_1"
        """, admission: CoverDecodingTests.admission)

        #expect(purchase.nextStep == .showPass)
    }

    @Test("An API from before Square still means Stripe")
    func noProvider() throws {
        let purchase = try decodePurchase("""
        "payment_intent_client_secret": "pi_1_secret_2", "publishable_key": "pk_live_1", "stripe_account_id": "acct_1"
        """)

        #expect(purchase.provider == .stripe)
        #expect(purchase.nextStep == .stripe(clientSecret: "pi_1_secret_2", publishableKey: "pk_live_1", accountID: "acct_1"))
    }

    @Test("Stripe without its keys can't be paid in the app")
    func stripeMissingKeys() throws {
        let purchase = try decodePurchase("""
        "provider": "STRIPE", "payment_intent_client_secret": "pi_1_secret_2",
        "publishable_key": null, "stripe_account_id": "acct_1"
        """)

        #expect(purchase.nextStep == .unavailable)
    }

    @Test("Square venues pay with Square's SDK and the audience's application")
    func square() throws {
        let purchase = try decodePurchase("""
        "provider": "SQUARE", "payment_intent_client_secret": null,
        "publishable_key": null, "stripe_account_id": null,
        "square_application_id": "sq0idp-abc", "square_location_id": "L123"
        """)

        #expect(purchase.isSquare)
        #expect(purchase.squareLocationID == "L123")
        #expect(purchase.nextStep == .square(applicationID: "sq0idp-abc"))
    }

    @Test("A paid Square pass goes straight to the pass")
    func squarePaid() throws {
        let purchase = try decodePurchase("""
        "provider": "SQUARE", "square_application_id": "sq0idp-abc", "square_location_id": "L123"
        """, admission: CoverDecodingTests.admission)

        #expect(purchase.nextStep == .showPass)
    }

    @Test("Square without an application ID, or a provider from a newer API, can't be paid in the app")
    func unavailable() throws {
        #expect(try decodePurchase("\"provider\": \"SQUARE\", \"square_application_id\": \" \"").nextStep == .unavailable)

        let newer = try decodePurchase("\"provider\": \"ADYEN\"")
        #expect(newer.provider == .unknown)
        #expect(newer.nextStep == .unavailable)
    }

    @Test("Offers Apple Pay through Square only when it works here and the build has a merchant ID")
    func squareMethods() {
        #expect(SquarePaymentMethod.available(canUseApplePay: true, merchantID: "merchant.social.hotmess") == [.applePay, .card])
        #expect(SquarePaymentMethod.available(canUseApplePay: false, merchantID: "merchant.social.hotmess") == [.card])
        #expect(SquarePaymentMethod.available(canUseApplePay: true, merchantID: nil) == [.card])
        #expect(SquarePaymentMethod.available(canUseApplePay: true, merchantID: "") == [.card])
    }

    @Test("Payment mechanisms properly indicate whether only Apple Pay is supported")
    func paymentMechanismsDetection() {
        let onlyApplePay = CoverCharge(
            amount: Money(cents: 1000),
            total: Money(cents: 1112),
            night: "2026-10-09",
            payable: true,
            paymentMechanisms: ["apple_pay"]
        )
        #expect(onlyApplePay.supportsApplePay)
        #expect(!onlyApplePay.hasOtherPaymentMechanisms)

        let both = CoverCharge(
            amount: Money(cents: 1000),
            total: Money(cents: 1112),
            night: "2026-10-09",
            payable: true,
            paymentMechanisms: ["apple_pay", "card"]
        )
        #expect(both.supportsApplePay)
        #expect(both.hasOtherPaymentMechanisms)

        let cardOnly = CoverCharge(
            amount: Money(cents: 1000),
            total: Money(cents: 1112),
            night: "2026-10-09",
            payable: true,
            paymentMechanisms: ["card"]
        )
        #expect(!cardOnly.supportsApplePay)
        #expect(cardOnly.hasOtherPaymentMechanisms)

        let legacyNil = CoverCharge(
            amount: Money(cents: 1000),
            total: Money(cents: 1112),
            night: "2026-10-09",
            payable: true
        )
        #expect(legacyNil.supportsApplePay)
        #expect(legacyNil.hasOtherPaymentMechanisms)
    }

    @Test("Apple Pay status computes properly for unavailable, needs setup, and ready states")
    func applePayStatus() {
        #expect(ApplePayStatus.current(canMakePayments: false, hasConfiguredCards: false) == .unavailable)
        #expect(ApplePayStatus.current(canMakePayments: false, hasConfiguredCards: true) == .unavailable)
        #expect(ApplePayStatus.current(canMakePayments: true, hasConfiguredCards: false) == .needsSetup)
        #expect(ApplePayStatus.current(canMakePayments: true, hasConfiguredCards: true) == .ready)
    }

    @Test("Apple Pay charges the all-in price in currency units")
    func totalAmount() {
        let admission = Admission(id: "a", status: .pending, night: "2026-10-09", total: Money(cents: 1112))
        #expect(admission.total.amount == Decimal(string: "11.12"))
    }
}

@Suite("Cover formatting")
struct CoverFormattingTests {
    @Test("Shows cents only when there are some")
    func price() {
        #expect(CoverFormat.price(cents: 1112, currency: "usd").contains("11.12"))
        #expect(!CoverFormat.price(cents: 1000, currency: "usd").contains("10.00"))
    }

    @Test("Reads nights as calendar dates")
    func night() throws {
        let date = try #require(CoverFormat.nightDate("2026-10-09"))
        #expect(date == Date(timeIntervalSince1970: 1_791_504_000))
        #expect(CoverFormat.time("21:00") != nil)
        #expect(CoverFormat.time("late") == nil)
    }

    @Test("Says tonight, or the night, and when it starts")
    func summary() {
        let cover = CoverCharge(amount: Money(cents: 1000), total: Money(cents: 1112), night: "2026-10-09", from: "21:00", payable: true)

        #expect(cover.summary(isTonight: true).hasPrefix("Cover \(cover.price) tonight · from "))
        #expect(cover.summary(isTonight: false).hasPrefix("Cover \(cover.price) · "))

        let noStart = CoverCharge(amount: Money(cents: 1000), total: Money(cents: 1000), night: "2026-10-09", payable: false)
        #expect(noStart.summary(isTonight: true) == "Cover \(noStart.price) tonight")
    }

    @Test("Only tonight's event cover can be paid")
    func eventTonight() throws {
        let tonight = CoverCharge(amount: Money(cents: 1000), total: Money(cents: 1112), night: "2026-10-09", payable: true)
        let friday = CoverCharge(amount: Money(cents: 1500), total: Money(cents: 1650), night: "2026-10-10", payable: true)
        let event = Event(id: UUID(), name: "Club Some Thing", startDate: .now)

        #expect(EventDetail(event: event, coverCharge: tonight, venueCoverTonight: tonight).isCoverTonight)
        #expect(!EventDetail(event: event, coverCharge: friday, venueCoverTonight: tonight).isCoverTonight)
        #expect(!EventDetail(event: event, coverCharge: friday).isCoverTonight)
    }
}

@Suite("Sliding-scale cover")
struct CoverScaleTests {
    static let json = """
    {"amount":{"cents":1500,"currency":"usd"},"fee":{"cents":50,"currency":"usd"},"total":{"cents":1647,"currency":"usd"},
     "night":"2026-11-21","from":"21:00","until":null,"payable":true,
     "scale":{"min":{"cents":500,"currency":"usd"},"max":{"cents":3000,"currency":"usd"},"suggested":{"cents":1500,"currency":"usd"}}}
    """

    @Test("Decodes the range and shows it instead of one price")
    func decodes() throws {
        let charge = try decode(CoverCharge.self, from: Self.json)
        #expect(charge.scale?.min.cents == 500)
        #expect(charge.scale?.max.cents == 3000)
        #expect(charge.scale?.suggested.cents == 1500)
        #expect(charge.price == "$5–$30")
        #expect(charge.summary(isTonight: true).contains("$5–$30"))
    }

    @Test("A fixed cover has no scale")
    func fixed() throws {
        let charge = try decode(CoverCharge.self, from: """
        {"amount":{"cents":1000},"fee":{"cents":50},"total":{"cents":1112},"night":"2026-11-21","payable":true}
        """)
        #expect(charge.scale == nil)
        #expect(charge.price == "$11.12")
    }

    @Test("Steps a dollar at a time and stays in range")
    func steps() {
        let scale = CoverScale(min: Money(cents: 550), max: Money(cents: 3000), suggested: Money(cents: 1500))
        #expect(scale.step(1500, by: 1) == 1600)
        #expect(scale.step(1500, by: -1) == 1400)
        #expect(scale.step(1550, by: -1) == 1500)
        #expect(scale.step(600, by: -1) == 550)
        #expect(scale.step(2950, by: 1) == 3000)
        #expect(scale.step(3000, by: 1) == 3000)
        #expect(scale.clamped(100) == 550)
    }
}
