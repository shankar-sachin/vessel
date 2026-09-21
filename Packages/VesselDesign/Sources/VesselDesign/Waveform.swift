import SwiftUI

/// A live audio waveform.
///
/// Its only job is to prove the microphone is hearing you. A static "Listening…"
/// label can't distinguish "working" from "muted, and you're about to lose what
/// you said" — bars that move with your voice can.
public struct Waveform: View {

    /// Current input level, 0...1.
    private let level: Double
    private let tint: Color
    private let barCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(level: Double, tint: Color = Palette.diet, barCount: Int = 5) {
        self.level = level
        self.tint = tint
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 4, height: height(for: index))
            }
        }
        .frame(height: 34)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    /// Bars are taller toward the middle, which reads as a voice rather than a
    /// level meter, and each is offset slightly so they don't move in lockstep.
    private func height(for index: Int) -> CGFloat {
        let centre = Double(barCount - 1) / 2
        let distance = abs(Double(index) - centre) / max(1, centre)
        let shape = 1.0 - distance * 0.55

        // A floor so the bars are visible in silence — an empty row looks broken.
        let amplitude = 0.18 + level * 0.82
        return 6 + 28 * amplitude * shape
    }
}

#Preview("Waveform") {
    VStack(spacing: 20) {
        Waveform(level: 0.1)
        Waveform(level: 0.5)
        Waveform(level: 0.9)
    }
    .padding(40)
    .background(Palette.ground)
}
