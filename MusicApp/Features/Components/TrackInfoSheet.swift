import SwiftUI
import UIKit

/// Source, license and attribution details for a track (CC BY requires attribution).
struct TrackInfoSheet: View {
    let track: PlayableTrack
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(track: track, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.headline)
                            Text(track.artist).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("信息") {
                    LabeledContent("歌手", value: track.artist)
                    if let album = track.album {
                        LabeledContent("专辑", value: album)
                    }
                    if let duration = TimeFormatting.clock(track.duration) {
                        LabeledContent("时长", value: duration)
                    }
                    if let genre = track.genre {
                        LabeledContent("流派", value: genre)
                    }
                    if let date = track.releaseDate {
                        LabeledContent("发行", value: String(date.prefix(10)))
                    }
                    LabeledContent("来源", value: track.source.displayName)
                }

                if track.isPreview {
                    Section {
                        Text("这是 iTunes 提供的 30 秒试听片段，只能在线播放，不能下载。完整歌曲请在 Apple Music 收听。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let license = track.license {
                    Section {
                        LabeledContent("协议", value: license.displayName)
                        if let url = license.url {
                            Link("查看协议全文", destination: url)
                        }
                        if license.isNonCommercial {
                            Text("该协议不允许商业用途。")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("授权")
                    }
                    if license.requiresAttribution {
                        Section {
                            Text(track.attributionText)
                                .font(.callout)
                                .textSelection(.enabled)
                            Button(copied ? "已复制" : "复制署名") {
                                UIPasteboard.general.string = track.attributionText
                                copied = true
                            }
                        } header: {
                            Text("署名")
                        } footer: {
                            Text("转载或二次使用时，请按协议要求注明作者和来源。")
                        }
                    }
                }

                if let page = track.webPageURL {
                    Section {
                        Link(track.source == .itunes ? "在 Apple Music 中打开" : "打开来源网页", destination: page)
                    }
                }
            }
            .navigationTitle("详细信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
