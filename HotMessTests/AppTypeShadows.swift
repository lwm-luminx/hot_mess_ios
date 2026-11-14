//
//  AppTypeShadows.swift
//  HotMessTests
//
//  AudienceKit exports public types with the same names as some of the app's
//  own models. The app sees its own module's types first, but these tests
//  import both AudienceKit and `@testable HotMess`, so a bare name such as
//  `Event` is ambiguous. These aliases live in the test module, which Swift
//  searches before either import, so a bare name means the app's model.
//  Write `AudienceKit.Venue` (etc.) when a test means the SDK type.
//
//  When an AudienceKit bump adds another clashing name, add it here.
//

@testable import HotMess

typealias Admission = HotMess.Admission
typealias AdmissionStatus = HotMess.AdmissionStatus
typealias CalendarFeed = HotMess.CalendarFeed
typealias ChatRoom = HotMess.ChatRoom
typealias CoverCharge = HotMess.CoverCharge
typealias CoverPass = HotMess.CoverPass
typealias CoverPurchase = HotMess.CoverPurchase
typealias Event = HotMess.Event
typealias Friend = HotMess.Friend
typealias LineupEntry = HotMess.LineupEntry
typealias Money = HotMess.Money
typealias Person = HotMess.Person
typealias Profile = HotMess.Profile
typealias ReportTarget = HotMess.ReportTarget
typealias SocialLink = HotMess.SocialLink
typealias Venue = HotMess.Venue
