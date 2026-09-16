# 在 1Panel 上部署 PicPro Web 版

Web 版的全部图像处理都在**浏览器内**完成，服务器只负责托管静态文件。
这意味着：容器几乎不消耗 CPU 与内存，用户的图片也不会离开自己的设备。

三条路线任选其一：

| 路线 | 适用场景 | 需要构建 | 耗时 |
|---|---|---|---|
| **A. 直接拉官方镜像** | 绝大多数情况，**推荐** | 否 | 1~2 分钟 |
| B. 从源码构建容器 | 需要改代码，或不想依赖 Docker Hub | 是 | 首次 10~25 分钟 |
| C. 静态网站 | 已有静态站点环境，不想引入容器 | 是（或下载 Release 产物） | 视情况 |

---

## 路线 A：直接拉取官方镜像（推荐）

镜像已发布到 Docker Hub，公开可拉取，且**同时提供 amd64 与 arm64**，
compose 或 docker run 会自动选择匹配服务器架构的那一份，无需手工指定。

可用标签：

| 标签 | 含义 |
|---|---|
| `latest` | 最新正式版本 |
| `0.1.0` / `0.1` | 固定版本，**生产环境建议用这类** |
| `edge` | main 分支的最新构建，用于尝鲜 |

### 方式 1：1Panel 编排（界面操作）

1. 进入 **容器 → 编排 → 创建编排**。
2. 名称填 `picpro`。
3. 把仓库中 `deploy/docker-compose.image.yml` 的内容粘贴进编排内容。
4. 确认创建，1Panel 会自动拉取镜像并启动容器。
5. 访问 `http://<服务器IP>:8080`。

### 方式 2：命令行

```bash
docker run -d --name picpro -p 8080:80 --restart unless-stopped \
  crazyfigure/picpro:0.1.0
```

### 方式 3：在 1Panel 里先拉镜像再创建容器

1. 进入 **容器 → 镜像 → 拉取镜像**，镜像名填写 `crazyfigure/picpro`，标签填 `0.1.0`。
2. 拉取完成后进入 **容器 → 容器 → 创建容器**，选择该镜像。
3. 端口映射填 `8080` → `80`（容器内固定监听 80）。
4. 重启策略选择「除非手动停止」，创建即可。

> 镜像已内置 nginx 配置，包含单页应用回退、`.wasm` 的 MIME 类型，
> 以及**必需的跨源隔离响应头**（见下文说明），无需再手工调整。

---

## 路线 B：从源码构建容器

适合需要改代码、或不想依赖 Docker Hub 的场景。

### 方式 1：1Panel 编排

1. 先在服务器上取到源码：`git clone https://github.com/CrazyFigure/PicPro.git`
2. 进入 **容器 → 编排 → 创建编排**，名称填 `picpro`。
3. 粘贴 `deploy/docker-compose.yml` 的内容，并把 `context: ..`
   改为仓库的**绝对路径**（编排文件的相对路径基准与仓库不同，写相对路径会找不到上下文）。
4. 确认创建，等待构建完成。

### 方式 2：命令行

```bash
git clone https://github.com/CrazyFigure/PicPro.git
cd PicPro
docker compose -f deploy/docker-compose.yml up -d --build
```

### 方式 3：本地构建好镜像再上传

服务器性能有限时，在本地构建并导出，避免在服务器上跑完整工具链：

```bash
docker build -f deploy/Dockerfile -t picpro-web:latest .
docker save picpro-web:latest | gzip > picpro-web.tar.gz
# 上传到服务器后
docker load < picpro-web.tar.gz
docker run -d --name picpro -p 8080:80 --restart unless-stopped picpro-web:latest
```

> 从源码构建需下载 Flutter 镜像并编译 Rust 与 Flutter，服务器需能访问外网。
> 构建完成后运行阶段完全离线可用。

---

## 路线 C：静态网站

适合已有静态站点环境、不想引入容器的场景。
但**必须自行配置跨源隔离响应头**，否则页面无法运行（见下方「关键配置」）。

1. 取得 Web 产物，二选一：
   - 从 [GitHub Release](https://github.com/CrazyFigure/PicPro/releases) 下载 `PicPro-Web.zip`；
   - 或本地构建后打包：
     ```bash
     flutter_rust_bridge_codegen build-web --release
     flutter build web --release
     cd build/web && zip -r ../../PicPro-Web.zip .
     ```

2. 进入 **网站 → 静态网站**，创建站点，记下域名与根目录。

3. 进入站点根目录（通常是 `/opt/1panel/www/sites/<站点名>/index`），
   清空默认内容后上传并解压 `PicPro-Web.zip`，确保 `index.html` 位于根目录。

4. 打开该站点的 **配置文件**，把 nginx 配置替换为仓库中的
   `deploy/nginx.conf`（注意修改 `root` 指向实际目录），至少必须包含：

   ```nginx
   server {
       root /opt/1panel/www/sites/<站点名>/index;
       index index.html;

       # 跨源隔离：多线程 WASM 的硬性前提，缺了页面直接打不开
       add_header Cross-Origin-Opener-Policy "same-origin" always;
       add_header Cross-Origin-Embedder-Policy "require-corp" always;

       # 不要在这里写 types 块来补 wasm 类型。
       # nginx 的 types 在 server/location 层是「替换」而非「合并」http 层的类型表，
       # 一旦写了（哪怕只为补一行 wasm），.html 等映射会全部丢失，
       # 浏览器就会把 index.html 当二进制文件下载。nginx 自带的 mime.types
       # 本就包含 application/wasm，无需另行声明。

       location = /index.html { expires -1; }         # 入口不缓存
       location ~* \.(?:js|wasm|css|png|svg|woff2?)$ { expires 30d; }
       location / { try_files $uri $uri/ /index.html; }  # 单页应用回退
   }
   ```

5. 重载 nginx 后打开域名。

> **为什么这两个头不可省**：Rust 内核编译为**多线程 WASM**，以
> `SharedArrayBuffer` 作为共享内存。浏览器只在页面处于「跨源隔离」状态时
> 才允许使用它，而该状态正是由上面两个响应头开启的。缺少它们，
> 页面会在控制台报 `SharedArrayBuffer is not defined` 并直接卡住。
>
> 另外注意：`add_header` 在 nginx 中是**覆盖而非继承**——
> 一旦在 `location` 里写了 `add_header`，该 location 就会丢掉上面这些头。
> 因此缓存控制要改用 `expires`（独立机制，不影响继承），
> 就像上面示例那样。

---

## 反向代理与 HTTPS

三种路线都建议套一层反向代理并启用证书：

1. 进入 **网站 → 反向代理**，新建代理，目标填 `http://127.0.0.1:8080`
   （静态网站路线则直接给站点申请证书即可）。
2. 为该网站申请 Let's Encrypt 证书，并开启强制 HTTPS。

> 反向代理只做转发，不会影响上面的跨源隔离响应头，
> 但若在代理层额外添加了 `add_header`，需确认没有覆盖掉 `COOP` 与 `COEP`。
> 可以在浏览器开发者工具的 Network 面板里检查响应头是否仍然存在。

---

## 资源占用与耗时

| 阶段 | 路线 A（拉镜像） | 路线 B（源码构建） |
|---|---|---|
| 首次部署 | 拉取约 72 MB 镜像，1~2 分钟 | 10~25 分钟，取决于网络与 CPU |
| 后续重建 | 重新拉取即可 | 依赖层有缓存，通常 2~5 分钟 |
| 运行阶段 | nginx 托管静态文件，内存约 10~20 MB | 同上 |

路线 A 对服务器配置基本没有要求；路线 B 建议至少 **2 核 4GB**，
低于此配置建议改用路线 A，或采用「本地构建后上传镜像」。

---

## 常见问题

**页面空白，控制台报 `SharedArrayBuffer is not defined`**

这是最常见的部署问题：服务器没有发送跨源隔离响应头。
确认响应头中包含：

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

用官方镜像（路线 A）不会出现该问题；自行配置 nginx 时请对照 `deploy/nginx.conf`。

**打开网址后浏览器直接下载了一个文件，而不是显示页面**

这是 MIME 类型丢失导致的：`index.html` 没有被识别为 `text/html`，
浏览器就把它当二进制文件下载了。

最常见的原因是 nginx 配置里在 server 或 location 层写了 `types` 块
（常见于想补 `application/wasm wasm`）。nginx 的 `types` 在这些层级是
**替换**而非合并 http 层的类型表，一写就会把 `.html` 等映射全部覆盖掉，
随后回落到 `default_type`（官方 nginx 镜像设为 `application/octet-stream`）。

解决：删掉那个 `types` 块即可。nginx 自带的 `mime.types` 本来就包含
`application/wasm`，不需要手动声明。可以用下面的命令确认当前返回的类型：

```bash
curl -sI http://<你的地址>/ | grep -i content-type
# 正常应为 text/html
```

**页面刷新后 404**

静态网站路线缺少单页应用回退，需加上 `try_files $uri $uri/ /index.html;`。
官方镜像已内置该配置。

**页面能打开但功能无响应**

检查 `.wasm` 是否被正确返回：响应头的 `Content-Type` 应为 `application/wasm`。
类型不对会禁用浏览器的流式编译，严重时直接加载失败。

**上传/导出没有反应**

浏览器不允许网页直接写入指定文件夹，Web 版的保存行为是逐个触发下载。
若浏览器拦截了多文件下载，请在地址栏权限提示中允许本站点下载多个文件。

**处理大图时页面卡顿**

Web 版的 WASM 内核运行在浏览器主线程之外，但受浏览器内存限制，
单张图片建议不超过 50MP。批量处理超大图请使用 Windows 桌面版。

**arm64 服务器（如部分云厂商的实例）能用吗**

可以。官方镜像同时提供 `linux/amd64` 与 `linux/arm64`，
Docker 会自动拉取匹配架构的那一份，无需任何额外配置。
