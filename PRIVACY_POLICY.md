# Privacy Policy / 隐私政策

**Last updated: 2026-07-29**

## English

Open Island is a local macOS companion for AI coding agents.

### Local-only boundary

The App does not collect, transmit, or sell personal data. It has no account,
analytics, telemetry, crash-reporting service, updater, relay, remote runtime,
or third-party tracking SDK. It does not create IP network connections.

The App can receive local hook events, read supported local agent files in
place, and focus an existing local terminal through a restricted Automation
policy. Those external applications remain independent: their own network
traffic, credentials, transcripts, and cloud behavior are not collected or
controlled by Open Island.

### Local storage and controls

Open Island stores feature preferences and minimized session metadata locally.
Session metadata excludes transcript text, prompts, command bodies, terminal
paths, and credentials; it is retained for at most 30 days in app-owned
protected files. The App does not keep an app-owned transcript store.

- **Clear History** deletes session metadata and eligible local caches/logs. It
  preserves preferences, source-agent transcripts, hook backups, installed
  integrations, and Keychain credentials.
- **Reset Integrations** removes only exactly verified managed integrations,
  their credentials, journals/provenance/backup state as applicable, and the
  verified shared helper. It first displays one aggregate consent record and
  aborts without mutation if any member is unsafe or ambiguous. It does not
  delete history or unrelated source-tool configuration.

Hook backups may contain source-tool configuration. They are private local
files, retained for at most 30 days or until a verified uninstall/restore, and
are not part of Clear History. The full field, path, retention, and deletion
matrix is [docs/data-lifecycle.md](docs/data-lifecycle.md).

### Contact

For questions, open an issue at:
https://github.com/Octane0411/open-vibe-island/issues

---

## 中文

Open Island 是一款面向 AI 编程代理的本地 macOS 辅助应用。

### 仅本地边界

本应用不会收集、传输或出售个人数据。它没有账户、分析、遥测、崩溃报告服务、更新器、中继、
远程运行时或第三方追踪 SDK，也不会创建 IP 网络连接。

本应用可以接收本地 hook 事件、就地读取受支持的本地代理文件，并通过受限的自动化策略聚焦已有
本地终端。这些外部应用仍然独立：它们自身的网络流量、凭据、转录内容和云端行为不会被 Open
Island 收集或控制。

### 本地存储和用户控制

Open Island 仅在本地存储功能偏好和最小化会话元数据。会话元数据不包含转录文本、提示词、命令
内容、终端路径或凭据；它保存在受保护的应用目录中，最长保留 30 天。本应用不保存自有的转录
内容库。

- **清除历史记录** 会删除会话元数据和符合条件的本地缓存/日志；不会删除偏好、源代理转录、
  hook 备份、已安装集成或钥匙串凭据。
- **重置集成** 只移除经过精确验证的受管理集成及其相应凭据、日志/溯源/备份状态和经过验证的
  共享 helper。它会先显示一次汇总同意记录；任一成员不安全或不明确时，整个操作不会修改任何
  内容。它不会删除历史记录或无关的源工具配置。

hook 备份可能包含源工具配置。它们是私有本地文件，最长保留 30 天或在经过验证的卸载/恢复后
删除，且不属于“清除历史记录”的范围。完整字段、路径、保留和删除矩阵见
[docs/data-lifecycle.md](docs/data-lifecycle.md)。

### 联系方式

如有问题，请在以下地址提交 issue：
https://github.com/Octane0411/open-vibe-island/issues
