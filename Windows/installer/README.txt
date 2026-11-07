Crumple for Windows 1.2.0
=========================

简体中文
--------
适用于 Windows 10 / Windows 11 64 位电脑。
安装版：双击 Crumple-1.2.0-Windows-x64-Setup.exe，按向导完成安装。
免安装版：双击 Crumple-1.2.0-Windows-x64.exe，可直接运行。
程序已包含 .NET 运行环境，无需安装开发工具。

智能清理：检查用户临时文件、浏览器缓存、崩溃报告、开发缓存、AI 工具残留、安装包和旧下载。
AI 工具的运行时、模型和对话记录默认不勾选；关联工具运行时会保护其文件。
大文件与重复文件：扫描桌面、文档、下载、图片、音乐、视频及设置中添加的文件夹。
空间分析：选择文件夹后双击条目逐层查看。
应用卸载和优化：打开对应的 Windows 系统维护工具完成操作。

扫描只读取文件。文件清理后移入 Windows 回收站，不提供永久删除操作。
回收站中的文件仍占用磁盘空间，清空回收站后才会释放空间。
清理记录支持恢复仍在回收站中、原路径未被占用的文件。
无法访问的文件、链接、系统文件与云端占位文件会被跳过。
额外扫描文件夹需要在设置中手动添加；忽略列表优先。

设置与记录保存在 %LOCALAPPDATA%\Crumple。卸载程序会保留这些记录。
在设置中可以切换中文、English、雾灰、牛皮纸、深色或跟随系统。
F5 重新扫描；Esc 停止；Ctrl+, 打开设置。

English
-------
Requires 64-bit Windows 10 or Windows 11.
Run the Setup exe to install, or use the standalone exe without installation.
The .NET runtime is included. Developer tools are not required.

Smart clean reviews temporary files, browser caches, crash reports, developer caches,
AI tool leftovers, installers and old downloads. Installers, old downloads and developer caches start unselected.
AI runtimes, models and conversations start unselected; running tools protect their files.
Large Files and Duplicates scan personal folders and any folders explicitly added in Settings.
Space Lens explores logical file sizes. Double-click a folder to explore inside it.
Uninstaller and Optimize open the corresponding Windows maintenance tools.

Scans are read-only. Cleanup moves files to the Windows Recycle Bin.
Recycled files continue to use disk space until the Recycle Bin is emptied.
History can restore tracked files while they remain recycled and their original paths are free.
Links, system files, cloud placeholders and inaccessible items are skipped.
Settings and history are stored in %LOCALAPPDATA%\Crumple and are kept on uninstall.

F5: rescan. Esc: stop. Ctrl+,: settings.
Pass --demo to launch generated demonstration files in an isolated temporary folder.

Build and verification details: Windows/README.md in the source project.
