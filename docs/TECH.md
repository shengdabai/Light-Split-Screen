# 技术方案与证据边界

## 结构
菜单栏/原生面板 → WindowEngine → macOS Accessibility API → 用户选定窗口。
全局快捷键用 Carbon RegisterEventHotKey，不采集键盘输入；更改快捷键时临时注销应用自己的快捷键。
拖边仅监听全局鼠标按下/拖动/松开，在窗口位置发生变化且尺寸基本不变时预览。忽略普通文字拖动。每次拖动最多约 22 次/秒读取窗口位置，无空闲高频轮询。
布局采用 AX 全局左上坐标；以 NSScreen.screens.first 的顶部转换 AppKit 坐标，按窗口与屏幕最大交集选屏；使用 visibleFrame 留出 Dock/菜单栏。
工作布局每次枚举普通应用的标准、可调整窗口，用户显式选 2–4 个；显示器断开时在执行前重新核对 ID。

## 信任边界
辅助功能权限由用户在系统设置授予。应用不申请屏幕录制、输入监控、文件夹权限；不联网，无服务端，无账户。
AX 句柄与 PID、launchDate 一起校验，避免应用退出后误控重用 PID。窗口标题仅用于本机选择界面，不落盘；不读取正文/输入框内容。
窗口操作先检查整个计划，再保存尺寸。失败时尝试恢复并保留撤销记录；外部应用可能拒绝恢复，不能声称原子事务。
最多 30 次撤销、80 个原始窗口记录，内存保存，退出清空。UserDefaults 只保存快捷键、间距、排除列表和拖边开关。

## REA 的实际使用
固定使用官方 npm rea-agents 6.7.0，从 registry.npmjs.org 隔离安装，未运行 setup，未修改全局 MCP/Skill。
阅读该仓库原生窗口桥接的公开代码，参考其 AX 类型校验、进程身份校验与权限边界；成品独立实现，不包含 REA 运行时。
通过实际 `inspect-macho` 命令分析本次生成的 Mach-O，保存 JSON 证据；最终代码还会重新分析。
Magnet 未安装，未逆向、购买或下载其二进制。功能匹配来自 Magnet 官方公开介绍：https://magnet.crowdcafe.com/ 。REA 不会让系统无法调整的窗口变得可调整。
REA 官方仓库：https://github.com/morluto/rea ，MIT；本次未把 REA 源码编译进产品。

## Spike
问题：能否无需 Electron/Node/大型逆向引擎交付轻量原生窗口工具？
阈值：Swift 编译可运行；成品 <10 MiB；多屏负坐标、上方副屏和 Dock 留白测试通过；REA 可在无 Hopper 情况检查 Mach-O。
机器证据：evidence/build.log，evidence/tests.log，evidence/rea-final-macho.json。
真实权限与跨应用操作另列；没有权限时保持 WAITING，不能用几何测试替代。

## 构建与恢复
Apple Silicon，macOS 13+ 编译目标；仅当前 macOS 27.0.1 / arm64 实机可验。零第三方依赖。
源码分 Layout / WindowEngine / Shortcuts / DragSnap / main；scripts/build.sh 编译 + ad-hoc 签名（无付费开发者证书、公证或对外发布）。
改前 checkpoint 记录在 evidence；不自动 Git 初始化、push、修改系统分屏/登录启动设置。
