#!/bin/bash

# 检查并安装 Docker 和 Docker Compose
install_docker() {
  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo "Docker 或 Docker Compose 未安装，开始安装..."

    # 获取系统发行版
    distro=$(cat /etc/os-release | grep ^ID= | cut -d= -f2 | tr -d '"')

    if [ "$distro" == "debian" ] || [ "$distro" == "ubuntu" ]; then
      echo "检测到 Debian/Ubuntu 系统，安装 Docker..."
      curl -fsSL https://get.docker.com | sudo bash -s docker
      sudo apt install -y docker-compose
    elif [ "$distro" == "alpine" ]; then
      echo "检测到 Alpine 系统，安装 Docker..."
      sudo apk add --no-cache docker docker-compose
      sudo rc-update add docker boot
      sudo service docker start
    else
      echo "不支持的系统: $distro，脚本退出"
      exit 1
    fi
  fi
  # 检查 Docker 和 Docker Compose 安装是否成功
  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    echo "Docker 或 Docker Compose 安装失败，请检查安装日志"
    exit 1
  fi

  echo "Docker 和 Docker Compose 已安装"
}

# Create x-ui directory
mkdir -p /home/x-ui/db /home/x-ui/cert

# Create docker-compose.yaml file
cat << EOF > /home/x-ui/docker-compose.yaml
services:
  3x-ui:
    stdin_open: true
    tty: true
    environment:
      - XRAY_VMESS_AEAD_FORCED=false
    volumes:
      - /home/x-ui/db:/etc/x-ui/
      - /home/x-ui/cert:/root/cert/
      - /home/acme:/acme/
    network_mode: host
    restart: unless-stopped
    container_name: 3x-ui
    image: ghcr.io/mhsanaei/3x-ui:latest
EOF

# Navigate to x-ui directory
cd /home/x-ui

# Run docker-compose
docker-compose up -d

# 生成x-ui访问地址
generate_access_address() {
    # 自动检测服务器的IPv4地址和IPv6地址,最多重试三次
    echo "自动检测服务器的IPv4地址和IPv6地址..."
    retry_times=3
    for i in $(seq $retry_times); do
        ipv4_address=$(curl -s http://ipv4.icanhazip.com)
        if [ $? -eq 0 ]; then
            break
        fi
        echo "获取 IPv4 地址失败, 进行第 ${i} 次重试..."
        sleep 1
    done

    if [ $i -eq $retry_times ]; then
        echo "获取 IPv4 地址失败, 超过最大重试次数" >&2
        ipv4_address=""
        exit 1
    fi

    for i in $(seq $retry_times); do
        ipv6_address=$(curl -s http://ipv6.icanhazip.com)
        if [ $? -eq 0 ]; then
            break
        fi
        echo "获取 IPv6 地址失败, 进行第 ${i} 次重试..."
        sleep 1
    done

    if [ $i -eq $retry_times ]; then
        echo "获取 IPv6 地址失败, 超过最大重试次数" >&2
        ipv6_address=""
        exit 1
    fi

    # 只输出有效的地址
    if [ -n "$ipv4_address" ]; then
        echo "x-ui安装完成，IPv4访问地址：http://$ipv4_address:2053"
    fi
    if [ -n "$ipv6_address" ]; then
        echo "x-ui安装完成，IPv6访问地址：http://[$ipv6_address]:2053"
    fi
    
    # 如果都没有获取到地址
    if [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ]; then
        echo "获取IP地址失败，请检查网络连接"
    fi
}

generate_access_address
