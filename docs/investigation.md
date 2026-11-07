# Investigation report

**Question:** LaunchOS 2.3.0 是如何实现全屏启动器的，我如何用自己的技术栈做一个自己的版本？

**Purpose:** 学习其交互与架构，独立实现一个可日常使用的 macOS 启动器，不复制其代码与素材

**Done when:** 产出一个可编译、可安装、可运行的 LaunchDeck.app，覆盖网格、搜索、分页、键盘/鼠标、排序与快捷键

## What we looked at

- LaunchOS (mach-o-fat)
- LaunchOS.app (directory)
- /Applications/LaunchOS.app
- /Applications/LaunchOS.app/Contents/MacOS/LaunchOS

## What we found

### LaunchOS 2.3.0 是一个纯原生 Swift 的 macOS 26+ 启动器（AppKit + SwiftUI + Core Data + Sparkle + KeyboardShortcuts），以 LSUIElement 代理方式常驻，用全局快捷键/热角呼出全屏图标网格。

- **Confidence:** Seen it (observed)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))

### 从本地化字符串可以还原其能力面：多页网格、文件夹、隐藏应用、Dock 显示/隐藏、热角与 F4/自定义快捷键、导入/导出布局、导入系统 Launchpad 数据库、图标大小与玻璃材质等外观设置。

- **Confidence:** Worked it out (derived)
- **Evidence:**
  - `ev_d68fd0ef4fbead5eca34aefe9dd8e6e12bfab4a631a0ae013bf383edf454d222` — "Hot Corner": 2 matching strings, 0 matching function names, 0 matching imports; 2 functions involved. (address=0x10016393c, address=0x100199010)
  - `ev_ef7b35648fe8e3586f7583b591cdd995d8fbad775ff0668bb68935dcf3710bd0` — "Import System Launchpad Data": 1 matching strings, 0 matching function names, 0 matching imports; 1 functions involved. (address=0x10019b8b8)

### 自建版本 LaunchDeck（app/LaunchDeck）以 SwiftPM + AppKit/SwiftUI 复刻了核心体验：全屏毛玻璃网格、搜索、分页、键盘/鼠标操作、拖拽排序、隐藏应用、排序与使用频率、状态栏与 ⌥Space/⌃⌥Space 快捷键；已验证可编译、可安装并运行。

- **Confidence:** Best guess (inferred)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))
  - `ev_d68fd0ef4fbead5eca34aefe9dd8e6e12bfab4a631a0ae013bf383edf454d222` — "Hot Corner": 2 matching strings, 0 matching function names, 0 matching imports; 2 functions involved. (address=0x10016393c, address=0x100199010)
  - `ev_ef7b35648fe8e3586f7583b591cdd995d8fbad775ff0668bb68935dcf3710bd0` — "Import System Launchpad Data": 1 matching strings, 0 matching function names, 0 matching imports; 1 functions involved. (address=0x10019b8b8)

### LaunchDeck v2 按用户反馈补齐三项：默认布局改为 6×4、图标 124pt、可调间距并把行高撑满全屏；右键菜单新增“卸载…”（移到废纸篓 + 系统应用保护）；实现 Launchpad 式文件夹（拖到图标中央建夹、2×2 预览、玻璃卡片展开、重命名/解散/移出、拖入追加），均已实机验证。

- **Confidence:** Best guess (inferred)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))
  - `ev_d68fd0ef4fbead5eca34aefe9dd8e6e12bfab4a631a0ae013bf383edf454d222` — "Hot Corner": 2 matching strings, 0 matching function names, 0 matching imports; 2 functions involved. (address=0x10016393c, address=0x100199010)

### LaunchDeck v1.3 把布局改成自适应：设置横/竖格数与间距比例，图标尺寸由行高推导并居中铺满；新增触控板左右滑动、滚轮上下翻页、空白处按住拖动翻页、热角呼出、快捷键录制、登录项、布局导入导出、打开时隐藏 Dock/菜单栏，均已构建并安装验证（热角与自定义快捷键经注入事件确认）。

- **Confidence:** Best guess (inferred)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))

### LaunchDeck v1.4 增加背景右键菜单（空白处右键弹出“重新启动/设置…”，重启经 /usr/bin/open -n 重新拉起，已验证 pid 更替）与图标大小百分比设置（55%-110%，默认 85%，在自适应推导值上再缩放），已构建安装。

- **Confidence:** Best guess (inferred)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))

### LaunchDeck v1.5 加入动效：面板整体 0.9→1 弹性缩放淡入、关闭缩小淡出、图标按序错峰浮现、翻页按方向滑入滑出并跟随拖拽偏移、点击图标时 1.5 倍放大淡出后再启动、文件夹弹性展开。已构建安装，启动/关闭与翻页状态经截图验证。

- **Confidence:** Best guess (inferred)
- **Evidence:**
  - `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (address=0x100001de0 (entry point))
  - `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (address=0x100001de0 (entry point))

## Open questions

_None outstanding._

## How this was done

- **Mode:** Deep (the original's code and files could be read)
- **Engines:** builtin
- **Limitations:**
  - 414 indirect jumps could not be resolved; code they reach may be missing
  - functions reached only through computed pointers or at run time may be missing; absence is not proof
  - the kind is detected from the first bytes and, to break ties, the file name
  - toolchain and packer hints come from markers that can be faked or borrowed

## Handoff

已完成：v1.5 动效已安装运行。实现：AppModel.panelVisible 驱动根视图 scale 0.9→1 + opacity 弹性；hide 后延迟 0.22s 再 orderOut；AppearOnPage 修饰符按 index*0.012 错峰；翻页用 pageDirection + .move(edge:) 过渡并把 DragGesture 位移映射到 0.35 倍跟手偏移；launchingID 让图标 1.5x 放大淡出 0.18s 后再 open，随后发关闭通知；文件夹仍用 opacity+scale 过渡。验证：启动后 1.2s 截图内容完整、翻页到第 2 页、回车启动 Calculator 后自动收起、toggle 收起在 0.6s 后 offscreen。注意：动画帧无法用静态截图判定，需肉眼看；用户设置仍为 7x5/20%/85%，不要覆盖。

## Evidence ledger

- `ev_135f5d7b3054ae2b8913d80aa0395eb2d99f466208b455e4c68ca5b1884d47d5` **core_target_triage** — LaunchOS.app is a folder (an app bundle, an unpacked app or a project). (Best guess)
- `ev_548a688e9f1f15b286f38c322fd9cf741c4b3fdc76230d1c751228e1830ca9da` **core_target_triage** — LaunchOS is a program for Mac, built for arm64 (64-bit). It looks like it was made with Swift. (Seen it)
- `ev_0a3fbfcfaaebc8eae6ca1db28a5cf6bd73caebe98e326699c040d154581f37c0` **core_overview_show** — Mach-O (macOS, iOS) executable for arm64 with 13766 functions, 11009 strings, 2398 imports from 43 libraries. (Worked it out)
- `ev_d68fd0ef4fbead5eca34aefe9dd8e6e12bfab4a631a0ae013bf383edf454d222` **core_feature_find** — "Hot Corner": 2 matching strings, 0 matching function names, 0 matching imports; 2 functions involved. (Worked it out)
- `ev_ef7b35648fe8e3586f7583b591cdd995d8fbad775ff0668bb68935dcf3710bd0` **core_feature_find** — "Import System Launchpad Data": 1 matching strings, 0 matching function names, 0 matching imports; 1 functions involved. (Worked it out)

