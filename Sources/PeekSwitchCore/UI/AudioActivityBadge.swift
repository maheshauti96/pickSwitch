import SwiftUI

/// Marks a window whose application is playing audio or capturing from the microphone.
///
/// Two glyphs and not one. They answer different questions and a user cares about them for opposite
/// reasons: a speaker is *find the noise*, and a microphone is *something is listening to me*. Folding
/// them into one "media" symbol would make the second unreadable, which is the one that matters more.
///
/// Placement is the reason this takes `isOverArtwork`. Over a thumbnail there is no telling what is
/// behind the glyph — a window preview is arbitrary pixels — so it gets an opaque plate and fixed
/// light colours, the same defence `minimizedBadge` uses. In a metadata row the background is the
/// card, whose colour is known, and a black chip there would read as a warning rather than a status.
struct AudioActivityBadge: View {

    var isPlaying: Bool = false
    var isRecording: Bool = false
    var isOverArtwork: Bool = false
    var isOnAccent: Bool = false

    @Environment(\.overlayPalette) private var palette

    /// Nothing to draw is the overwhelmingly common case, so callers may construct this
    /// unconditionally and let it disappear.
    private var hasAnything: Bool { isPlaying || isRecording }

    private var speakerColor: Color {
        if isOverArtwork { return .white }
        return isOnAccent ? palette.onAccentText : palette.text
    }

    private var microphoneColor: Color {
        // The plate is dark whatever the appearance, so the light theme's darkened orange would be
        // the wrong one there.
        isOverArtwork ? Color(.sRGB, red: 255 / 255, green: 159 / 255, blue: 10 / 255, opacity: 1)
            : palette.microphoneIndicator
    }

    private var glyphSize: CGFloat { isOverArtwork ? 10 : 9 }

    var body: some View {
        if hasAnything {
            HStack(spacing: 3) {
                if isRecording {
                    Image(systemName: "mic.fill")
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(microphoneColor)
                }
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(speakerColor)
                }
            }
            .padding(isOverArtwork ? 4 : 0)
            .background {
                if isOverArtwork {
                    Capsule().fill(.black.opacity(0.55))
                }
            }
            // Spoken by the card's own label instead, so a screen reader hears it once as part of
            // "Google Chrome, YouTube, playing audio" rather than as a stray element after it.
            .accessibilityHidden(true)
            .help(Self.tooltip(isPlaying: isPlaying, isRecording: isRecording))
        }
    }

    /// Wording that admits what this actually knows.
    ///
    /// It says "this app" and not "this window", because that is the truth: CoreAudio reports audio
    /// per process, so every window of a browser playing a video is marked, not the one showing it.
    /// Claiming otherwise in the tooltip would make the badge look broken when a second Chrome window
    /// lights up, rather than merely coarse.
    static func tooltip(isPlaying: Bool, isRecording: Bool) -> String {
        switch (isPlaying, isRecording) {
        case (true, true): return "This app is playing audio and using the microphone"
        case (true, false): return "This app is playing audio"
        case (false, true): return "This app is using the microphone"
        case (false, false): return ""
        }
    }

    /// The same facts for VoiceOver, as phrases to append to a card's label.
    static func accessibilityPhrases(isPlaying: Bool, isRecording: Bool) -> [String] {
        var parts: [String] = []
        if isRecording { parts.append("app using microphone") }
        if isPlaying { parts.append("app playing audio") }
        return parts
    }
}
