#!/bin/bash

# 检查并安装 Docker
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，开始安装..."

    # 获取系统发行版
    distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

    if [ "$distro" == "debian" ] || [ "$distro" == "ubuntu" ]; then
      echo "检测到 Debian/Ubuntu 系统，安装 Docker..."
      sudo apt-get update
      sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
      curl -fsSL https://download.docker.com/linux/$distro/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$distro $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [ "$distro" == "alpine" ]; then
      echo "检测到 Alpine 系统，安装 Docker..."
      sudo apk add --no-cache docker
      sudo rc-update add docker boot
      sudo service docker start
    else
      echo "不支持的系统: $distro，脚本退出"
      exit 1
    fi
  fi
  
  # 检查 Docker 安装是否成功
  if ! command -v docker &> /dev/null; then
    echo "Docker 安装失败，请检查安装日志"
    exit 1
  fi

  echo "Docker 已安装"
}

# 检查并安装 Docker Compose
install_docker_compose() {
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose 未安装，开始安装..."

    # 获取系统发行版和架构
    distro=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
    arch=$(uname -m)

    if [ "$arch" == "x86_64" ]; then
      compose_arch="x86_64"
    elif [ "$arch" == "aarch64" ]; then
      compose_arch="aarch64"
    else
      echo "不支持的架构: $arch，脚本退出"
      exit 1
    fi

    if [ "$distro" == "debian" ] || [ "$distro" == "ubuntu" ]; then
      echo "检测到 Debian/Ubuntu 系统，安装 Docker Compose..."
      url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$compose_arch"
      sudo curl -L $url -o /usr/local/bin/docker-compose
      if [ $? -ne 0 ]; then
        echo "下载 Docker Compose 失败，请检查网络连接或 URL"
        exit 1
      fi
      sudo chmod +x /usr/local/bin/docker-compose
    elif [ "$distro" == "alpine" ]; then
      echo "检测到 Alpine 系统，安装 Docker Compose..."
      sudo apk add --no-cache docker-compose
      if [ $? -ne 0 ]; then
        echo "安装 Docker Compose 失败，请检查安装日志"
        exit 1
      fi
    else
      echo "不支持的系统: $distro，脚本退出"
      exit 1
    fi
  fi
  
  # 检查 Docker Compose 安装是否成功
  if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose 安装失败，请检查安装日志"
    exit 1
  fi

  echo "Docker Compose 已安装"
}

install_docker

install_docker_compose
