# PicPro 🖼️

批量图片处理工具：**Windows（EXE）+ Android（APK）+ Web（可 1Panel 部署）**。
一套 Rust 处理内核同时编译为原生库与 WASM，三端行为完全一致。

![License](https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-orange)

## ✨ 功能

### 按目标体积压缩
在「分辨率 × 编码质量」二维空间搜索，而非固定质量硬压。
优先保住分辨率——文字与证件类图片的可读性主要由像素量决定，
因此宁可用略低的质量换取更高分辨率。支持单张体积上限与长边上限两种约束。

### 更换背景色
纯算法离线实现：边缘采样估计背景色 → 从画面边界做连通域抠图 → 软边羽化 → 白底去污染。

其中**连通域抠图**是关键：白衬衫与白背景颜色几乎相同，仅靠颜色阈值会把衬衫挖空；
而衬衫被深色西装包围、不与画面边界连通，因此不会被误判为背景。

**白底去污染**用于消除发丝白边：利用 `I = a·F + (1-a)·Bg` 反解出前景真实颜色
`F = (I - (1-a)·Bg)/a`，从根本上消除半透明边缘在新底色上的发白轮廓。

### 证件照裁剪
内置 30 项规格预设，源自北京市《摄影行业服务规范（试行）》常规照片尺寸规格表，
并补充各类考试报名与签证的高频规格：

| 分类 | 示例 |
|---|---|
| 基础寸照 | 一寸 25×35mm / 295×413px、二寸 35×49mm / 413×579px、大一寸、小二寸、大二寸、三寸、五寸 |
| 证件类 | 身份证 26×32mm @350dpi、社保卡、驾驶证、护照 / 港澳通行证、居住证 |
| 考试报名 | 考研网上确认（3:4）、学信网图像采集、高考、公务员、教师资格证、计算机等级、四六级、成人自考 |
| 签证 | 美国 51×51mm、日本 45×45mm、申根 / 韩国 / 泰国 35×45mm |
| 其他 | 简历照、半身职业照、高清证件照 |

两点必须说明的事实：

- **同一名称的规格在不同机构可能不一致。** 照相馆所说的「二寸」常指 35×53mm（严格叫大二寸），
  而多数报名系统要的是 35×49mm。界面会给出毫米、像素、DPI 三项信息与用途备注，便于核对。
- **顺序不可颠倒：先裁到规定像素，再压体积。** 体积要求是在规定像素下考核的，
  若先压体积再裁剪，裁完体积会再次变化。

### 格式转换
支持 `png` · `jpg` · `jpeg` · `gif` · `svg` 作为输入，输出 `png / jpg / gif / webp / bmp / tiff`。

- **SVG 仅作输入**：位图无法反向转换为矢量图。SVG 会被栅格化（可选目标宽度），默认输出 PNG。
- **GIF 保留动画**：压缩与转格式时逐帧处理并保留帧延时；转静态格式时只取首帧并给出提示。
- **GIF 不支持换背景**：动画逐帧换底易产生闪烁，因此该组合不提供。

## 📦 构建

### 自动构建（推荐）

| 触发方式 | 产出 |
|---|---|
| 推送 `v*` 标签 | Windows 安装包、Android APK、Web 产物（均发布到 Release）＋ 镜像打版本标签与 `latest` |
| 推送到 `main` | 构建 Web 产物并推送 `edge` 镜像 |
| 手动触发 | 同标签方式，但版本号为占位值，产物仅作工作流附件 |

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 自动产出：

- `PicPro-Setup-<版本>.exe`（Windows 安装包）
- `PicPro-<版本>.apk`（Android，arm64，**正式签名**并校验证书指纹）
- `PicPro-Web.zip`（Web 静态产物，可直接用于 1Panel）
- `crazyfigure/picpro:<版本>`、`1.0`、`latest`（多架构镜像）

> Android 需要仓库 Secrets 中的签名凭据才会产出正式签名包。
> 未配置时构建不会失败，但产物只作工作流附件保留、不上传到 Release，
> 以免测试签名的包被误用于分发（debug 签名的包无法被正式包覆盖安装）。
> 当前仓库已完成该配置，细节见 [`android/SIGNING.md`](android/SIGNING.md)。

镜像推送需要 `DOCKERHUB_USERNAME` 与 `DOCKERHUB_TOKEN` 两个 Secrets；
未配置时会跳过镜像环节，不影响其它产物发布。

### 本地构建

```bash
flutter pub get
flutter analyze

cargo test --manifest-path rust/Cargo.toml    # 内核单元测试（88 项）

flutter build windows --release               # Windows，构建时自动编译 Rust 内核
flutter build apk --release --target-platform android-arm64
flutter_rust_bridge_codegen build-web --release && flutter build web --release
```

> Windows 本地构建建议开启系统「开发人员模式」
> （设置 → 隐私和安全性 → 开发者选项），否则 Flutter 插件符号链接创建可能失败。

### 内核命令行工具

内核自带命令行示例，可直接用于验证行为或脚本化处理：

```bash
cd rust

# 查看图片信息
cargo run --release --example cli -- input.jpg --info

# 换蓝底并压到 200KB 以内
cargo run --release --example cli -- in.jpg out.jpg --bg 67,142,219 --max-kb 200

# 按一寸规格裁剪 + 换白底 + 压到 100KB
cargo run --release --example cli -- in.jpg out.jpg --preset size_1cun --bg 255,255,255 --max-kb 100
```

## 🚀 部署

Web 版的全部处理都在浏览器内完成，服务器只托管静态文件，用户的图片不会离开设备。
详见 [`deploy/1panel.md`](deploy/1panel.md)，提供静态网站与 Docker 容器两种路线。

### 直接用镜像仓库的镜像

推版本标签会**自动构建并推送**镜像到 Docker Hub，无需自己编译：

```bash
# 最新正式版
docker pull crazyfigure/picpro:latest

# 固定版本（推荐用于生产）
docker pull crazyfigure/picpro:1.0.0

# main 分支的最新构建
docker pull crazyfigure/picpro:edge
```

镜像同时提供 `linux/amd64` 与 `linux/arm64`，两者内容一致。

运行：

```bash
docker run -d --name picpro -p 8080:80 --restart unless-stopped crazyfigure/picpro:latest
```

### 从源码构建

```bash
docker compose -f deploy/docker-compose.yml up -d --build
```

首次构建需下载 Flutter 镜像并编译 Rust/Flutter，耗时较长（10~25 分钟）；
直接拉取上面的官方镜像可以跳过这一步。

> 部署时必须保留 `deploy/nginx.conf` 中的 `Cross-Origin-Opener-Policy` 与
> `Cross-Origin-Embedder-Policy` 响应头——Rust 内核是多线程 WASM，
> 依赖 `SharedArrayBuffer`，缺少这两个头页面会直接无法加载。

## 🛠 技术栈

Rust（图像处理内核）· Flutter 3.x / Dart · flutter_rust_bridge 2.x · image · resvg · fast_image_resize · Provider

内核为纯计算层，不含平台相关 IO 与 UI 逻辑，因此可同时产出
原生动态库（Windows / Android 经 FFI 调用）与 WASM（浏览器内运行）。

- `image`：png/jpeg/gif/webp/bmp/tiff 编解码
- `resvg`：SVG 栅格化（纯 Rust，含 WASM 支持，三端一致）
- `fast_image_resize`：SIMD 加速的 Lanczos3 重采样
- `jpeg-encoder`：JPEG 独立编码器，用于获得色度抽样控制权
  （`image` 未暴露该选项，而 4:4:4 对证件照发丝边缘质量影响显著）

## 🔒 隐私

- 桌面版与移动版：图片仅在本机处理，不发起任何网络请求。
- Web 版：图片在浏览器内处理，不上传服务器。

## 📄 许可

[MIT License with Commons Clause License Condition v1.0](./LICENSE) © 2026
CrazyFigure. Free internal production use by businesses is permitted. You may
not sell PicPro itself or offer a paid product or service whose value
derives entirely or substantially from PicPro without prior written
authorization from the copyright holder. This is a source-available license,
not an OSI-approved open-source license.
