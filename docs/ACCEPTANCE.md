# 验收记录 · 2026-10-19

当前结论：原生应用与源码已交付到本机；机器检查、真实 AX 核心测试、Claude 复审均通过。最终包的独立应用权限与交互验收另记，不能用测试宿主已有权限替代。

## 固定产物
- 应用：`~/Applications/轻分屏.app`，0.1.0，arm64；344,936 字节（约 337 KiB），磁盘块占用约 344 KiB。
- 二进制 SHA-256：`c331630d9bbf707303289a6d22efc4d53620abf7e49d2514a885a7aa3b4f55fa`。
- `codesign --verify --strict` 通过；本机 ad-hoc 签名，无 Apple 开发者证书或公证。
- REA 6.7.0 `inspect-macho` 实际运行，最终 evidence 的 subject digest 与应用二进制一致。
- 构建/源文件哈希：`evidence/final-manifest.json`。所有依赖为 macOS 系统框架，无第三方动态库或运行时。

## 已通过
| 项目 | 结果与证据 |
|---|---|
| 编译、签名、plist | PASS，evidence/final-build.log |
| 几何与拖动判断 | PASS 152 条，evidence/tests.log |
| 快捷键映射、去重、保存、普通输入保护 | PASS 449 条，evidence/tests.log |
| 真实 AX 核心测试 | PASS 54 条，evidence/integration-final.log；两台显示器 1920×1080 和 2560×1440；四个专用 Fixture 标准窗口 + 一个 NSPanel |
| 真实布局范围 | 每屏全部 15 种布局、显式跨屏、原位恢复、撤销、双窗/开发三窗/三列/四窗、最小尺寸失败回滚、排除应用和浮动面板拒绝 |
| 浅蓝原生界面 | PASS，CUA 目视设置与布局面板；标题/按钮/长文本/滚动起点/键盘焦点环；evidence/design-adoption.md |
| 配色对比度 | PASS，正文/浅蓝13.78:1，说明/浅蓝5.81:1，白字/主按钮6.09:1 |
| Claude 交叉审核 | 首轮 REVISE → 主 Agent 核实修复 → 最终 APPROVED，无剩余 P0/P1；实际模型 claude-opus-5-5。evidence/claude-review.md 与 claude-final-review.md |
| 空实现检查 | Sources/Tests/scripts 无 TODO、FIXME、test.skip、.only 或 fatalError 占位；构建脚本 bash -n 通过 |

## 独立应用交互
首次应用授权后，CUA 实际观察到「辅助功能已授权」。此后修复与浅蓝版重新编译改变签名，最终包再次显示未授权。已请用户重新开启；当前 WAITING，尚未把最终包称为已完成跨应用 UI 端到端验收。
真实 AX 核心测试是在已授权的测试宿主中运行，只操作专用 Fixture。它证明该实现能调整真实窗口，但不能替代最终独立应用权限验收，也不能证明所有应用兼容。
Esc 取消快捷键录制和返回设置已用 UI 验证。全局按键是否经过系统热键分发不能仅由 CUA 定向按键行为确认。

## 剩余范围
- devflow 门 1 仍为 WAITING：未取得 Tony 的 3 条真实日常使用记录；无他人试用或付费验证，无登录/支付。
- 原生拖动事件完整链、物理键盘全局热键、VoiceOver 完整人工检查、旧版 macOS、Intel 和所有软件兼容性未全覆盖。
- Claude 记录的 P2：共享屏幕边缘最多 1 点的松手偏差或快速拖动未吸附；卡死应用可能阻塞主线程数秒；AXWindows 元素类型为系统契约；理论显示器 ID 缺失；快捷键面板从未变为 key 时可能需再次点更改。
- 本机系统 `EnableTilingByEdgeDrag=0`、`EnableTopTilingByEdgeDrag=0`（只读观察），没有修改设置。若以后开启系统平铺，两者拖边可能冲突，可关闭本工具拖边。
- 最小尺寸、全屏、固定窗口、浮动面板和应用限制会失败或被跳过；失败后尝试恢复，有界重试不能保证第三方应用配合。
- 不声称零缺陷、不声称复制/逆向了 Magnet。Magnet 未安装；对应功能以官方公开介绍为证。

## 恢复和资源
全部源码改前 checkpoint ID 保存在 evidence/*checkpoint.json。初始可运行应用的恢复副本保存在本次 tools/recovery 下，二进制哈希已与改前核对。
暂停：菜单栏 → 暂停管理窗口。停止：菜单栏 → 退出轻分屏。撤销：⌃⌥⌘Z；原位：⌃⌥Z。退出后内存历史清空。
临时 REA/Swift 编译缓存仅本次生成；最终分析后清理。源码、测试、审查、必要证据与恢复副本保留。
