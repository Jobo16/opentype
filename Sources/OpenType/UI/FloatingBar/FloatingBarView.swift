import SwiftUI

/// Transparent floating overlay shown during recording/processing.
struct FloatingBarView: View {
    let phase: String
    let audioLevel: Float
    var transcript: String = ""

    @State private var rippleScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 10) {
            // Audio ripple indicator
            ZStack {
                Circle()
                    .fill(.red.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .scaleEffect(1.0 + CGFloat(audioLevel) * 0.5)
                    .animation(.easeOut(duration: 0.08), value: audioLevel)

                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(0.8 + CGFloat(audioLevel) * 0.4)
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }

            // Phase label + transcript
            VStack(alignment: .leading, spacing: 2) {
                Text(phase)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 160, maxWidth: 400)
        .background(.black.opacity(0.8), in: Capsule())
    }
}
