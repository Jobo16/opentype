import SwiftUI

/// Transparent floating overlay shown during recording/processing.
struct FloatingBarView: View {
    let phase: String
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 12) {
            // Audio level meter.
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.8))
                .frame(width: 4, height: CGFloat(16 + audioLevel * 16))

            Text(phase)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.75), in: Capsule())
    }
}
