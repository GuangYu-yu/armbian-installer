#!/bin/bash
# 此 shell 脚本在 chroot 环境中执行

echo 设置主机名
echo "installer" > /etc/hostname

# 设置为非交互模式，以便 apt 不会提示用户输入
export DEBIAN_FRONTEND=noninteractive

echo 安装安全更新和 apt-utils
apt-get update
apt-get -y install apt-utils
apt-get -y upgrade

echo 设置语言环境
apt-get -y install locales fonts-wqy-microhei
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
# 添加中文支持
sed -i -e 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
# 如果上面的替换失败（可能是因为注释格式不同），则直接添加
grep -q "zh_CN.UTF-8 UTF-8" /etc/locale.gen || echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
dpkg-reconfigure --frontend=noninteractive locales
# 设置默认语言为中文
update-locale LANG=zh_CN.UTF-8

echo 安装软件包
apt-get install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv
# 检查内核是否安装成功
echo "检查内核文件是否存在..."
ls -la /boot/vmlinuz* || echo "警告：未找到内核文件！"
apt-get install -y parted openssh-server bash-completion cifs-utils curl dbus dosfstools firmware-linux-free gddrescue gdisk iputils-ping isc-dhcp-client less nfs-common ntfs-3g openssh-client open-vm-tools procps vim wimtools wget

echo 清理 apt 安装后文件
apt-get clean

echo 启用 systemd-networkd 作为网络管理器
systemctl enable systemd-networkd

echo 设置 resolv.conf 使用 systemd-resolved
rm /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config
echo "root:1234" | chpasswd
systemctl enable ssh

echo 删除 machine-id
rm /etc/machine-id

echo 列出已安装的软件包
dpkg --get-selections|tee /packages.txt
