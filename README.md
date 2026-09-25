# 悦听 — iOS 听歌 App

一个用 SwiftUI 写的原生 iOS 音乐播放器。它聚合多个**合法公开**的音乐接口做详细搜索，支持后台播放、锁屏控制、歌单收藏、同步歌词和离线下载。

## 功能

- **聚合搜索**：同时搜索多个来源，按来源分组显示；可以按「全部 / 歌曲 / 歌手 / 专辑」缩小范围，按来源筛选，加载更多，保留搜索历史
- **播放器**：播放 / 暂停、上一首 / 下一首、进度拖动、随机播放、列表循环 / 单曲循环、可编辑的播放队列、迷你播放条、全屏播放页、隔空播放
- **后台与锁屏**：切到后台继续播放；锁屏和控制中心显示歌曲信息和封面，可以控制播放；来电打断后自动恢复，拔耳机自动暂停
- **曲库**：收藏、歌单（新建、重命名、拖动排序、删除）、最近添加、按歌名 / 歌手 / 播放次数排序
- **歌词**：从 [LRCLIB](https://lrclib.net) 获取同步歌词，随播放滚动，点击某一行跳到对应位置；支持导入本地 `.lrc` 文件（兼容 GBK 编码）
- **下载与导入**：CC 授权的完整曲目可以下载离线听；可以从「文件」App 导入 mp3 / m4a 等文件，自动读取标签和封面

## 音乐来源与版权

| 来源 | 内容 | 能否完整播放 | 能否下载 | 需要 key |
|---|---|---|---|---|
| iTunes Search API | 主流歌曲（周杰伦、Taylor Swift…）| 只有 30 秒试听 | 否 | 否 |
| Openverse | CC 授权音乐 | 是 | 是 | 否 |
| Internet Archive | 公有领域 / CC 专辑、老唱片、现场录音 | 是 | 是 | 否 |
| Jamendo | CC 授权独立音乐 | 是 | 视曲目而定 | 需要免费 client_id |
| 本地导入 | 你自己的音乐文件 | 是 | — | — |

本应用**不抓取**网易云音乐、QQ 音乐、酷狗等商业平台的版权音频。CC 协议一般要求署名，部分协议禁止商业使用。每首歌的「详细信息与授权」页面可以查看协议并复制署名。

## 运行

### 需要

- 一台 Mac，装有 **Xcode 16 或更新版本**
- iPhone 模拟器，或者 iOS 17 以上的 iPhone

### 在模拟器上运行

1. `git clone` 本仓库
2. 双击打开 `MusicApp.xcodeproj`（注意打开的是这个工程文件，不是文件夹）
3. 顶部选择一个 iPhone 模拟器，按 ▶（⌘R）

模拟器上运行不需要签名。

### 在自己的 iPhone 上运行（免费 Apple ID 即可）

1. Xcode → Settings → Accounts，登录你的 Apple ID
2. 在左侧选中 `MusicApp` 工程，再选 `MusicApp` target，打开 **Signing & Capabilities**
   - Team 选择 “(Personal Team)”
   - 把 **Bundle Identifier** 改成唯一的名字，比如 `com.你的名字.MusicApp`
3. 用数据线连接 iPhone，在手机上点「信任此电脑」
4. 在 iPhone 上打开开发者模式：设置 → 隐私与安全性 → 开发者模式，然后重启
5. 在 Xcode 顶部选择你的 iPhone，按 ▶
6. 第一次运行时，在 iPhone 上进入 设置 → 通用 → VPN 与设备管理，信任你的开发者证书

用免费账号安装的 App 7 天后会过期，重新从 Xcode 运行一次即可。

### 运行测试

在 Xcode 中按 ⌘U。测试覆盖了搜索接口的解析、歌词解析、播放队列逻辑等。

没有 Mac 时，也可以在 Linux 上测试纯逻辑部分（需要 Swift 5.9+ 工具链）：

```sh
./scripts/linux-check.sh
```

## 使用小贴士

- **Jamendo**：到 [devportal.jamendo.com](https://devportal.jamendo.com) 免费注册一个应用，把 client_id 填到 App 的「设置」里，搜索结果里就会多出 Jamendo
- **iTunes 地区**：中国大陆区没有搜索结果，默认用香港区，可以在设置里改
- **中文搜索**：Openverse 和 Internet Archive 以英文内容为主，中文关键词结果很少，可以试试英文
- **Openverse 频率限制**：匿名每分钟 20 次、每天 200 次，所以远程搜索在按下搜索键后才发请求
- **导入音乐**：在「曲库 → 本地音乐」点 + 从「文件」App 导入。和音乐文件同名的 `.lrc` 会自动当作歌词。也可以用「文件」App 或电脑上的访达把文件拷到本 App 的文件夹里，再点「扫描 App 文件夹」
- **锁屏控制和后台播放**：请在真机上测试，模拟器上的表现不完整

## 常见问题

- **打不开工程 / 提示版本太旧**：工程需要 Xcode 16 以上。也可以用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成：`brew install xcodegen && xcodegen generate`
- **真机运行提示签名错误**：检查 Team 是否已选择，Bundle Identifier 是否已改成唯一的名字
- **某首歌放不了**：部分来源的文件可能已失效，App 会自动跳到下一首

## 项目结构

```
MusicApp/
  App/          入口、依赖注入、根视图
  Core/         纯 Foundation 逻辑（可以在 Linux 上测试）
    Sources/    iTunes / Openverse / Internet Archive / Jamendo 接口
    Search/     聚合搜索、搜索历史、去重
    Lyrics/     LRC 解析、LRCLIB 客户端、文本编码识别
    Playback/   播放队列（随机、循环）
  Persistence/  SwiftData 模型（歌曲、歌单）
  Services/     播放器、锁屏控制、歌词、下载、本地导入
  Features/     SwiftUI 界面（搜索、曲库、正在播放、设置）
MusicAppTests/  单元测试和接口样例数据
scripts/        Linux 测试脚本、CI 辅助脚本
```

## 许可证与致谢

代码以 [Apache-2.0](LICENSE) 协议发布。音乐和歌词的版权归各自的作者所有。感谢 Apple iTunes Search API、[Openverse](https://openverse.org)、[Internet Archive](https://archive.org)、[Jamendo](https://www.jamendo.com) 和 [LRCLIB](https://lrclib.net)。
