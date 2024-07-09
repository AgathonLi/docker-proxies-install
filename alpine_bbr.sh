#!/bin/sh

# 更新系统
echo "Updating the system..."
sudo apk update && sudo apk upgrade

# 配置 BBR
echo "Configuring BBR..."
sudo sh -c 'echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf'
sudo sh -c 'echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf'

# 应用更改
echo "Applying changes..."
sudo sysctl -p

# 验证 BBR 是否启用
echo "Verifying BBR..."
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr

echo "BBR has been configured."
