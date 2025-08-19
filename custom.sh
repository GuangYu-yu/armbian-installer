#!/bin/bash
set -euo pipefail

# 校验参数
if [ -z "${1:-}" ]; then
  echo "❌ 错误：未提供下载地址！"
  exit 1
fi

mkdir -p imm output
DOWNLOAD_URL="$1"
OUTPUT_PATH="imm/downloaded_file"

echo "下载地址: $DOWNLOAD_URL"
echo "保存路径: $OUTPUT_PATH"

# 下载文件
curl -k -L -o "$OUTPUT_PATH" "$DOWNLOAD_URL" || { echo "❌ 下载失败！"; exit 1; }
echo "✅ 下载成功!"
file "$OUTPUT_PATH"

# 生成稀疏 img 函数
CUSTOM_IMG="imm/custom.img"
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

# 提取最终文件名函数
get_extracted_filename() {
    local path="$1"
    local ftype
    ftype=$(file --mime-type -b "$path")
    local result=""

    case "$ftype" in
        application/gzip)
            result="${path%.gz}"
            ;;
        application/x-bzip2)
            result="${path%.bz2}"
            ;;
        application/x-xz)
            result="${path%.xz}"
            ;;
        application/x-7z-compressed)
            result=$(7z l "$path" | awk '/^----/{f=1;next} f && NF{print $6}' | head -n1)
            result="imm/$(basename "$result")"
            ;;
        application/x-tar)
            result=$(tar -tf "$path" | grep -v '/$' | head -n1)
            result="imm/$(basename "$result")"
            ;;
        application/zip)
            result=$(unzip -l "$path" | awk 'NR>3 {print $4}' | grep -v '/$' | head -n1)
            result="imm/$(basename "$result")"
            ;;
        *)
            result="$path"
            ;;
    esac

    echo "$result"
}

# 检查压缩包内容，判断是否为img文件
is_img_file=false
img_filename=""

case "$(file --mime-type -b "$OUTPUT_PATH")" in
    application/gzip)
        img_filename=$(gzip -l "$OUTPUT_PATH" 2>/dev/null | tail -n +2 | head -n1 | awk '{print $1}' || echo "")
        [[ "$img_filename" == *.img ]] && is_img_file=true
        ;;
    application/x-bzip2)
        img_filename=$(bzip2 -l "$OUTPUT_PATH" 2>/dev/null | tail -n +2 | head -n1 | awk '{print $1}' || echo "")
        [[ "$img_filename" == *.img ]] && is_img_file=true
        ;;
    application/x-xz)
        img_filename=$(xz -l "$OUTPUT_PATH" 2>/dev/null | tail -n +2 | head -n1 | awk '{print $1}' || echo "")
        [[ "$img_filename" == *.img ]] && is_img_file=true
        ;;
    application/x-7z-compressed)
        img_filename=$(7z l "$OUTPUT_PATH" | awk '/^----/{f=1;next} f && NF && $6 ~ /\.img$/ {print $6}' | head -n1)
        [ -n "$img_filename" ] && is_img_file=true
        ;;
    application/x-tar)
        img_filename=$(tar -tf "$OUTPUT_PATH" | grep '\.img$' | head -n1)
        [ -n "$img_filename" ] && is_img_file=true
        ;;
    application/zip)
        img_filename=$(unzip -l "$OUTPUT_PATH" | awk 'NR>3 {print $4}' | grep '\.img$' | head -n1)
        [ -n "$img_filename" ] && is_img_file=true
        ;;
    *)
        # 直接处理img文件
        if [[ "$OUTPUT_PATH" == *.img ]]; then
            is_img_file=true
            img_filename=$(basename "$OUTPUT_PATH")
        fi
        ;;
esac

# 根据是否为img文件选择处理方式
if [ "$is_img_file" = true ]; then
    echo "检测到img文件: $img_filename"
    echo "使用管道直接生成稀疏img..."
    
    # 直接通过管道解压并使用qemu-img转换为稀疏raw img
    case "$(file --mime-type -b "$OUTPUT_PATH")" in
        application/gzip)
            gunzip -c "$OUTPUT_PATH" | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        application/x-bzip2)
            bzip2 -dc "$OUTPUT_PATH" | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        application/x-xz)
            xz -dc "$OUTPUT_PATH" | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        application/x-7z-compressed)
            7z x -so "$OUTPUT_PATH" "$img_filename" 2>/dev/null | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        application/x-tar)
            tar -xOf "$OUTPUT_PATH" "$img_filename" | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        application/zip)
            unzip -p "$OUTPUT_PATH" "$img_filename" | qemu-img convert -O raw -S 1M - "$CUSTOM_IMG"
            ;;
        *)
            qemu-img convert -O raw -S 1M "$OUTPUT_PATH" "$CUSTOM_IMG"
            ;;
    esac
    
    EXTRACTED_FILE="imm/$img_filename"
    ORIGINAL_BASE_FILENAME=$(basename "$img_filename" .img)
    
else
    echo "未检测到img文件，使用传统解压+转换方式"
    
    # 传统方式：先解压再转换
    EXTRACTED_FILE=$(get_extracted_filename "$OUTPUT_PATH")
    
    case "$(file --mime-type -b "$OUTPUT_PATH")" in
        application/gzip) gunzip -c "$OUTPUT_PATH" > "$EXTRACTED_FILE";;
        application/x-bzip2) bzip2 -dc "$OUTPUT_PATH" > "$EXTRACTED_FILE";;
        application/x-xz) xz -dc "$OUTPUT_PATH" > "$EXTRACTED_FILE";;
        application/x-7z-compressed) 7z x "$OUTPUT_PATH" -oimm/ || true;;
        application/x-tar) tar -xf "$OUTPUT_PATH" -C imm/ || true;;
        application/zip) unzip -j -o "$OUTPUT_PATH" -d imm/ || true;;
        *) ;; # 保留原文件
    esac
    
    # 删除原始压缩包
    rm -f "$OUTPUT_PATH"
    
    echo "解压完成，文件: $EXTRACTED_FILE"
    
    # 转为稀疏 img
    make_sparse_img "$EXTRACTED_FILE"
    
    # 检查结果
    if [ ! -f "$CUSTOM_IMG" ]; then
        echo "❌ 转换失败，未生成 $CUSTOM_IMG"
        exit 1
    fi
    
    echo "✅ 稀疏 img 生成成功: $CUSTOM_IMG"
    
    # 保存原始文件名
    ORIGINAL_BASE_FILENAME=$(basename "$EXTRACTED_FILE")
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.img}
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.qcow2}
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vdi}
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vmdk}
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.vhd}
    ORIGINAL_BASE_FILENAME=${ORIGINAL_BASE_FILENAME%.raw}
fi

echo "保存原始文件名: $ORIGINAL_BASE_FILENAME"

ls -lh --block-size=1 imm/
echo "✅ 准备合成 自定义OpenWrt 安装器"

# Docker 构建
docker run --privileged --rm \
    -v "$(pwd)"/output:/output \
    -v "$(pwd)"/supportFiles:/supportFiles:ro \
    -v "$(pwd)"/$CUSTOM_IMG:/mnt/custom.img \
    -e EXTRACTED_FILE="$ORIGINAL_BASE_FILENAME" \
    debian:buster \
    /supportFiles/custom/build.sh
