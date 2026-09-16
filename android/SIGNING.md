# Android 签名密钥配置

发布正式 APK 需要固定签名密钥。**这一点不能随意更换**：
Android 只允许签名一致的包覆盖安装，一旦更换密钥库，
所有已安装旧版本的用户都必须先卸载才能升级。

## 1. 生成密钥库

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias picpro
```

按提示设置密钥库口令与密钥口令，并牢记。

> 建议有效期设置得足够长（如上例 10000 天），
> 密钥过期后同样会导致无法继续发布更新。

## 2. 配置本地构建（可选）

本地需要构建 release 包时，复制示例文件并填入实际值：

```bash
cp android/key.properties.example android/key.properties
```

`android/key.properties` 已被 `.gitignore` 排除，**不要提交到仓库**。

## 3. 配置 CI

在仓库的 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 密钥库文件的 Base64 编码 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名（上例为 `picpro`） |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

生成 Base64 编码：

```bash
# Linux / macOS
base64 -w 0 upload-keystore.jks > keystore.b64

# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Content keystore.b64
```

把 `keystore.b64` 的内容整体粘贴为 `ANDROID_KEYSTORE_BASE64` 的值。

## 4. 未配置密钥库时的行为

未配置上述 Secrets 时，构建**不会失败**，但：

- APK 使用 debug 密钥签名；
- 产物只作为工作流附件（Artifacts）保留，**不会上传到 Release**。

这样既能让人验证构建可用，又避免测试签名的包被误当成正式包分发。
正式发版前请务必完成上面的 Secrets 配置。

## 5. 校验产物签名

```bash
# 查看证书指纹
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

若需要像 EasyPassword 那样在 CI 中硬校验指纹（防止静默回退到 debug 签名），
可在 `.github/workflows/release.yml` 的 Android 任务中追加一步比对
`sha-256 digest`，与密钥库中的指纹一一对应。
