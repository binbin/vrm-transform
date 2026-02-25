#!/bin/bash

# 检查依赖
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "错误: $1 未安装"
        return 1
    fi
    return 0
}

# 检查 pkg-config
if ! check_dependency pkg-config; then
    echo ""
    echo "请先安装 pkg-config:"
    echo "  brew install pkg-config"
    exit 1
fi

# 检查 vips (libvips)
if ! pkg-config --exists vips; then
    echo "错误: libvips 未安装或未找到"
    echo ""
    echo "请先安装 libvips:"
    echo "  brew install vips"
    exit 1
fi

# 检查 toktx (KTX-Software)
if ! check_dependency toktx; then
    # 检查本地 bin 目录
    if [ -f "./bin/toktx" ]; then
        export PATH="$(pwd)/bin:$PATH"
    else
        echo ""
        echo "错误: toktx 未安装"
        echo ""
        echo "请运行安装脚本:"
        echo "  ./install-toktx.sh"
        echo ""
        echo "或者手动安装 KTX-Software"
        exit 1
    fi
fi

# 设置 Go 代理加速（国内镜像）
export GOPROXY=https://goproxy.cn,direct
export GOSUMDB=sum.golang.google.cn

# 编译
echo "正在构建..."
go build -o main .

if [ $? -eq 0 ]; then
    echo "构建完成！运行 ./main 启动服务"
else
    echo "构建失败！"
    exit 1
fi
