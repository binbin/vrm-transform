#!/bin/bash

# 安装 toktx 工具脚本
# 从 KTX-Software releases 下载并安装

set -e

KTX_VERSION="4.4.2"
ARCH=$(uname -m)

echo "检测到系统架构: $ARCH"

if [ "$ARCH" = "arm64" ]; then
    PKG_NAME="KTX-Software-${KTX_VERSION}-Darwin-arm64.pkg"
    DOWNLOAD_URL="https://github.com/KhronosGroup/KTX-Software/releases/download/v${KTX_VERSION}/${PKG_NAME}"
elif [ "$ARCH" = "x86_64" ]; then
    PKG_NAME="KTX-Software-${KTX_VERSION}-Darwin-x86_64.pkg"
    DOWNLOAD_URL="https://github.com/KhronosGroup/KTX-Software/releases/download/v${KTX_VERSION}/${PKG_NAME}"
else
    echo "错误: 不支持的架构: $ARCH"
    exit 1
fi

echo "正在下载 ${PKG_NAME}..."
TMP_DIR=$(mktemp -d)
PKG_FILE="${TMP_DIR}/${PKG_NAME}"

if command -v curl &> /dev/null; then
    curl -L -o "$PKG_FILE" "$DOWNLOAD_URL"
elif command -v wget &> /dev/null; then
    wget -O "$PKG_FILE" "$DOWNLOAD_URL"
else
    echo "错误: 需要 curl 或 wget 来下载文件"
    exit 1
fi

# 默认使用本地安装（不需要 sudo）
INSTALL_METHOD=2
# 如果提供了参数 --system，则使用系统安装
if [ "$1" = "--system" ]; then
    INSTALL_METHOD=1
fi

if [ "$INSTALL_METHOD" = "1" ]; then
    echo "正在系统安装（需要 sudo 权限）..."
    sudo installer -pkg "$PKG_FILE" -target /
    INSTALL_PATH="/usr/local/bin"
else
    echo "正在本地安装到 ./bin 目录..."
    echo "正在本地安装..."
    # 创建本地 bin 目录
    LOCAL_BIN_DIR="./bin"
    mkdir -p "$LOCAL_BIN_DIR"
    
    # 提取 .pkg 文件内容
    EXTRACT_DIR="${TMP_DIR}/extract"
    mkdir -p "$EXTRACT_DIR"
    
    echo ""
    echo "本地安装需要从 .pkg 文件中提取二进制文件，这比较复杂。"
    echo "建议使用系统安装方式（需要 sudo 权限）:"
    echo ""
    echo "  ./install-toktx.sh --system"
    echo ""
    echo "或者手动安装:"
    echo "  1. 打开下载的 .pkg 文件: open $PKG_FILE"
    echo "  2. 按照安装向导完成安装"
    echo "  3. 安装后 toktx 将位于 /usr/local/bin/toktx"
    echo ""
    rm -rf "$TMP_DIR"
    exit 1
fi

# 清理临时文件
rm -rf "$TMP_DIR"

echo "安装完成！"
echo "验证安装..."
if [ "$INSTALL_METHOD" = "2" ]; then
    export PATH="$(pwd)/bin:$PATH"
fi

if command -v toktx &> /dev/null; then
    toktx --version
    echo ""
    echo "toktx 已成功安装到: $INSTALL_PATH"
    if [ "$INSTALL_METHOD" = "2" ]; then
        echo ""
        echo "注意: 本地安装方式，请确保在运行程序前将 ./bin 添加到 PATH:"
        echo "  export PATH=\"\$(pwd)/bin:\$PATH\""
        echo ""
        echo "或者更新 run.sh 脚本以自动设置 PATH"
    fi
else
    echo "警告: toktx 未在 PATH 中找到"
    if [ "$INSTALL_METHOD" = "1" ]; then
        echo "可能需要重启终端或运行:"
        echo "  export PATH=\"/usr/local/bin:\$PATH\""
    fi
fi
