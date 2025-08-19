#!/bin/bash
set -euo pipefail

# 校验参数
if [ -z "${1:-}" ]; then
  echo "❌ 错误：未提供下载地址！"
  exit 1
fi

mkdir -p imm
DOWNLOAD_URL="$1"
filename=$(basename "$DOWNLOAD_URL")
OUTPUT_PATH="imm/$filename"
CUSTOM_IMG="imm/custom.img"

echo "下载地址: $DOWNLOAD_URL"
echo "保存路径: $OUTPUT_PATH"

# 下载文件
curl -k -L -o "$OUTPUT_PATH" "$DOWNLOAD_URL" || { echo "❌ 下载失败！"; exit 1; }
echo "✅ 下载成功!"
file "$OUTPUT_PATH"

# 生成稀疏 img 函数
make_sparse_img() {
    local input="$1"
    echo "生成稀疏 img: $CUSTOM_IMG"
    if command -v qemu-img &>/dev/null; then
        FORMAT=$(qemu-img info "$input" 2>/dev/null | awk '/file format/{print $3}' || true)
        if [ -n "$FORMAT" ] && [ "$FORMAT" != "raw" ]; then
            qemu-img convert -O raw -S 1M "$input" "$CUSTOM_IMG"
        else
            cp --sparse=always "$input" "$CUSTOM_IMG"
        fi
    else
        cp --sparse=always "$input" "$CUSTOM_IMG"
    fi
    # 删除原文件，避免占用空间
    [ "$input" != "$CUSTOM_IMG" ] && rm -f "$input"
}

# 解压或转换
EXTRACTED_FILE=""

FILE_TYPE=$(file --mime-type -b "$OUTPUT_PATH")
case "$FILE_TYPE" in
    application/gzip)
        FNAME="${filename%.gz}"
        gunzip -c "$OUTPUT_PATH" > "imm/$FNAME"
        EXTRACTED_FILE="imm/$FNAME"
        rm -f "$OUTPUT_PATH"
        ;;
    application/x-bzip2)
        FNAME="${filename%.bz2}"
        bzip2 -dc "$OUTPUT_PATH" > "imm/$FNAME"
        EXTRACTED_FILE="imm/$FNAME"
        rm -f "$OUTPUT_PATH"
        ;;
    application/x-xz)
        FNAME="${filename%.xz}"
        xz -dc "$OUTPUT_PATH" > "imm/$FNAME"
        EXTRACTED_FILE="imm/$FNAME"
        rm -f "$OUTPUT_PATH"
        ;;
    application/x-7z-compressed)
        FILE_IN_7Z=$(7z l "$OUTPUT_PATH" | awk '/^----/{f=1;next} f && NF{print $6}' | head -n1)
        7z x "$OUTPUT_PATH" -oimm/ || true
        EXTRACTED_FILE="imm/$(basename "$FILE_IN_7Z")"
        rm -f "$OUTPUT_PATH"
        ;;
    application/x-tar)
        FILE_IN_TAR=$(tar -tf "$OUTPUT_PATH" | grep -v '/$' | head -n1)
        tar -xf "$OUTPUT_PATH" -C imm/ || true
        EXTRACTED_FILE="imm/$(basename "$FILE_IN_TAR")"
        rm -f "$OUTPUT_PATH"
        ;;
    application/zip)
        FILE_IN_ZIP=$(unzip -l "$OUTPUT_PATH" | awk 'NR>3 {print $4}' | grep -v '/$' | head -n1)
        unzip -j -o "$OUTPUT_PATH" -d imm/ || true
        EXTRACTED_FILE="imm/$(basename "$FILE_IN_ZIP")"
        rm -f "$OUTPUT_PATH"
        ;;
    *)
        # 按扩展名兜底处理
        extension="${filename##*.}"
        case "$extension" in
            gz)
                FNAME="${filename%.gz}"
                gunzip -c "$OUTPUT_PATH" > "imm/$FNAME"
                EXTRACTED_FILE="imm/$FNAME"
                rm -f "$OUTPUT_PATH"
                ;;
            bz2)
                FNAME="${filename%.bz2}"
                bzip2 -dc "$OUTPUT_PATH" > "imm/$FNAME"
                EXTRACTED_FILE="imm/$FNAME"
                rm -f "$OUTPUT_PATH"
                ;;
            xz)
                FNAME="${filename%.xz}"
                xz -dc "$OUTPUT_PATH" > "imm/$FNAME"
                EXTRACTED_FILE="imm/$FNAME"
                rm -f "$OUTPUT_PATH"
                ;;
            zip)
                unzip -j -o "$OUTPUT_PATH" -d imm/ || true
                EXTRACTED_FILE=$(find imm -type f -printf "%T@ %p\n" | sort -nr | head -n1 | awk '{print $2}')
                rm -f "$OUTPUT_PATH"
                ;;
            img)
                EXTRACTED_FILE="$OUTPUT_PATH"
                ;;
            *)
                echo "❌ 不支持的文件格式: $extension"
                exit 1
                ;;
        esac
        ;;
esac

# 转为稀疏 img
make_sparse_img "$EXTRACTED_FILE"

# 检查结果
if [ ! -f "$CUSTOM_IMG" ]; then
    echo "❌ 转换失败，未生成 $CUSTOM_IMG"
    exit 1
fi

echo "✅ 稀疏 img 生成成功: $CUSTOM_IMG"

# 保存原始文件名（去掉常见镜像后缀）
ORIGINAL_BASE_FILENAME=$(basename "$EXTRACTED_FILE")
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.img}
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.qcow2}
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vdi}
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vmdk}
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vhd}
ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.raw}
echo "保存原始文件名: $ORIGINAL_BASE_FILENAME"

ls -lh --block-size=1 imm/
echo "✅ 准备合成 自定义OpenWrt 安装器"

# Docker 构建
mkdir -p output
docker run --privileged --rm \
    -v "$(pwd)"/output:/output \
    -v "$(pwd)"/supportFiles:/supportFiles:ro \
    -v "$CUSTOM_IMG":/mnt/custom.img \
    -e EXTRACTED_FILE="$ORIGINAL_BASE_FILENAME" \
    debian:buster \
    /supportFiles/custom/build.sh
