//
//  ChatPrompts.swift
//  HotMess
//

import SwiftUI

// An event chat's prompts (design system "Chat prompts"): the PromptBar under
// the room's title for tonight's rotating prompt, the TriviaCard in its place
// for a trivia question, the PromptCard a quiet room gets in its thread, and
// the composer's AnswerChip. Prompts are the audience talking, so they carry
// the audience's mark (AudienceMark), never a person's photo or a RoleTag.
// The answers themselves are ordinary bubbles with a "Prompt" label (ChatBubble).

/// The 3pt stripe of spectrum bands along the top of a prompt. Decoration
/// only: the overline is what says it's a prompt.
struct SpectrumStripe: View {
    var height: CGFloat = 3

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Color.hotMessSpectrum.indices, id: \.self) { index in
                Color.hotMessSpectrum[index]
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The audience's mark beside a prompt: its first letter on the accent, round
/// like a person's TinyAvatar but never a photo.
struct AudienceMark: View {
    /// The audience's name, as the prompt was posted ("Hot Mess").
    let name: String?
    var size: CGFloat = ChatMetrics.avatarSize

    var body: some View {
        Text(letter)
            .font(.hotMess(fixedSize: size * 0.5, weight: .extraBold))
            .foregroundStyle(Color.hotMessOnAccent)
            .frame(width: size, height: size)
            .background(Color.hotMessAccent, in: .circle)
            .accessibilityHidden(true)
    }

    private var letter: String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.first.map { String($0).uppercased() } ?? "H"
    }
}

/// The audience's name for a prompt's who-line, when the room didn't send one.
enum PromptAuthor {
    static func name(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return String(localized: "Hot Mess") }
        return name
    }
}

// MARK: - PromptBar

/// Tonight's prompt under the room's title (design system "PromptBar"), or a
/// TriviaCard in its place for a trivia question. Open, it's the prompt in
/// full with "14 answers · Next one at 9:15 PM" and "Answer"; collapsed (once
/// the reader scrolls back, or under a pinned announcement) it's one line.
struct PromptBar: View {
    let prompt: ChatPrompt
    /// How many answers the room has shown; 0 says nothing.
    var answers = 0
    var isCollapsed = false
    var now: Date = .now
    /// Outlined for a moment: an answer's label just brought the reader here.
    var isHighlighted = false
    /// "Answer". Without it there's no button.
    var onAnswer: (() -> Void)? = nil
    /// Tapping the folded bar opens it. Without it the folded bar is only text.
    var onExpand: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpectrumStripe()

            if isCollapsed {
                collapsed
            } else if prompt.isTrivia {
                TriviaContent(prompt: prompt, answers: answers, now: now, onAnswer: onAnswer)
            } else {
                open
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: HotMessRadius.lg, style: .continuous))
        .overlay {
            PromptHighlight(isOn: isHighlighted)
        }
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.prompt")
    }

    /// The disc, the overline and the prompt, then the footer and "Answer".
    private var open: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.hotMessAccentInk)
                    .frame(width: 28, height: 28)
                    .background(Color.hotMessAccentSoft, in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    PromptOverline(text: prompt.overline)
                    ExpandablePromptText(text: prompt.text, font: .hotMess(.subheadline, semibold: true))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }

            HStack(spacing: 8) {
                if let footer = PromptFooter.text(answers: answers, nextAt: prompt.nextAt, now: now) {
                    Text(footer)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                if let onAnswer {
                    QuietPromptButton(title: String(localized: "Answer"), action: onAnswer)
                }
            }
            .padding(.leading, 38)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// "PROMPT", the prompt on one line, "Answer". Tapping the line opens the bar.
    private var collapsed: some View {
        HStack(spacing: 8) {
            if let onExpand {
                Button(action: onExpand) {
                    collapsedLine
                        .frame(minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Shows the whole prompt"))
                .accessibilityIdentifier("chat.prompt.expand")
            } else {
                collapsedLine
            }

            if let onAnswer {
                QuietPromptButton(title: String(localized: "Answer"), action: onAnswer)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: 36)
    }

    private var collapsedLine: some View {
        HStack(spacing: 8) {
            PromptOverline(text: prompt.label)
            Text(prompt.text)
                .font(.hotMess(.footnote, semibold: true))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The PromptBar's footer: "14 answers · Next one at 9:15 PM", either part
/// alone, or `nil` with neither.
enum PromptFooter {
    static func text(answers: Int, nextAt: Date?, now: Date = .now) -> String? {
        var parts: [String] = []
        if let count = answerCount(answers) {
            parts.append(count)
        }
        if let nextAt, nextAt > now {
            parts.append(String(localized: "Next one at \(ChatTime.clock(nextAt))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1 answer", "14 answers"; `nil` for none.
    static func answerCount(_ answers: Int) -> String? {
        switch answers {
        case ..<1: nil
        case 1: String(localized: "1 answer")
        default: String(localized: "\(answers) answers")
        }
    }
}

// MARK: - TriviaCard

/// A trivia question in the PromptBar's place (design system "TriviaCard"):
/// "Trivia · 3 of 6" with the answers so far, the question, a nudge to talk
/// to the table first, and the answer hidden until the reader taps "Show the
/// answer" or it's `revealAt` for everyone.
private struct TriviaContent: View {
    let prompt: ChatPrompt
    let answers: Int
    let now: Date
    let onAnswer: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PromptOverline(text: prompt.overline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = PromptFooter.answerCount(answers) {
                    Text(count)
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                }
            }

            ExpandablePromptText(text: prompt.text, font: .hotMess(.headline, semibold: true), isHeader: true)

            TriviaAnswer(prompt: prompt, now: now, onAnswer: onAnswer)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

/// "Shout it to your table before you look it up.", the answer (when shown),
/// "Show the answer" / "Hide the answer" and "Answer".
private struct TriviaAnswer: View {
    let prompt: ChatPrompt
    let now: Date
    let onAnswer: (() -> Void)?

    /// The reader's own choice; until they make one, the answer shows from
    /// `revealAt`.
    @State private var shows: Bool?

    private var isShowing: Bool { shows ?? prompt.isRevealed(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let answer = prompt.answer, isShowing {
                Label {
                    Text(answer)
                        .font(.hotMess(.subheadline, semibold: true))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.hotMessSuccess)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.hotMessSuccessSoft, in: .rect(cornerRadius: HotMessRadius.md))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Answer: \(answer)"))
            } else {
                Text("Shout it to your table before you look it up.")
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if prompt.answer != nil {
                    Button(isShowing ? String(localized: "Hide the answer") : String(localized: "Show the answer")) {
                        withAnimation(HotMessMotion.quick) { shows = !isShowing }
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .controlSize(.small)
                    .font(.hotMess(.footnote, semibold: true))
                }

                if let onAnswer {
                    QuietPromptButton(title: String(localized: "Answer"), action: onAnswer)
                }
            }
        }
    }
}

// MARK: - PromptCard

/// A prompt dropped into a quiet room (design system "PromptCard"): the
/// stripe, "Hot Mess · Prompt · 9:14 PM" beside the audience's mark, the
/// prompt, then "Answer" and "Not now", which hides it for this reader only.
/// It stands alone in the thread, centred, up to 330 wide.
struct PromptCard: View {
    let prompt: ChatPrompt
    /// The audience's name, as the room sent it.
    let author: String?
    let sentAt: Date?
    var now: Date = .now
    var onAnswer: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    /// Outlined for a moment: an answer's label just brought the reader here.
    var isHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpectrumStripe()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AudienceMark(name: author)
                    whoLine
                        .font(.hotMess(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Text(prompt.text)
                    .font(.hotMess(.headline, semibold: true))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if prompt.isTrivia {
                    TriviaAnswer(prompt: prompt, now: now, onAnswer: nil)
                }

                HStack(spacing: 8) {
                    if let onAnswer {
                        Button(String(localized: "Answer"), action: onAnswer)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .font(.hotMess(.footnote, semibold: true))
                    }

                    if let onDismiss {
                        Button(String(localized: "Not now"), action: onDismiss)
                            .buttonStyle(.bordered)
                            .tint(.primary)
                            .controlSize(.small)
                            .font(.hotMess(.footnote, semibold: true))
                            .accessibilityHint(String(localized: "Hides this prompt for you"))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: HotMessRadius.lg, style: .continuous))
        .overlay {
            PromptHighlight(isOn: isHighlighted)
        }
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.promptCard")
    }

    /// "**Hot Mess** · Prompt · 9:14 PM".
    private var whoLine: Text {
        let name = Text(PromptAuthor.name(author)).font(.hotMess(.footnote, semibold: true)).foregroundStyle(.primary)
        guard let sentAt else { return Text("\(name) · \(prompt.label)") }
        return Text("\(name) · \(prompt.label) · \(ChatTime.clock(sentAt))")
    }
}

// MARK: - Answer chip

/// Over the composer's field while the reader answers a prompt: "Answering
/// the prompt", the prompt on one line, and a close button.
struct AnswerChip: View {
    let prompt: ChatPrompt
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.hotMessAccentInk)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Answering the prompt")
                    .font(.hotMess(.footnote, semibold: true))
                    .foregroundStyle(Color.hotMessAccentInk)
                Text(prompt.text)
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stop answering the prompt"))
        }
        .padding(.leading, 10)
        .padding(.vertical, 2)
        .padding(.trailing, 2)
        .background(Color.hotMessAccentSoft, in: .rect(cornerRadius: HotMessRadius.lg))
        .accessibilityIdentifier("chat.answering")
    }
}

// MARK: - Pieces

/// The small uppercase `accent-ink` line over a prompt: "Tonight's prompt · 2 of 6".
private struct PromptOverline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.hotMess(fixedSize: 12, semibold: true))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.hotMessAccentInk)
            .lineLimit(1)
    }
}

/// The accent outline a prompt gets for a moment when an answer's label
/// brings the reader to it.
private struct PromptHighlight: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: HotMessRadius.lg, style: .continuous)
            .strokeBorder(Color.hotMessAccent, lineWidth: 2)
            .opacity(isOn ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A prompt's text, held to three lines with a quiet "Show more" when it
/// runs longer, and "Show less" once open.
private struct ExpandablePromptText: View {
    let text: String
    let font: Font
    var isHeader = false

    static let lineLimit = 3

    @State private var isExpanded = false
    /// The text's height at three lines, and in full: it's truncated when
    /// the full height is taller.
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(font)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : Self.lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if !isExpanded { clampedHeight = height }
                }
                // The full text, unseen, to tell whether three lines cut it short.
                .background(alignment: .topLeading) {
                    Text(text)
                        .font(font)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            fullHeight = height
                        }
                }
                .accessibilityAddTraits(isHeader ? .isHeader : [])

            if isExpanded || isTruncated {
                Button {
                    withAnimation(HotMessMotion.quick) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? String(localized: "Show less") : String(localized: "Show more"))
                        .font(.hotMess(.footnote, semibold: true))
                        .foregroundStyle(Color.hotMessAccentInk)
                        .frame(minHeight: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded
                    ? String(localized: "Shows the prompt in three lines")
                    : String(localized: "Shows the whole prompt"))
            }
        }
    }
}

/// A quiet, accent-ink text button: the PromptBar's "Answer".
private struct QuietPromptButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hotMess(.footnote, semibold: true))
                .foregroundStyle(Color.hotMessAccentInk)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

private enum ChatPromptPreviewData {
    static let start = Date(timeIntervalSince1970: 1_791_590_400)

    static let pinned = ChatPrompt(
        id: "p2", text: "Who should have won last season? Find someone at the bar who disagrees.",
        shownAs: .pinned, number: 2, total: 6, nextAt: start.addingTimeInterval(4500)
    )

    static let trivia = ChatPrompt(
        id: "p3", kind: .trivia, text: "Who won the very first season of RuPaul's Drag Race?",
        answer: "BeBe Zahara Benet", revealAt: start.addingTimeInterval(600), shownAs: .pinned, number: 3, total: 6
    )

    static let card = ChatPrompt(
        id: "p4", text: "Ask whoever is next to you what brought them out tonight. Then tell the room.",
        shownAs: .card, number: 4, total: 6
    )
}

#Preview("Prompts") {
    ScrollView {
        VStack(spacing: 16) {
            PromptBar(prompt: ChatPromptPreviewData.pinned, answers: 14, now: ChatPromptPreviewData.start) {}
            PromptBar(prompt: ChatPromptPreviewData.pinned, isCollapsed: true) {}
            PromptBar(prompt: ChatPromptPreviewData.trivia, answers: 9, now: ChatPromptPreviewData.start) {}
            PromptCard(
                prompt: ChatPromptPreviewData.card, author: "Hot Mess", sentAt: ChatPromptPreviewData.start,
                onAnswer: {}, onDismiss: {}
            )
            .frame(maxWidth: ChatMetrics.promptCardMaxWidth)
            AnswerChip(prompt: ChatPromptPreviewData.card) {}
            HStack {
                ChatBubble(text: "Plane Jane, fight me", isOwn: false, label: "Prompt")
                ChatBubble(text: "BeBe, obviously", isOwn: true, label: "Trivia")
            }
        }
        .padding(12)
    }
    .background(Color(.systemGroupedBackground))
}
