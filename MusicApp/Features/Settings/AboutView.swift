import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("版本", value: version)
            }

            Section {
                Text("本应用只使用公开、合法的音乐接口，不抓取任何商业音乐平台的版权音频。")
            } header: {
                Text("说明")
            }

            Section {
                source(
                    "iTunes Search API",
                    "提供歌曲信息、封面和 30 秒试听片段。试听只能在线播放，不能下载。完整歌曲请在 Apple Music 收听。",
                    "https://performance-partners.apple.com/search-api"
                )
                source(
                    "Openverse",
                    "由 WordPress 基金会维护的开放授权内容搜索引擎。曲目采用 Creative Commons 协议，使用时请遵守对应协议并注明作者。",
                    "https://openverse.org"
                )
                source(
                    "Internet Archive",
                    "非营利数字图书馆，收录公有领域和 CC 授权的录音、网络厂牌专辑和现场录音。",
                    "https://archive.org/details/audio"
                )
                source(
                    "Jamendo",
                    "CC 授权的独立音乐平台。需要你在设置中填写自己的 client_id。",
                    "https://www.jamendo.com"
                )
                source(
                    "LRCLIB",
                    "开放、免费的歌词数据库，提供同步歌词。",
                    "https://lrclib.net"
                )
            } header: {
                Text("音乐与歌词来源")
            }

            Section {
                Text("Creative Commons 协议通常要求署名（BY），部分协议禁止商业使用（NC）或禁止修改（ND）。每首歌的「详细信息与授权」页面可以查看协议并复制署名。")
                    .font(.callout)
            } header: {
                Text("关于 CC 协议")
            }

            Section {
                Link("源代码（Apache-2.0）", destination: URL(string: "https://github.com/diegozzzzds/blank-app")!)
            }
        }
        .navigationTitle("关于与版权")
    }

    private func source(_ name: String, _ description: String, _ link: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let url = URL(string: link) {
                Link(link, destination: url)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
