# Android 签名密钥配置

发布正式 APK 需要固定签名密钥。**这一点不能随意更换**：
Android 只允许签名一致的包覆盖安装，一旦更换密钥库，
所有已安装旧版本的用户都必须先卸载才能升级。

## 当前状态

本仓库的签名密钥已生成并配置完成：

| 项目 | 值 |
|---|---|
| 别名 | `picpro` |
| 密钥库格式 | JKS |
| 有效期 | 10000 天 |
| SHA-256 指纹 | `68:CE:CC:CE:B9:F6:C5:1E:31:BE:81:9B:DE:B7:CA:A7:0D:EB:05:43:7E:B9:CF:BD:AD:A2:A1:F6:78:6F:41:7F` |

密钥库与口令存放在**仓库之外**：`C:\Users\21573\.keystores\picpro\`
（`upload-keystore.jks` 与 `credentials.txt`）。这四项已写入 GitHub Secrets，
CI 构建 APK 时会自动使用，并在构建后**硬校验证书指纹**——
指纹不匹配会立即中止发布，避免悄悄回退到 debug 签名。

> **请立即备份该目录。** 密钥库丢失后无法用新密钥覆盖安装旧版本，
> 只能让用户卸载重装。建议备份到至少两处离线位置。
>
> 若更换密钥库，必须同步更新：GitHub Secrets 四项凭据，
> 以及 `.github/workflows/release.yml` 中的 `EXPECTED_SHA256`。

## 从零重新配置（仅在新机器或更换密钥时）

### 1. 生成密钥库

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias picpro
```

按提示设置密钥库口令与密钥口令，并牢记。

> 建议有效期设置得足够长（如上例 10000 天），
> 密钥过期后同样会导致无法继续发布更新。

### 2. 配置本地构建（可选）

本地需要构建 release 包时，复制示例文件并填入实际值：

```bash
cp android/key.properties.example android/key.properties
```

`android/key.properties` 已被 `.gitignore` 排除，**不要提交到仓库**。

### 3. 配置 CI

在仓库的 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 密钥库文件的 Base64 编码 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | 密钥别名（当前为 `picpro`） |
| `ANDROID_KEY_PASSWORD` | 密钥口令 |

生成 Base64 编码：

```bash
# Linux / macOS
base64 -w 0 upload-keystore.jks > keystore.b64

# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Content keystore.b64
```

把 `keystore.b64` 的内容整体粘贴为 `ANDROID_KEYSTORE_BASE64` 的值。

### 4. 未配置密钥库时的行为

未配置上述 Secrets 时，构建**不会失败**，但：

- APK 使用 debug 密钥签名；
- 产物只作为工作流附件（Artifacts）保留，**不会上传到 Release**。

这样既能让人验证构建可用，又避免测试签名的包被误当成正式包分发。

## 校验产物签名

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

对照上表确认 `SHA-256 digest` 一致，即说明产物使用正确的密钥签名。

