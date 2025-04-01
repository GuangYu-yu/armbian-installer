#!/bin/bash
set -euo pipefail  

# 校验参数是否存在
if [ -z "$1" ]; then
  echo "❌ 错误：未提供下载地址！"
  exit 1
fi

mkdir -p imm
DOWNLOAD_URL="$1"
filename=$(basename "$DOWNLOAD_URL")  # 从 URL 提取文件名
OUTPUT_PATH="imm/$filename"

echo "下载地址: $DOWNLOAD_URL"
echo "保存路径: $OUTPUT_PATH"

# 下载文件
if ! curl -k -L -o "$OUTPUT_PATH" "$DOWNLOAD_URL"; then
  echo "❌ 下载失败！"
  exit 1
fi

echo "✅ 下载成功!"
file "$OUTPUT_PATH"

# 检测文件类型
FILE_TYPE=$(file --mime-type -b "$OUTPUT_PATH")
EXTRACTED_FILE=""

# 处理不同的压缩格式
case "$FILE_TYPE" in
  application/gzip)
    echo "检测到 gzip 压缩，解压中..."
    gunzip -k "$OUTPUT_PATH" || true  # 忽略解压缩时的警告
    EXTRACTED_FILE="${OUTPUT_PATH%.gz}"
    ;;
  application/x-bzip2)
    echo "检测到 bzip2 压缩，解压中..."
    bzip2 -dk "$OUTPUT_PATH" || true
    EXTRACTED_FILE="${OUTPUT_PATH%.bz2}"
    ;;
  application/x-xz)
    echo "检测到 xz 压缩，解压中..."
    xz -dk "$OUTPUT_PATH" || true
    EXTRACTED_FILE="${OUTPUT_PATH%.xz}"
    ;;
  application/x-7z-compressed)
    echo "检测到 7z 压缩，解压中..."
    7z x "$OUTPUT_PATH" -oimm/ || true
    EXTRACTED_FILE=$(find imm -type f | head -n 1)
    ;;
  application/x-tar)
    echo "检测到 tar 压缩，解压中..."
    tar -xf "$OUTPUT_PATH" -C imm/ || true
    EXTRACTED_FILE=$(find imm -type f | head -n 1)
    ;;
  application/zip)
    echo "检测到 zip 压缩，解压中..."
    unzip -j -o "$OUTPUT_PATH" -d imm/ || true
    EXTRACTED_FILE=$(find imm -type f | head -n 1)
    ;;
  *)
    echo "未识别的文件类型，尝试按扩展名处理..."
    extension="${filename##*.}"  # 获取文件扩展名
    case $extension in
      gz)
        echo "按 .gz 处理..."
        gunzip -f "$OUTPUT_PATH" || true
        EXTRACTED_FILE="${OUTPUT_PATH%.gz}"
        ;;
      bz2)
        echo "按 .bz2 处理..."
        bzip2 -dk "$OUTPUT_PATH" || true
        EXTRACTED_FILE="${OUTPUT_PATH%.bz2}"
        ;;
      xz)
        echo "按 .xz 处理..."
        xz -d --keep "$OUTPUT_PATH" || true
        EXTRACTED_FILE="${OUTPUT_PATH%.xz}"
        ;;
      zip)
        echo "按 .zip 处理..."
        unzip -j -o "$OUTPUT_PATH" -d imm/ || true
        EXTRACTED_FILE=$(find imm -type f | head -n 1)
        ;;
      img)
        echo "直接使用 img 文件: $OUTPUT_PATH"
        EXTRACTED_FILE="$OUTPUT_PATH"
        ;;
      *)
        echo "❌ 不支持的文件格式: $extension"
        exit 1
        ;;
    esac
    ;;
esac

# 确保解压后有文件
if [ -z "$EXTRACTED_FILE" ]; then
  echo "❌ 解压失败或未找到解压后的文件，退出..."
  exit 1
fi

echo "解压完成，使用文件: $EXTRACTED_FILE"

# 检查文件是否为 img 格式，如果不是则转换
if [[ "$EXTRACTED_FILE" != *.img ]]; then
  echo "检测到非 img 格式文件，尝试转换为 img 格式..."
  
  # 尝试使用 qemu-img 检测格式
  if command -v qemu-img &> /dev/null; then
    FORMAT=$(qemu-img info "$EXTRACTED_FILE" 2>/dev/null | grep "file format" | awk '{print $3}')
    if [ -n "$FORMAT" ] && [ "$FORMAT" != "raw" ]; then
      echo "转换 $FORMAT 格式到 img 格式..."
      qemu-img convert -O raw "$EXTRACTED_FILE" "imm/custom.img"
      EXTRACTED_FILE="imm/custom.img"
    else
      # 如果是 raw 格式或无法检测，直接复制并重命名
      cp "$EXTRACTED_FILE" "imm/custom.img"
      EXTRACTED_FILE="imm/custom.img"
    fi
  else
    # 如果没有 qemu-img 命令，直接复制并重命名
    cp "$EXTRACTED_FILE" "imm/custom.img"
    EXTRACTED_FILE="imm/custom.img"
  fi
else
  # 如果已经是 img 格式，但不在 imm/custom.img 位置，则复制过去
  if [ "$EXTRACTED_FILE" != "imm/custom.img" ]; then
    cp "$EXTRACTED_FILE" "imm/custom.img"
    EXTRACTED_FILE="imm/custom.img"
  fi
fi

# 检查最终文件
if [ -f "imm/custom.img" ]; then
  ls -lh imm/
  echo "✅ 准备合成 自定义OpenWrt 安装器"
  
  # 获取原始文件名（不含路径和扩展名）
  ORIGINAL_FILENAME=$(basename "$1")
  ORIGINAL_FILENAME=${ORIGINAL_FILENAME%.*}
  echo "使用原始文件名: $ORIGINAL_FILENAME"
else
  echo "❌ 错误：最终文件 imm/custom.img 不存在"
  exit 1
fi

mkdir -p output
docker run --privileged --rm \
        -v $(pwd)/output:/output \
        -v $(pwd)/supportFiles:/supportFiles:ro \
        -v $(pwd)/imm/custom.img:/mnt/custom.img \
        -e EXTRACTED_FILE="$ORIGINAL_FILENAME" \
        debian:buster \
        /supportFiles/custom/build.sh
