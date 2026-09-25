import SwiftUI

struct PlaybackControlsView: View {
    @Environment(PlayerManager.self) private var player

    var body: some View {
        HStack {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.isShuffled ? Color.accentColor : Color.secondary)
            }
            .accessibilityLabel(player.isShuffled ? "关闭随机播放" : "随机播放")

            Spacer()

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .accessibilityLabel("上一首")

            Spacer()

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Spacer()

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(!player.queue.hasNext)
            .accessibilityLabel("下一首")

            Spacer()

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
            }
            .accessibilityLabel(player.repeatMode.title)
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
    }
}
