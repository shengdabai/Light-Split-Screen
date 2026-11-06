# 轻分屏 v0.3.0 build6 交付现场

2026-10-19，用户反馈重启后窗口跳动，要求自行选登录项、一键开启/关闭自动分屏，最后明确选择Control+S。devflow B1+B2/L2执行。登录项页面已打开，用户确认选择完成，未代改其他软件。

正式应用 ~/Applications/轻分屏.app，v0.3.0 build6。SHA 5621875f8eda1f580cbbb5000acf5c5a7327b41c21970916d26ecd211c34f1d6，数据832885字节。严格签名通过，根inode保持，9源码匹配control-s-review-manifest。最终冻结，无后续重编译。

每次启动默认关闭，覆盖旧continuousAuto开启偏好；登录仅启动菜单栏。关闭取消自动窗口通知、pending和timer，停用DragSnap并保留当前位置；重复开启不重启协调器。默认全局⌃S松开切换一次，独立于可选手动键。只有autoToggle精确CtrlS允许单修饰键；其他单Control/裸键/CmdS拒绝，捕获和加载统一规则。CtrlS会被接管，用户已告知，系统/非独占/事件拦截冲突不保证检测。

验证：152几何、512快捷键、4550自动单元；生产AppDelegate+隔离偏好44项真实窗口断言；34项持续窗口测试的四个依赖源码摘要与当前完全相同。三次Claude官方只读复审APPROVED（claude-opus-5-5），最后以claude-control-s-review为准。

用户行动时明确授权后，仅原生重建本app设备控制权限，无TCC数据库写入。独立日志trusted=true、screens=2、shortcutsFailed=0。实际面板开启4窗无重叠、面板关闭后5秒精确不变、关闭6次只读采样稳定。曾保存on后退出，重开实际UIoff、prefs0，权限仍有效。真实CtrlS开启在干净区间off->on通过。

真实 CtrlS 关闭已补充通过：最后在已置前的「Control S 按键检查」窗口内由用户输入；工具不夹杂点击控制，轻分屏原生 switch1->0，四个专用窗口在开启基线及两次关闭采样中位置完全一致。见 build6-physical-key-off.json。早期未确认记录是历史状态，不能覆盖这次结果。

当前状态：测试 fixture、按键观察器全部关闭，正式 app 无参数日常运行，continuousAuto=0。后续按 CtrlS 将整理当前桌面窗口，再按一次关闭。不要重编译或重建已生效权限。
交付证据在evidence/control-20261019。build6-manifest为构建时点，notInstalledYet=true是历史；build6-install、permission、delivery-receipt反映实际结果。应用源码包的校验与精确iCloud状态见archive-final-check.json和icloud-final-target.json，外层回执不自包含于ZIP。早期build4/5和A组合是用户改选前的历史。

恢复：旧v0.2.1与已授权build4 app副本保留在~/Codex/2026-10-19/qingfenping-control。初始checkpoint 20261019T112751Z-a19fde4551e6已恢复验证；后续键盘规则checkpoint 20261019T114919Z-ca2f5c3f910b、20261019T115938Z-65321e641031；交付包/文档前20261019T122240Z-7f79fc43f5fb，最终关闭验收回写前20261019T122857Z-6acfdfd8997b已恢复核验。非Git，未初始化Git。

清理：只清本轮可重建编译缓存、中间候选、测试重复二进制与打包目录；保留必要源码、原始图标、证据、恢复点和一套最终测试程序。具体见cleanup-final.json及前序cache-cleanup回执。

限制：未重启/注销整机，Spaces、StageManager、物理插拔、全部第三方软件、长期连续运行未完整覆盖。旧390矩阵不是真实登录体验证明。
