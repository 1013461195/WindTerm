# 安全模型

## 设计目标

- 不继承 WindTerm 旧依赖和潜在漏洞。
- 默认安全，危险操作需要明确确认。
- 敏感数据最小化保存、最短时间驻留内存。
- 日志、崩溃报告、诊断信息默认脱敏。

## 资产

需要保护：

- SSH 密码。
- 私钥文件与 passphrase。
- agent socket 使用权限。
- known_hosts 信任记录。
- session profile。
- SFTP 访问路径和传输记录。
- session logs。

## 威胁

| 威胁 | 防护 |
| --- | --- |
| 中间人攻击 | known_hosts 校验、host key changed 默认阻止。 |
| 凭据泄露 | 平台 keychain、主密码、内存清零、日志脱敏。 |
| 配置文件泄露 | profile 不存明文密码，敏感值只存引用。 |
| 依赖漏洞 | 锁定版本、漏洞扫描、SBOM。 |
| 恶意终端输出 | OSC/clipboard/title/hyperlink 等敏感控制序列可配置限制。 |
| 粘贴误执行 | paste dialog、大量粘贴确认、bracketed paste。 |
| 远端伪造 prompt | host key 与认证 UI 不在终端内展示，避免被远端输出混淆。 |

## 凭据存储

优先级：

1. macOS Keychain、Windows Credential Manager、Linux Secret Service。
2. 主密码加密 vault。
3. 不保存，只会话内临时使用。

新项目不建议使用裸 AES-CBC。推荐：

- KDF：Argon2id。
- AEAD：XChaCha20-Poly1305 或 AES-256-GCM。
- 每条 secret 独立 nonce。
- vault metadata 不包含明文敏感字段。

## known_hosts 策略

默认：

- unknown：展示 host、port、algorithm、SHA256 fingerprint，用户确认后写入。
- changed：强警告，默认拒绝，覆盖需要二次确认。
- other algorithm：默认拒绝，允许高级用户查看详情。

支持：

- OpenSSH known_hosts 导入。
- hashed hostnames。
- 每个 profile pin host key。

## 私钥处理

- 优先引用用户原始私钥路径，不复制。
- 如导入到 app vault，必须加密。
- passphrase 不落盘，除非用户明确选择保存到 keychain。
- 解密后的 key 材料用完清零。

## 日志

日志分两类：

- session log：用户主动开启，记录终端原始输出或文本输出。
- app diagnostic log：记录状态与错误，不记录密码、私钥、完整命令输入。

默认脱敏：

- password/passphrase/token。
- private key 内容。
- known sensitive env。
- proxy auth。

## 终端控制序列安全

默认策略：

- OSC 52 clipboard：默认询问或禁用。
- clickable hyperlink：允许展示，但打开前确认域名。
- window title：允许，但长度限制。
- bell：可配置。
- remote-triggered file write/download：禁止。

## 发布安全

- 每个平台签名。
- 自动更新包签名校验。
- 依赖 license 与漏洞清单。
- CI 做 `cargo audit`、`cargo deny`、Flutter dependency check。
- release build 禁用 debug 日志。

