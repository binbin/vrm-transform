FROM golang:1.21rc2-bookworm

# 使用国内 apt 镜像源加速（使用更稳健的方法）
RUN echo "deb https://mirrors.aliyun.com/debian/ bookworm main non-free-firmware" > /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian/ bookworm-updates main non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb https://mirrors.aliyun.com/debian-security bookworm-security main" >> /etc/apt/sources.list && \
    rm -rf /etc/apt/sources.list.d/* || true

# 设置 Go 代理加速
RUN go env -w GOPROXY=https://goproxy.cn,direct && \
    go env -w GOSUMDB=sum.golang.google.cn

# 安装系统依赖并安装 KTX-Software
RUN apt update -y && \
    apt install -y libvips-dev wget ca-certificates dpkg-dev build-essential cmake git && \
    ARCH=$(dpkg --print-architecture) && \
    echo "Detected architecture: $ARCH" && \
    DEB_FILE="/tmp/ktx.deb" && \
    if [ "$ARCH" = "amd64" ]; then \
        DEB_URL="https://github.com/KhronosGroup/KTX-Software/releases/download/v4.2.1/KTX-Software-4.2.1-Linux-x86_64.deb" && \
        wget -q -O "$DEB_FILE" "$DEB_URL" && \
        dpkg -i "$DEB_FILE" || apt-get install -f -y && \
        TOKTX_PATH=$(find /usr -name "toktx" -type f 2>/dev/null | head -1) && \
        if [ -z "$TOKTX_PATH" ]; then \
            EXTRACT_DIR="/tmp/ktx-extract" && \
            mkdir -p "$EXTRACT_DIR" && \
            dpkg-deb -x "$DEB_FILE" "$EXTRACT_DIR" && \
            TOKTX_PATH=$(find "$EXTRACT_DIR" -name "toktx" -type f 2>/dev/null | head -1) && \
            LIB_PATH=$(find "$EXTRACT_DIR" -name "libktx.so*" -type f 2>/dev/null | head -1) && \
            if [ -n "$TOKTX_PATH" ] && [ -f "$TOKTX_PATH" ]; then \
                mkdir -p /usr/local/bin && \
                cp "$TOKTX_PATH" /usr/local/bin/toktx && \
                chmod +x /usr/local/bin/toktx; \
            fi && \
            if [ -n "$LIB_PATH" ] && [ -f "$LIB_PATH" ]; then \
                LIB_DIR=$(dirname "$LIB_PATH" | sed 's|/tmp/ktx-extract||') && \
                mkdir -p "/usr/local$LIB_DIR" && \
                find "$EXTRACT_DIR" -name "libktx.so*" -exec cp {} "/usr/local$LIB_DIR/" \; && \
                ldconfig; \
            fi && \
            rm -rf "$EXTRACT_DIR"; \
        else \
            mkdir -p /usr/local/bin && \
            ln -sf "$TOKTX_PATH" /usr/local/bin/toktx 2>/dev/null || cp "$TOKTX_PATH" /usr/local/bin/toktx && \
            chmod +x /usr/local/bin/toktx; \
        fi && \
        rm -f "$DEB_FILE"; \
    elif [ "$ARCH" = "arm64" ]; then \
        echo "ARM64 detected, building from source..." && \
        cd /tmp && \
        git clone --depth 1 --branch v4.2.1 https://github.com/KhronosGroup/KTX-Software.git ktx-source || \
        (wget -q https://github.com/KhronosGroup/KTX-Software/archive/refs/tags/v4.2.1.tar.gz && \
         tar -xzf v4.2.1.tar.gz && \
         mv KTX-Software-4.2.1 ktx-source) && \
        cd ktx-source && \
        mkdir build && cd build && \
        cmake .. -DKTX_FEATURE_STATIC_LIBRARY=OFF -DKTX_FEATURE_TOOLS=ON -DCMAKE_INSTALL_PREFIX=/usr/local && \
        make -j$(nproc) && \
        make install && \
        cd / && rm -rf /tmp/ktx-source /tmp/v4.2.1.tar.gz; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    which toktx && \
    (toktx --version 2>&1 || echo "toktx installed but version check skipped") && \
    echo "Checking toktx dependencies..." && \
    (ldd /usr/local/bin/toktx 2>/dev/null || echo "Static binary or ldd not available") && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# 确保运行时依赖可用（包括所有可能的依赖）
RUN apt update -y && \
    apt install -y libstdc++6 libgcc-s1 libc6 libzstd1 libz1 libbz2-1.0 liblzma5 binutils && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:/usr/bin:${PATH}"

# 验证 toktx 可用并更新动态链接库缓存
RUN which toktx && \
    ls -la /usr/local/bin/toktx && \
    file /usr/local/bin/toktx && \
    echo "Updating library cache..." && \
    ldconfig && \
    echo "Checking toktx dependencies:" && \
    ldd /usr/local/bin/toktx 2>/dev/null || echo "Cannot check dependencies" && \
    echo "Testing toktx:" && \
    /usr/local/bin/toktx --version

# 复制代码并构建（放在最后，代码变更时只需重新构建这一层）
COPY . /app
WORKDIR /app

RUN go mod download && \
    go build -o main main.go

EXPOSE 4000
ENV PORT=4000
CMD ["./main"]
