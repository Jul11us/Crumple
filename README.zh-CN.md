<div align="center">

<br>

<img src="design/app-icon.png" alt="Crumple 应用图标" width="88" height="88">

# Crumple

### 给日常，多一点留白。

一个有纸张触感的桌面清理工具。<br>
把不再需要的，揉成纸团，轻轻放下。

<sub>macOS 与 Windows · 简体中文与 English · 雾灰、牛皮纸与深色</sub>

<br>

**[下载 macOS 版](https://github.com/Jul11us/Crumple/releases/tag/v1.1.1-macos)** &nbsp; / &nbsp; **[Windows 预览版](https://github.com/Jul11us/Crumple/releases/tag/v1.1.1-windows)**

[整理的手感](#一个小动作腾出一点空间) &nbsp; · &nbsp; [功能](#让每一份空间都有去处) &nbsp; · &nbsp; [构建](#纸张背后) &nbsp; · &nbsp; [English](README.md)

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/crumple-zh-dark.png">
  <img src="docs/images/crumple-zh-light.png" alt="Crumple macOS 版：纸色界面、衬线标题，以及一只金属纸篓" width="100%">
</picture>

<sub>真实 macOS 界面，使用生成的演示文件。</sub>

</div>

<br>

## 一个小动作，腾出一点空间

Crumple 把一个熟悉的小动作，带回日常整理。拖起文件，它会在手中皱成纸团；轻轻一甩，纸团沿着弧线落向纸篓。投中，文件移入废纸篓；投偏，它就回到列表。整理结束，一张小票缓缓打印出来，记下每一次取舍。

纸张、墨色、一行衬线标题。雾灰的清爽、牛皮纸的温度与深色的安静，构成三种外观。动效跟着操作发生，从第一道折痕，到小票的最后一行。

## 选择你的版本

| | macOS | Windows 预览版 |
| :--- | :--- | :--- |
| **系统** | macOS 14 或更新版本 | Windows 10 / 11，x64 |
| **下载** | [通用版 DMG](https://github.com/Jul11us/Crumple/releases/download/v1.1.1-macos/Crumple-1.1.1-macOS-universal.dmg) | [安装版 exe](https://github.com/Jul11us/Crumple/releases/download/v1.1.1-windows/Crumple-1.1.1-Windows-x64-Setup.exe) · [免安装 exe](https://github.com/Jul11us/Crumple/releases/download/v1.1.1-windows/Crumple-1.1.1-Windows-x64.exe) |
| **安装** | 打开 DMG，将 Crumple 拖入「应用程序」 | 运行安装向导，或直接打开免安装程序 |
| **实现** | SwiftUI 与 AppKit · Apple 芯片和 Intel 通用 | C# 与 Avalonia · 自带 .NET 运行环境 |

macOS 包使用本机临时签名，尚未经 Apple 公证。Windows 包尚未代码签名，作为预览版发布：已在 macOS 上完成核心测试、界面渲染与演示交互验证；Windows 系统集成仍待 Windows 实机验证。两个 Release 均附 SHA-256 校验文件。

## 让每一份空间，都有去处

| 工具 | 可以做什么 |
| :--- | :--- |
| **智能清理** | 检查缓存、日志、开发工具下载缓存、安装包与旧下载，扫描位置随系统适配。 |
| **空间分析** | 从文件夹逐层查看占用，找到空间花在了哪里。 |
| **大文件** | 在个人文件夹中寻找体积较大的文件。 |
| **重复文件** | 先检查大小与抽样内容，再比对完整 SHA-256；为每组文件建议保留一份。 |
| **应用卸载** | macOS 查看应用与关联文件；Windows 打开应用登记的卸载程序。 |
| **状态与优化** | 查看系统读数，按需使用对应平台的维护工具。 |
| **记录与撤销** | 保留清理小票；文件仍在废纸篓且原位置空闲时，可以恢复已记录的项目。 |

macOS 菜单栏面板让系统状态随手可见。Windows 版延续相同的纸张语言，把纸团、纸篓与清理小票带到桌面。

<details>
<summary><strong>看看 Windows 版</strong></summary>
<br>
<img src="docs/images/crumple-windows-light.png" alt="从 Avalonia 应用实际渲染的 Windows 版界面，使用演示文件" width="100%">
<br>
<sub>在 macOS 上运行 Avalonia 渲染，用于逐页核对界面；此图不是 Windows 桌面实拍。</sub>
</details>

## 把分寸放进默认设置

- 扫描只读取文件，选定项目后才开始清理。
- 默认**移到废纸篓**。文件仍占用磁盘，清空废纸篓后才会释放空间。
- 安装包与旧下载默认不勾选，Windows 的开发缓存也默认不勾选。
- 正在运行的应用，其缓存受到清理保护。
- 清理前重新检查路径边界与忽略列表。
- 演示模式使用生成的假文件和独立废纸篓。

macOS 另提供需要明确选择的碎纸机模式，用于永久删除。Windows 预览版使用系统回收站，不提供永久删除。平台差异与验证范围见 [macOS 开发指南](docs/DEVELOPMENT.zh-CN.md)和 [Windows 说明](Windows/README.md)。

## 纸张背后

### macOS

需要 macOS 14+ 和 Apple Command Line Tools，无第三方软件包依赖。

```bash
git clone https://github.com/Jul11us/Crumple.git
cd Crumple
bash scripts/build.sh
open build/Crumple.app
```

```bash
swift test
bash Localization/verify.sh
bash scripts/make-dmg.sh
```

先通过独立进程体验演示文件：

```bash
CRUMPLE_DEMO_HOME=/private/tmp/crumple-demo \
  "build/Crumple.app/Contents/MacOS/Crumple"
```

### Windows

构建需要 .NET 10 SDK；使用打包后的程序无需另装运行环境。生成安装向导另需 NSIS。

```powershell
powershell -File scripts/build-windows.ps1
```

也可以在 macOS 或 Linux 上交叉构建：

```bash
bash scripts/build-windows.sh
```

演示渲染、测试脚本和打包细节见 [Windows 说明](Windows/README.md)，本地验证记录见 [VALIDATION.md](docs/VALIDATION.md)。

## 设计手记

界面审查参考 [Damir Sokolovsky 的 unslop](https://github.com/heydamir/unslop)，遵循 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 署名。适配与来源记录见[界面设计方向](docs/UI-DIRECTION.md)。Windows 版使用 [Lucide](https://lucide.dev) 图标与 [Noto Serif SC](https://github.com/notofonts/noto-cjk) 字体，组件许可随安装包提供。

<br>

<div align="center">
<sub>Crumple · 给日常，多一点留白。</sub>
</div>
