# Crumple · 开发与功能说明

一个原生 SwiftUI 的 Mac 空间清理工具：每清理一个文件，它就会从列表里弹出一张纸，被揉成纸团，再扔进右下角的废纸篓。

## 页面

| 页面 | 内容 |
| --- | --- |
| 概览 | 磁盘用量圆环、可清理的垃圾、各工具入口、最近的清理记录 |
| 状态 | 实时刷新（1.5 秒）：健康度、CPU、GPU、内存（压力和交换）、电池（健康度、循环次数、充电功率）、可用空间和读写速度、网络速度、散热状态，以及按应用汇总的进程列表（可退出 / 强制退出） |
| 智能清理 | 首页 → 扫描（进度环，7 类逐个打勾）→ 结果（总数 + 分类卡片 + 占比图）→ 查看详情 → 揉纸团 → 完成（篮筐徽章 + 打印出来的清理小票） |
| 空间分析 | 个人文件夹或应用程序里每个文件夹占了多少，点进去一层层找，可以移到废纸篓 |
| 大文件 | 在桌面、文稿、下载、影片、音乐、图片里找出超过下限的文件，按类型筛选、按大小或最久没用排序 |
| 优化 | 退出占内存最多的应用；开关后台启动项（关掉的会挪到 Disabled by Crumple，可恢复）；维护任务：重置快速查看缓存、重建“打开方式”、重启程序坞和访达、刷新 DNS、释放内存、重建聚焦索引（后三项需要管理员密码） |
| 应用卸载 | 列出第三方应用和它们在资源库里的残留文件，一起扔进废纸篓 |
| 清理记录 | 累计扔掉多少、清理次数、最近 14 天柱状图、按天分组的记录 |
| 设置（⌘,） | 清理方式、浅色 / 深色 / 跟随系统、中英文、开场动画、权限、菜单栏和提醒、扫描下限、忽略列表、清空记录 |

## 功能

- **外观与语言**：默认使用浅色外观，也可以在设置里切换为深色或跟随系统，主窗口、设置、关于、权限引导和菜单栏面板会一起切换。界面支持简体中文与 English，默认跟随系统语言；手动切换后点「立即重新打开」生效。
- **开场动画**：打开应用时，Crumple 的字母一个个跳出来，接着突出 m：一个纸团沿着 m 的笔画把它“写”一遍，再被投进右边的篮筐。点任意位置可以跳过，设置里可以关掉。
- **扫描 7 类垃圾**：应用缓存、日志文件、Xcode 垃圾（DerivedData / 设备支持 / 模拟器缓存）、开发工具缓存（npm、Gradle、Cargo、pip…）、AI 工具残留（Claude、Codex、Cursor 等的缓存默认勾选；虚拟机镜像、运行时和模型只列出来；对话记录、检查点和历史一律不碰；正在运行的工具按进程名保护）、下载文件夹里的安装包、很久没碰过的旧下载。
- **一键清理**：勾选后点「开始清理」（⌘↩），每个文件依次被揉成纸团投进纸篓。
- **亲手投**：按住列表里任意一行拖起来，纸在手里被揉皱，甩出去按抛物线飞。
  - 投进篓口才会清理；打到篓沿会弹开，没投中会掉出窗口，文件都会回到列表。
  - 拿在手里靠近纸篓时，篓口发绿光；如果这个文件投不进去，就发红光。
- **投不进去的文件**：所属应用正在运行的缓存、没有删除权限的文件、删除失败的文件，都会被纸篓弹出来，上方会冒出原因（例如「Safari浏览器 正在运行，投不进去」），文件不会被删除。
- **安全默认**：默认「移到废纸篓」（可恢复）；只会删除家目录里至少两层深的东西；下载文件夹的内容和 Xcode 归档默认不勾选。

## 构建

只需要 Command Line Tools（不需要完整 Xcode）：

```bash
bash scripts/build.sh
```

生成 `build/Crumple.app`（通用版，Apple 芯片和 Intel 都能运行）。装进「应用程序」文件夹，这样访达、启动台和聚焦里都能找到它：

```bash
bash scripts/install.sh
```

## 打包成 DMG

```bash
bash scripts/make-dmg.sh
```

生成 `build/releases/Crumple <版本>.dmg`：打开后是带背景图的安装窗口，把应用拖到 Applications 即可安装。第一次运行时 macOS 可能会询问是否允许控制「访达」（用来排版窗口），不允许也能打包，只是没有背景图。

这个 DMG 只做了本机临时签名，没有经过 Apple 公证。自己用没问题；发给别人时，对方第一次打开需要右键点应用 →「打开」，或在「系统设置 › 隐私与安全性」里点「仍要打开」。要让别人直接双击就能打开，需要 Apple 开发者账号（Developer ID）签名并公证。

## 演示模式

想先放心试玩动画，可以让它在一个装满假文件的沙盒里运行：

```bash
CRUMPLE_DEMO_HOME=/tmp/crumple-demo "build/Crumple.app/Contents/MacOS/Crumple"
```

## 开发用的小工具

运行自动化测试，并检查打包后的中英文资源（含单复数、数字插值和权限说明）：

```bash
swift test
bash Localization/verify.sh
```

`scripts/build.sh` 会让 Swift 编译器提取界面文案，再通过 `Localization/en.py` 生成中英文资源；遇到缺失翻译或插值参数不匹配会停止构建。资源检查需要先构建应用。

```bash
# 只读扫描报告（不删除任何东西，跳过“下载”文件夹）
"build/Crumple.app/Contents/MacOS/Crumple" --scan-report

# 把纸团动画的静帧渲染成 PNG
"build/Crumple.app/Contents/MacOS/Crumple" --render-previews /tmp/previews

# 浅色与深色的真实 SwiftUI 界面预览（1180×780 / 1100×720，只使用演示文件）
CRUMPLE_DEMO_HOME=/tmp/crumple-ui "build/Crumple.app/Contents/MacOS/Crumple" --render-interface build/ui-preview

# 开场动画的分帧图
"build/Crumple.app/Contents/MacOS/Crumple" --render-splash design

# 所有 logo 方案和对比图（图标定稿是 H：篮球框 · 米白墨黑）
"build/Crumple.app/Contents/MacOS/Crumple" --render-logos design/logo-explorations
```

## 代码结构

- `Engine/` — 扫描（`Scanner`：垃圾、大文件、应用）、删除（`Cleaner`）、清理记录存储、演示数据
- `Model/` — 应用状态、页面流程、清理流程、手动投掷逻辑、设置
- `Paper/` — 纸团的运动轨迹（`PaperMotion`）和绘制（`PaperArt`：揉皱的纸、废纸篓、应用图标；`HeroArt`：各页插画和彩纸）
- `Views/` — 设计组件（`Components`）、侧边栏和各个页面
- `Localization/` — 英文翻译、编译器提取结果的资源生成器、打包资源验证

## 界面设计

界面采用纸张和墨色的风格，提供雾灰、牛皮纸、深色三种主题；标题用衬线体，数字用等宽字体，列表像小票一样用点线连接。设计审查与调整参考 Damir Sokolovsky 的 [unslop](https://github.com/heydamir/unslop)（[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)）；方向与逐项记录见 [UI-DIRECTION.md](UI-DIRECTION.md)。
