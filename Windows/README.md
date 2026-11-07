# Crumple for Windows

Windows 版本，使用 C#、.NET 10 和 [Avalonia](https://avaloniaui.net)。界面逐页照着 macOS 版本移植：同样的三套配色、衬线标题、纸团揉皱和抛进纸篓的物理效果都是同一套数字。Avalonia 自己绘制整个界面，所以同一份程序在 Mac 上也能以演示模式运行、截图，方便和 Mac 版本逐页对照。

- `Crumple.Core`：扫描、路径边界、回收站与恢复（平台无关，有测试）。
- `Crumple.Desktop`：界面、纸团动画、Windows 系统调用。

## 已打包文件

输出目录为 `build/releases/windows/`：

- `Crumple-1.2.0-Windows-x64-Setup.exe`：安装向导，为当前用户安装到 `%LOCALAPPDATA%\Programs\Crumple`，创建开始菜单快捷方式及系统卸载入口。
- `Crumple-1.2.0-Windows-x64.exe`：免安装单文件程序。
- `README.txt`：中英文使用说明。
- `THIRD-PARTY-NOTICES.txt`：随包组件许可，程序内设置页也可查看。
- `SHA256SUMS.txt`：实际交付 exe 的 SHA-256 校验值。

两种 exe 均自带运行环境，无需用户安装 .NET、Python、Visual Studio 或 Swift。目标为 64 位 Windows 10/11；当前产物未做代码签名。

## Windows 功能

| 工具 | 行为 |
| --- | --- |
| 智能清理 | 用户临时文件、Chrome/Edge/Brave/Firefox 的明确缓存目录、崩溃报告、npm/pip/NuGet/Yarn/Gradle/Cargo 缓存、AI 工具残留（Claude/Cursor/Windsurf 的网页缓存、Claude Code 与 Codex 的缓存默认勾选；运行时、模型和对话记录只列出）、下载目录中的安装包与旧文件。临时文件默认至少 7 天未修改。 |
| 空间分析 | 按文件夹逐层统计逻辑大小，双击进入下一层。 |
| 大文件 | 扫描 Windows 的实际个人文件夹位置，支持设置中明确加入的额外文件夹。 |
| 重复文件 | 按大小、首中尾抽样、完整 SHA-256 逐步比对；跳过硬链接，每组保留一份，清理前再次核对内容。 |
| 应用卸载 | 读取系统登记的桌面应用，确认后直接打开该应用自带的卸载程序（和“设置 › 应用”一样）；回到 Crumple 时自动刷新列表。 |
| 状态与优化 | CPU、内存、运行时间、进程工作集与托盘读数；打开启动应用、存储感知、磁盘清理、驱动器优化、任务管理器和 Windows 更新。 |
| 记录与恢复 | 每个成功移入回收站的文件都会更新记录；通过 Windows Shell 恢复，原位置有文件时拒绝覆盖。 |
| 界面 | 与 Mac 版本一致：简体中文、English，雾灰、牛皮纸、深色或跟随系统；拖起任意一行甩进右下角的纸篓，点纸篓清空回收站，完成后打印清理小票；声音同样是程序合成的。 |

Windows 应用卸载与优化使用 Windows 自身的流程。SwiftUI、Xcode 清理、macOS 菜单栏以及 macOS 专属维护命令不属于 Windows 版本。

## 文件边界

扫描只读取文件；清理只移动明确列出的单个文件，不递归删除目录。默认移入 Windows 回收站，不提供永久删除路径。安装包、旧下载与开发缓存默认不勾选。

路径边界和忽略列表在扫描与清理时都会检查。系统目录、已安装程序目录、Crumple 自身、符号链接、目录联接和云端占位文件不会作为清理项。浏览器等关联应用运行时，其缓存不能清理。扫描之后变化的文件需要重新扫描。

回收站中的文件继续占用磁盘空间。小票记录移入回收站的文件大小，不将它写成已经释放的磁盘容量。回收站清理仅支持本地固定磁盘。扫描大小是逻辑大小，未尝试推断 NTFS 压缩、去重或云端文件的实际分配大小。

## 构建

需要 .NET 10 SDK。安装包另外需要 NSIS 3.13；原生 Windows 编译器可直接使用 NSIS 官方发行版。没有 NSIS 时仍会生成免安装 exe。

Windows PowerShell：

```powershell
powershell -File scripts/build-windows.ps1
```

macOS 或 Linux：

```bash
bash scripts/build-windows.sh
```

脚本会先运行核心测试，再以 `win-x64`、`SelfContained`、`PublishSingleFile` 和 `IncludeNativeLibrariesForSelfExtract` 发布。SDK 无需安装到系统位置，可用 `CRUMPLE_DOTNET` 指定。可选 `win-arm64` 参数生成 ARM64 免安装程序。

在 macOS 上构建 NSIS 编译器，可按 [NSIS 官方 POSIX 构建说明](https://nsis.sourceforge.io/Docs/AppendixG.html)，将同一版本源码编译出的 `makensis` 与官方 zip 中的 Stubs、Include 和 Plugins 搭配使用。使用 `CRUMPLE_MAKENSIS` 与 `NSISDIR` 指向对应位置。

## 验证

```bash
dotnet run --project Windows/Crumple.Core.Tests -c Release
python3 scripts/verify-windows-package.py build/releases/windows
```

23 项核心测试覆盖路径边界、忽略项、系统目录、链接替换、变更文件保护、正在运行的应用、回收与恢复、覆盖冲突、记录写入失败、取消、下载与 AI 文件默认选择、完整哈希、保留副本、物理文件标识、空间统计与原子 JSON 存储。它们可以在 macOS 或 Windows 上执行，不使用真实用户文件。

Windows 实机测试：

```powershell
powershell -File scripts/test-windows.ps1
```

它在屏幕外以演示模式运行真正的 exe：智能扫描、大文件、重复文件、一次清理、用（模拟的）鼠标把一个文件拖进纸篓，并导出每一页三种主题的截图到 exe 旁的 `Crumple-previews`。只操作新建的 `Crumple-Demo-*` 临时文件夹。

在 Mac 上可以用同一个渲染模式出截图，与 `build/previews/mac-reference` 里 Mac 版本的截图逐页对照：

```bash
dotnet run --project Windows/Crumple.Desktop -- --render build/previews/windows --demo-home /private/tmp/Crumple-Demo --states
```

演示文件夹上面不能有链接（Mac 的 `/tmp`、`/var` 都是链接，所以用 `/private/tmp`），因为路径安全规则从不跟随链接。

本次交付在 macOS 上完成核心测试、上述渲染与拖拽测试、Windows 交叉编译与安装包检查。没有 Windows 实机或虚拟机，因此回收站、卸载程序、开机启动项和声音等 Windows 系统调用还没有在实机上跑过。

单独体验演示模式：

```powershell
.\Crumple-1.2.0-Windows-x64.exe --demo
```

演示目录由程序创建并保留供检查，不接触真实用户目录或真实回收站。
