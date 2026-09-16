# 在 1Panel 上部署 PicPro Web 版

Web 版的全部图像处理都在**浏览器内**完成，服务器只负责托管静态文件。
这意味着：容器几乎不消耗 CPU 与内存，用户的图片也不会离开自己的设备。

下面两条路线任选其一。已有 1Panel 环境时推荐路线 B（容器）。

---

## 路线 A：静态网站（最简单）

适合只需要托管、不想引入容器的场景。

1. 取得 Web 产物。两种方式：
   - 从 GitHub Release 下载 `PicPro-Web.zip`（推 `v*` 标签后自动产出）；
   - 或本地构建后打包：
     ```bash
     flutter_rust_bridge_codegen build-web --release
     flutter build web --release
     cd build/web && zip -r ../../PicPro-Web.zip .
     ```

2. 在 1Panel 左侧进入 **网站 → 静态网站**，创建一个站点，记下域名与根目录。

3. 进入该站点的**根目录**（通常是 `/opt/1panel/www/sites/<站点名>/index`），
   清空默认内容后上传并解压 `PicPro-Web.zip`，确保 `index.html` 位于根目录。

4. 打开域名即可使用。

> 若刷新页面出现 404，说明服务器未配置单页应用回退。
> 在站点的 nginx 配置中加入：
> ```nginx
> location / { try_files $uri $uri/ /index.html; }
> ```

---

## 路线 B：Docker 容器（推荐）

镜像自带 nginx 与正确的缓存、MIME、SPA 回退配置，无需手工调 nginx。

### 方式 1：1Panel 编排模板

1. 进入 **容器 → 编排 → 创建编排**。
2. 名称填 `picpro`，把仓库中 `deploy/docker-compose.yml` 的内容粘贴到编排内容里。
3. 确认构建上下文能取到仓库代码（若 1Panel 主机上没有源码，
   请先在主机上 `git clone` 仓库，并把 `context` 改为该仓库的绝对路径）。
4. 点击确认，等待构建完成（首次构建需编译 Rust 与 Flutter，耗时较长）。

### 方式 2：命令行

在服务器上执行：

```bash
git clone https://github.com/CrazyFigure/PicPro.git
cd PicPro
docker compose -f deploy/docker-compose.yml up -d --build
```

访问 `http://<服务器IP>:8080` 即可。端口在 `deploy/docker-compose.yml` 中调整。

### 方式 3：在本地构建好镜像再上传

服务器性能有限时，在本地构建并导出镜像，可避免在服务器上跑完整工具链：

```bash
docker build -f deploy/Dockerfile -t picpro-web:latest .
docker save picpro-web:latest | gzip > picpro-web.tar.gz
# 上传到服务器后
docker load < picpro-web.tar.gz
docker compose -f deploy/docker-compose.yml up -d
```

---

## 反向代理与 HTTPS

1Panel 的静态网站与容器都支持一键申请证书：

- 容器部署：进入 **网站 → 反向代理**，新建代理指向 `http://127.0.0.1:8080`，
  再为该网站申请 Let's Encrypt 证书并开启强制 HTTPS。
- 需要处理较大图片时，建议在代理配置中放宽请求体大小限制（默认值即可，
  因为图片并不会上传到服务器）。

> 提示：**不要把容器部署在无法访问外网的隔离网络**。首次构建需要拉取
> Flutter 镜像与 Rust 依赖；构建完成后运行阶段则完全离线可用。

---

## 构建耗时与资源建议

| 阶段 | 说明 |
|---|---|
| 首次构建 | 需下载 Flutter 镜像并编译 Rust/Flutter，通常 10~25 分钟，取决于网络与 CPU |
| 后续重建 | 依赖层被 Docker 缓存，通常 2~5 分钟 |
| 运行阶段 | nginx 托管静态文件，内存占用约 10~20 MB |

服务器建议至少 **2 核 4GB**；低于此配置建议采用上述「本地构建后上传镜像」的方式。

---

## 常见问题

**页面空白，控制台报 WASM 相关错误**

浏览器需支持 WebAssembly（Chrome、Edge、Firefox、Safari 的现代版本均支持）。
另外确认 nginx 返回的 `.wasm` MIME 类型是 `application/wasm`；
若自行配置 nginx，可直接使用仓库中的 `deploy/nginx.conf`。

**上传/导出没有反应**

浏览器不允许网页直接写入指定文件夹，Web 版的保存行为是逐个触发下载。
若浏览器拦截了多文件下载，请在地址栏权限提示中允许本站点下载多个文件。

**处理大图时页面卡顿**

Web 版的 WASM 内核运行在浏览器主线程之外，但受浏览器内存限制，
单张图片建议不超过 50MP。批量处理超大图请使用 Windows 桌面版。
