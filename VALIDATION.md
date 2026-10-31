# 本机验证

## 2026-10-31 · 浅色默认与 unslop 界面调整

- `bash build.sh`：arm64、x86_64 发布构建通过，共提取 470 个中英文本地化键；应用严格签名检查通过。
- `swift test`：现有 4 组、22 项测试通过；日志在 `build/ui-tests.log`。
- `bash Localization/verify.sh`：中英文各 31 项打包资源检查通过；日志在 `build/ui-localization.log`。
- 在真实原生窗口核对概览、智能清理首页、实时状态页；验证独立演示应用的概览扫描按钮、扫描进度、结果页与文件详情入口。
- 独立的 UIReview bundle 首次打开设置时显示「浅色」，再切换为「深色」，确认列表、选择框与操作栏的对比度和显示正常；该测试设置与正式应用分开保存。
- 使用真实 SwiftUI 视图渲染中英文概览、智能清理、大文件、重复文件、应用卸载的浅色 1180×780 和深色 1100×720 预览，检查长文案换行与侧栏显示。文件在 `build/ui-preview/zh` 和 `build/ui-preview/en`。
- 扫描验证仅针对 `CRUMPLE_DEMO_HOME=/tmp/crumple-ui-live-review` 的演示文件；没有对实际用户文件执行清理。
- 新版已构建为 `build/Crumple.app` 并更新至 `/Applications/Crumple.app`；DMG 已重新打包为 `build/Crumple 1.0.dmg`（4,836,286 字节）。镜像校验、只读挂载、包内应用严格签名检查、与新版应用的完整内容比对均通过；Applications 链接、安装窗口布局、背景和卷图标已核对。日志在 `build/ui-dmg-verification.log`，SHA-256 在 `build/Crumple 1.0.dmg.sha256`。

构建日志在 `build/ui-build.log`；设计方向和来源署名在 `design/UI-DIRECTION.md`。

## 2026-10-30 · 前次功能与打包验证

验证日期：2026-10-30。设备：Apple M5，macOS 27.0.1。

- `swift test`：4 组、22 项测试通过，覆盖删除边界、符号链接、撤销、防覆盖、重复文件比对和投掷判定。
- `bash Localization/verify.sh`：中英文各 31 项打包资源检查通过，包含单复数、多个插值参数、百分号和权限说明。构建共提取 478 个本地化键。
- 在原生窗口检查了概览、状态、智能清理、大文件、重复文件、空间分析、优化、应用卸载、历史、设置、关于和权限引导。验证了浅色 / 深色 / 跟随系统，以及切换 English 后重新打开、恢复系统中文。
- 修复英文状态卡片和关于窗口的文字截断；设置窗口可滚动。概览工具卡片悬停保持背景不变，增加主题色描边、轻微阴影和箭头位移，采用 0.18 秒过渡；开启“减少动态效果”时取消位移。新增反馈后已复测工具卡片与侧边栏的实际点击，并恢复原有浅色设置。
- 修复背景光晕越界拦截侧边栏点击：装饰背景不参与点击检测，页面的点击范围限制在内容区。通过真实鼠标坐标验证「概览、状态、空间分析」各自的图标、文字和空白区域，共 9 处，均能切换页面。
- 演示清理将 19 项移入独立演示废纸篓，受保护的演示缓存保持原状；撤销后，99 个演示文件的 SHA-256 全部与清理前一致，演示废纸篓为空。
- 对本机执行 `--scan-report` 只读扫描；未对真实扫描结果执行清理。
- DMG 校验和与只读挂载通过；包内应用的严格签名校验通过，内容与构建版一致，Applications 链接、背景和图标位置均已核对。

交付为 `build/Crumple.app`、`build/Crumple 1.0.dmg`，并安装到 `/Applications/Crumple.app`。构建包含 arm64 和 x86_64；实际运行检查在上述 Apple 芯片设备完成。应用使用本地临时签名，Apple 公证仍需开发者账号。

原始构建和测试输出在 `build/build.log`、`build/tests.log`、`build/localization-verification.log`、`build/real-scan-report.log` 和 `build/dmg-verification.log`。
