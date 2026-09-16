# PicPro Web 版容器镜像
#
# 两阶段构建：
#   1. builder —— 用 Flutter SDK 镜像，并把 Rust 内核编译成 WASM，最后产出 Flutter Web 静态文件；
#   2. runtime —— 只保留产物，用 nginx 托管，镜像体积小且不含任何构建工具链。
#
# Web 版全部处理都在浏览器内完成，容器只做静态托管，不承担任何图像计算，
# 因此运行阶段对服务器 CPU/内存几乎没有要求。

# ---------------- 阶段 1：构建 ----------------
# 说明：这里用 stable 标签以便持续可用；对构建可复现性有要求时，
# 应改为固定版本标签（如 ghcr.io/cirruslabs/flutter:3.44.8）。
FROM ghcr.io/cirruslabs/flutter:stable AS builder

USER root

# Rust 工具链。
# Web 端必须用 nightly：内核编译为多线程 WASM（依赖共享内存），
# 需要 `-Z build-std` 重建标准库，因此同时要装 rust-src 组件。
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain stable \
 && /root/.cargo/bin/rustup toolchain install nightly --profile minimal --component rust-src \
 && /root/.cargo/bin/rustup target add wasm32-unknown-unknown
ENV PATH="/root/.cargo/bin:${PATH}"

# wasm-pack：flutter_rust_bridge 的 Web 构建依赖它
RUN curl -sSf https://rustwasm.github.io/wasm-pack/installer/init.sh | sh

# 绑定生成器。版本必须与 rust/Cargo.toml 中 flutter_rust_bridge 的版本严格一致，
# 否则生成的胶水代码与运行时结构不匹配。
RUN cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked

WORKDIR /app

# 先只拷贝依赖描述文件，让依赖层能被 Docker 缓存复用：
# 源码改动不会导致每次重新拉取 pub 与 cargo 依赖。
COPY pubspec.yaml pubspec.lock ./
COPY rust/Cargo.toml rust/Cargo.lock ./rust/
RUN flutter pub get

COPY . .

# 1) Rust -> WASM；2) Flutter Web 产物
RUN flutter config --enable-web \
 && flutter_rust_bridge_codegen build-web --release \
 && flutter build web --release

# ---------------- 阶段 2：运行 ----------------
FROM nginx:1.27-alpine AS runtime

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# 容器自身健康检查：nginx 就绪即视为可用
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
