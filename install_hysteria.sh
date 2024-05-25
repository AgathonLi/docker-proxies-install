#!/bin/bash

if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "Docker 或 Docker Compose 未安装，开始安装..."
  
  # 识别当前的 Linux 系统
  if [ -f /etc/debian_version ]; then
    echo "检测到 Debian/Ubuntu 系统，安装 Docker..."
    curl -fsSL https://get.docker.com | sudo bash
    # 检查 Docker 安装是否成功
    if ! command -v docker &> /dev/null; then
      echo "Docker 安装失败，脚本退出"
      exit 1
    fi
    # 安装 Docker Compose
    sudo apt update
    sudo apt install -y docker-compose
    # 检查 Docker Compose 安装是否成功
    if ! command -v docker-compose &> /dev/null; then
      echo "Docker Compose 安装失败，脚本退出"
      exit 1
    fi
  elif [ -f /etc/alpine-release ]; then
    echo "检测到 Alpine 系统，安装 Docker..."
    sudo apk add --no-cache docker docker-compose
    sudo rc-update add docker boot
    sudo service docker start
    # 检查 Docker 安装是否成功
    if ! command -v docker &> /dev/null; then
      echo "Docker 安装失败，脚本退出"
      exit 1
    fi
    # 检查 Docker Compose 安装是否成功
    if ! command -v docker-compose &> /dev/null; then
      echo "Docker Compose 安装失败，脚本退出"
      exit 1
    fi
  else
    echo "不支持的系统，脚本退出"
    exit 1
  fi
else
  echo "Docker 和 Docker Compose 已安装"
fi

# 创建hysteria目录
mkdir -p /home/hysteria
cd /home/hysteria

# 创建Hysteria的clash proxy配置信息
cat > proxy.yaml <<EOF
- {"name": "hysteria-IPv4","type": "hysteria2","server": "server_ipv4","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
- {"name": "hysteria-IPv6","type": "hysteria2","server": "server_ipv6","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
EOF

# 创建hysteria配置文件
cat > config.yaml <<EOF
listen: :443

acme:
  domains:
    - your.domain.net
  email: your@email.com
  ca: letsencrypt
  dir: /home/acme

#tls:
#  cert: 
#  key: 

auth:
  type: password
  password: your_password

acl:
  inline:
    - reject(geoip:cn)
    - default(all)

outbounds:
  - name: v4_first
    type: direct
    direct:
      mode: 46
  - name: v6_first
    type: direct
    direct:
      mode: 64
#  - name: my_socks5
#    type: socks5
#    socks5:
#      addr: socks5_address:socks5_port 
#      username: socks5_username 
#      password: socks5_password 

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
EOF

# 提示输入端口
while true; do
  read -p "请输入端口 (1-65535，回车则随机选择1000-60000之间的端口): " port
  if [ -z "$port" ]; then
    port=$((RANDOM % 59000 + 1000))
  fi
  if ! ss -tuln | grep -q ":$port "; then
    break
  else
    echo "端口被占用，请手动关闭后安装"
    exit 1
  fi
done

sed -i "s/:443/:$port/" config.yaml
sed -i "s/server_port/$port/" proxy.yaml

# 设置需要申请证书的域名
while true; do
  read -p "请输入需要申请证书的域名: " domain
  if echo "$domain" | grep -Eq "^[a-zA-Z0-9.-]+$"; then
    sed -i "s/your.domain.net/$domain/" config.yaml
    sed -i "s/server_domain/$domain/" proxy.yaml
    break
  else
    echo "域名格式不正确，请重新输入。"
  fi
done

# 选择证书获取方式
echo "请选择证书获取方式:"
echo "A. ACME"
echo "B. TLS"
read -p "选择 (A/B): " cert_method

if [ "$cert_method" = "B" ] || [ "$cert_method" = "b" ]; then
  # 注释acme部分
  sed -i "s/^acme:/#acme:/" config.yaml
  sed -i "s/^  domains:/#  domains:/" config.yaml
  sed -i "s/^    - your.domain.net/#    - your.domain.net/" config.yaml
  sed -i "s/^  email:/#  email:/" config.yaml
  sed -i "s/^  ca:/#  ca:/" config.yaml
  sed -i "s/^  dir:/#  dir:/" config.yaml
  
  # 取消tls部分注释
  sed -i "s/#tls:/tls:/" config.yaml
  sed -i "s/#  cert:/  cert:/" config.yaml
  sed -i "s/#  key:/  key:/" config.yaml
  
  # 设定证书路径
  while true; do
    read -p "请输入TLS证书的路径 (cert): " cert_path
    if [ -f "$cert_path" ]; then
      sed -i "s|cert:|cert: $cert_path|" config.yaml
      break
    else
      echo "证书路径不存在，请重新输入。"
    fi
  done
  
  while true; do
    read -p "请输入TLS私钥的路径 (key): " key_path
    if [ -f "$key_path" ]; then
      sed -i "s|key:|key: $key_path|" config.yaml
      break
    else
      echo "私钥路径不存在，请重新输入。"
    fi
  done
else
  # 设置申请域名的邮箱
  read -p "请输入申请证书的邮箱: " email
  sed -i "s/your@email.com/$email/" config.yaml
fi

# 生成密码
password=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 36 | head -n 1)
sed -i "s/your_password/$password/" config.yaml
sed -i "s/server_password/$password/" proxy.yaml

# 创建docker compose文件
cat > docker-compose.yaml <<EOF
services:
  hysteria:
    image: tobyxdd/hysteria
    container_name: hysteria
    restart: always
    network_mode: "host"
    volumes:
      - /home/acme:/acme
      - /home/hysteria/config.yaml:/etc/hysteria.yaml
    command: ["server", "-c", "/etc/hysteria.yaml"]
volumes:
  acme:
EOF

# 运行docker compose
docker-compose up -d

# 是否修改分流配置
read -p "是否修改分流配置（y/n）: " modify_routing
if [ "$modify_routing" = "y" ] || [ "$modify_routing" = "Y" ]; then
  echo "设置全局IPv4或IPv6优先:"
  echo "A. 全局IPv4优先"
  echo "B. 全局IPv6优先"
  read -p "选择 (A/B): " ip_priority

  if [ "$ip_priority" = "B" ] || [ "$ip_priority" = "b" ]; then
    # 检查 config.yaml 是否存在
    if [ -f "config.yaml" ]; then
      echo "找到 config.yaml 文件，正在处理..."
    
      # 使用 awk 进行处理
      awk '
      BEGIN { v6_first_found=0; v6_first="" }
      /^outbounds:/ { outbounds=1 }
      outbounds && /^  - name: v6_first$/ { v6_first_found=1 }
      v6_first_found && outbounds && !/^  - name: v6_first$/ {
        v6_first = v6_first $0 "\n";
        next
      }
      v6_first_found && outbounds && /^  - name: v4_first$/ {
        v6_first = "- name: v6_first\n    type: direct\n    direct:\n      mode: 64\n" v6_first;
        print v6_first;
        v6_first_found=0;
        v6_first=""
      }
      { print }
      ' config.yaml > config_new.yaml && mv config_new.yaml config.yaml
    
      echo "处理完成。"
    else
      echo "未找到 config.yaml 文件，脚本退出。"
      exit 1
    fi
  fi

  if [ "$ip_priority" = "A" ] || [ "$ip_priority" = "a" ]; then
    echo "选择需要修改的分流-IPv4优先模式下:"
    echo "A. IPv6分流"
    echo "B. Socks5分流"
    read -p "选择 (A/B): " routing_type

    if [ "$routing_type" = "A" ] || [ "$routing_type" = "a" ]; then
      # 输入需要分流的域名或数据集
      read -p "输入需要分流的域名或数据集，使用GeoIP/GeoSite，用逗号分隔: " domains
      IFS=',' read -ra ADDR <<< "$domains"
      for i in "${ADDR[@]}"; do
        echo "    - v6_first($i)" >> config.yaml
      done
    elif [ "$routing_type" = "B" ] || [ "$routing_type" = "b" ]; then
      # 配置Socks5分流
      sed -i "s/#  - name: my_socks5/  - name: my_socks5/" config.yaml
      sed -i "s/#    type: socks5/    type: socks5/" config.yaml
      sed -i "s/#    socks5:/    socks5:/" config.yaml
      sed -i "s/#      addr:/      addr:/" config.yaml
      sed -i "s/#      username:/      username:/" config.yaml
      sed -i "s/#      password:/      password:/" config.yaml

      read -p "请输入Socks5分流的地址: " socks5_addr
      read -p "请输入Socks5分流的端口: " socks5_port
      read -p "请输入Socks5分流的用户名: " socks5_user
      read -p "请输入Socks5分流的密码: " socks5_pass

      sed -i "s/socks5_address/$socks5_addr/" config.yaml
      sed -i "s/socks5_port/$socks5_port/" config.yaml
      sed -i "s/socks5_username/$socks5_user/" config.yaml
      sed -i "s/socks5_password/$socks5_pass/" config.yaml

      # 输入需要分流的域名或数据集
      read -p "输入需要分流的域名或数据集，使用GeoIP/GeoSite，用逗号分隔: " domains
      IFS=',' read -ra ADDR <<< "$domains"
      for i in "${ADDR[@]}"; do
        echo "    - my_socks5($i)" >> config.yaml
      done
    fi
  else
    echo "选择需要修改的分流-IPv6优先模式下:"
    echo "A. IPv4分流"
    echo "B. Socks5分流"
    read -p "选择 (A/B): " routing_type

    if [ "$routing_type" = "A" ] || [ "$routing_type" = "a" ]; then
      # 输入需要分流的域名或数据集
      read -p "输入需要分流的域名或数据集，使用GeoIP/GeoSite，用逗号分隔: " domains
      IFS=',' read -ra ADDR <<< "$domains"
      for i in "${ADDR[@]}"; do
        echo "    - v4_first($i)" >> config.yaml
      done
    elif [ "$routing_type" = "B" ] || [ "$routing_type" = "b" ]; then
      # 配置Socks5分流
      sed -i "s/#  - name: my_socks5/  - name: my_socks5/" config.yaml
      sed -i "s/#    type: socks5/    type: socks5/" config.yaml
      sed -i "s/#    socks5:/    socks5:/" config.yaml
      sed -i "s/#      addr:/      addr:/" config.yaml
      sed -i "s/#      username:/      username:/" config.yaml
      sed -i "s/#      password:/      password:/" config.yaml

      read -p "请输入Socks5分流的地址: " socks5_addr
      read -p "请输入Socks5分流的端口: " socks5_port
      read -p "请输入Socks5分流的用户名: " socks5_user
      read -p "请输入Socks5分流的密码: " socks5_pass

      sed -i "s/socks5_address/$socks5_addr/" config.yaml
      sed -i "s/socks5_port/$socks5_port/" config.yaml
      sed -i "s/socks5_username/$socks5_user/" config.yaml
      sed -i "s/socks5_password/$socks5_pass/" config.yaml

      # 输入需要分流的域名或数据集
      read -p "输入需要分流的域名或数据集，使用GeoIP/GeoSite，用逗号分隔: " domains
      IFS=',' read -ra ADDR <<< "$domains"
      for i in "${ADDR[@]}"; do
        echo "    - my_socks5($i)" >> config.yaml
      done
    fi
  fi
fi

# 重启容器使配置生效
docker restart hysteria

# 输出客户端配置
echo "客户端配置如下:"
cat proxy.yaml
