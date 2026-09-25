import SwiftUI

struct ProgressSliderView: View {
    @Environment(PlayerManager.self) private var player
    @State private var scrubValue: Double = 0
    @State private var isEditing = false

    var body: some View {
        let duration = player.duration.isFinite && player.duration > 0 ? player.duration : 1
        let value = isEditing ? scrubValue : min(max(player.currentTime, 0), duration)
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { value }, set: { scrubValue = $0 }),
                in: 0...duration
            ) { editing in
                if editing {
                    scrubValue = player.currentTime
                }
                isEditing = editing
                player.isScrubbing = editing
                if !editing {
                    let target = scrubValue
                    Task { await player.seek(to: target) }
                }
            }
            .disabled(!player.hasTrack)
            HStack {
                Text(TimeFormatting.clock(value))
                Spacer()
                if player.isBuffering {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Text("-" + TimeFormatting.clock(max(duration - value, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
