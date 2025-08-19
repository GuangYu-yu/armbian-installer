#!/bin/bash
# 基于 https://willhaley.com/blog/custom-debian-live-environment/

set -e

echo "🔧 修复 buster 的源..."

cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

apt-get update

echo "🚀 开始执行 build.sh ..."

echo 安装所需工具
apt-get update
apt-get -y install debootstrap squashfs-tools xorriso isolinux syslinux-efi  grub-pc-bin grub-efi-amd64-bin mtools dosfstools parted

echo 创建用于制作镜像的目录
mkdir -p $HOME/LIVE_BOOT

echo 安装 Debian
debootstrap --arch=amd64 --variant=minbase buster $HOME/LIVE_BOOT/chroot http://archive.debian.org/debian/

echo 将支持文件复制到 chroot
cp -v /supportFiles/installChroot.sh $HOME/LIVE_BOOT/chroot/installChroot.sh
cp -v /supportFiles/custom/ddd $HOME/LIVE_BOOT/chroot/usr/bin/ddd
chmod +x $HOME/LIVE_BOOT/chroot/usr/bin/ddd
# 确保安装脚本有执行权限
chmod +x $HOME/LIVE_BOOT/chroot/installChroot.sh
cp -v /supportFiles/sources.list $HOME/LIVE_BOOT/chroot/etc/apt/sources.list

echo 挂载 dev / proc / sys
mount -t proc none $HOME/LIVE_BOOT/chroot/proc
mount -o bind /dev $HOME/LIVE_BOOT/chroot/dev
mount -o bind /sys $HOME/LIVE_BOOT/chroot/sys

echo 在 chroot 中运行安装脚本
chroot $HOME/LIVE_BOOT/chroot /installChroot.sh

echo 清理 chroot
rm -v $HOME/LIVE_BOOT/chroot/installChroot.sh
mv -v $HOME/LIVE_BOOT/chroot/packages.txt /output/packages.txt

echo 复制 systemd-networkd 配置
cp -v /supportFiles/99-dhcp-en.network $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chown -v root:root $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network
chmod -v 644 $HOME/LIVE_BOOT/chroot/etc/systemd/network/99-dhcp-en.network

echo 启用自动登录
mkdir -p -v $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/
cp -v /supportFiles/override.conf $HOME/LIVE_BOOT/chroot/etc/systemd/system/getty@tty1.service.d/override.conf

echo 卸载 dev / proc / sys
umount $HOME/LIVE_BOOT/chroot/proc
umount $HOME/LIVE_BOOT/chroot/dev
umount $HOME/LIVE_BOOT/chroot/sys

echo 创建目录以包含实时环境文件和临时文件
mkdir -p $HOME/LIVE_BOOT/{staging/{EFI/boot,boot/grub/x86_64-efi,isolinux,live},tmp}

echo 将 chroot 环境压缩为 Squash 文件系统
cp /mnt/custom.img ${HOME}/LIVE_BOOT/chroot/mnt/
ls ${HOME}/LIVE_BOOT/chroot/mnt/
mksquashfs $HOME/LIVE_BOOT/chroot $HOME/LIVE_BOOT/staging/live/filesystem.squashfs -e boot

echo 复制内核和 initrd
cp -v $HOME/LIVE_BOOT/chroot/boot/vmlinuz-* $HOME/LIVE_BOOT/staging/live/vmlinuz
cp -v $HOME/LIVE_BOOT/chroot/boot/initrd.img-* $HOME/LIVE_BOOT/staging/live/initrd

echo 复制启动配置文件
cp -v /supportFiles/custom/isolinux.cfg $HOME/LIVE_BOOT/staging/isolinux/isolinux.cfg
cp -v /supportFiles/custom/grub.cfg $HOME/LIVE_BOOT/staging/boot/grub/grub.cfg
cp -v /supportFiles/grub-standalone.cfg $HOME/LIVE_BOOT/tmp/grub-standalone.cfg
touch $HOME/LIVE_BOOT/staging/DEBIAN_CUSTOM

echo 复制启动镜像
cp -v /usr/lib/ISOLINUX/isolinux.bin "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v /usr/lib/syslinux/modules/bios/* "${HOME}/LIVE_BOOT/staging/isolinux/"
cp -v -r /usr/lib/grub/x86_64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/x86_64-efi/"

echo 制作 UEFI grub 文件
grub-mkstandalone --format=x86_64-efi --output=$HOME/LIVE_BOOT/tmp/bootx64.efi --locales=""  --fonts="" "boot/grub/grub.cfg=$HOME/LIVE_BOOT/tmp/grub-standalone.cfg"

cd $HOME/LIVE_BOOT/staging/EFI/boot
SIZE=`expr $(stat --format=%s $HOME/LIVE_BOOT/tmp/bootx64.efi) + 65536`
dd if=/dev/zero of=efiboot.img bs=$SIZE count=1
/sbin/mkfs.vfat efiboot.img
mmd -i efiboot.img efi efi/boot
mcopy -vi efiboot.img $HOME/LIVE_BOOT/tmp/bootx64.efi ::efi/boot/

# 设置输出文件名
if [ ! -z "$EXTRACTED_FILE" ]; then
  ORIGINAL_FILENAME="$EXTRACTED_FILE"
else
  # 添加默认值
  ORIGINAL_FILENAME="custom"
fi

ISO_OUTPUT="/output/${ORIGINAL_FILENAME}.iso"
COMPRESSED_OUTPUT="/output/${ORIGINAL_FILENAME}.7z"

echo 构建 ISO
xorriso \
    -as mkisofs \
    -iso-level 3 \
    -o "$ISO_OUTPUT" \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot \
        isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog isolinux/isolinux.cat \
    -eltorito-alt-boot \
        -e /EFI/boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
    -append_partition 2 0xef ${HOME}/LIVE_BOOT/staging/EFI/boot/efiboot.img \
    "${HOME}/LIVE_BOOT/staging"

chmod -v 666 "$ISO_OUTPUT"

# 使用7z进行最大压缩
echo 使用7z进行最大压缩
apt-get install -y p7zip-full
7z a -t7z -m0=lzma2 -mx=9 "$COMPRESSED_OUTPUT" "$ISO_OUTPUT"
chmod -v 666 "$COMPRESSED_OUTPUT"

ls -lah /output