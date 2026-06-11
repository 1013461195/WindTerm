# 更新签名

更新清单使用 Ed25519 签名。私钥不得提交到仓库，应用仅内置公钥。

生成密钥：

```sh
openssl genpkey -algorithm ED25519 -out update-private.pem
openssl pkey -in update-private.pem -pubout -outform DER |
  tail -c 32 | base64
```

清单格式：

```json
{
  "version": "1.1.0",
  "notes": "Release notes",
  "packages": {
    "macos": {
      "url": "https://example.com/wind-send-1.1.0.dmg",
      "sha256": "...",
      "fileName": "wind-send-1.1.0.dmg"
    }
  }
}
```

签名并构建：

```sh
tool/sign_update.sh manifest.json update-private.pem envelope.json
flutter build macos --release \
  --dart-define=APP_VERSION=1.1.0 \
  --dart-define=UPDATE_MANIFEST_URL=https://example.com/envelope.json \
  --dart-define=UPDATE_PUBLIC_KEY=<base64-public-key>
```

客户端先验证清单 Ed25519 签名，再下载对应平台安装包并验证 SHA-256。
