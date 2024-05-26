#!/bin/bash

# 检查并安装 Docker
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，开始安装..."

    # 获取系统发行版
    distro=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')

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

# 创建Hysteria目录
echo "创建并进入hysteria目录..."
mkdir -p /home/hysteria && cd /home/hysteria

# 创建Hysteria的客户端配置信息
echo "创建Hysteria配置信息..."
cat > proxy.yaml <<EOF
  - {"name": "hysteria-IPv4","type": "hysteria2","server": "server_ipv4","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
  - {"name": "hysteria-IPv6","type": "hysteria2","server": "server_ipv6","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
EOF

if [ ! -f "proxy.yaml" ]; then
    echo "错误: proxy.yaml 文件不存在！"
    exit 1
fi

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
    exit 1
fi
    
# 替换 proxy.yaml 中的服务器地址
sed -i "s/server_ipv4/$ipv4_address/" proxy.yaml
sed -i "s/server_ipv6/$ipv6_address/" proxy.yaml

# 创建hysteria配置文件
cat > config.yaml <<EOF
listen: :443

acme:
  domains:
    - your.domain.net
  email: your@email.com

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
  read -p "请输入端口 (1-65535，回车则随机选择10000-59000之间的端口): " port
  if [ -z "$port" ]; then
    port=$((RANDOM % 59000 + 10000))
  fi
  if ! nc -z -w 1 localhost "$port" &> /dev/null; then
    break
  else
    echo "端口被占用，请手动关闭后安装"
    exit 1
  fi
done

sed -i "s/:443/:$port/" config.yaml
sed -i "s/server_port/$port/" proxy.yaml

# 设置需要申请证书的域名
max_retries=3
retries=0

while [ $retries -lt $max_retries ]; do
  read -p "请输入需要申请证书的域名: " domain
  if echo "$domain" | grep -Eq "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$"; then
    sed -i "s/your.domain.net/$domain/" config.yaml
    sed -i "s/server_domain/$domain/" proxy.yaml

    echo "域名设置成功！"
    break
  else
    echo "域名格式不正确，请重新输入。"
    retries=$((retries+1))
  fi
done

if [ $retries -eq $max_retries ]; then
  echo "错误：超过最大尝试次数，请检查域名格式。"
  exit 1
fi

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

# 设定伪装的域名
read -p "请输入需要伪装的域名: " masquerade_domain
sed -i "s/news.ycombinator.com/$masquerade_domain/" config.yaml

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

# 配置 Socks5 分流
configure_socks5() {
  # 校验 Socks5 地址和端口
  if ! echo "$socks5_addr" | grep -Eq "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$" || ! echo "$socks5_port" | grep -Eq "^[1-9][0-9]*$" ; then
    echo "Socks5 地址或端口格式错误！"
    exit 1
  fi

  # 使用 sed 命令修改配置文件
  sed -i 's/#  - name: my_socks5/  - name: my_socks5/' config.yaml
  sed -i 's/#    type: socks5/    type: socks5/' config.yaml
  sed -i 's/#    socks5:/    socks5:/' config.yaml
  sed -i 's/#      addr:/      addr:/' config.yaml
  sed -i 's/socks5_address:socks5_port/'$socks5_addr':'$socks5_port'/' config.yaml
  sed -i 's/#      username: socks5_username/      username: '$socks5_user'/' config.yaml
  sed -i 's/#      password: socks5_password/      password: '$socks5_pass'/' config.yaml
}

# 修改分流配置
read -p "是否修改分流配置（y/n）: " modify_routing
if [ "$modify_routing" = "y" ] || [ "$modify_routing" = "Y" ]; then
  echo "设置全局IPv4或IPv6优先:"
  echo "A. 全局IPv4优先"
  echo "B. 全局IPv6优先"
  read -p "选择 (A/B): " ip_priority

  # 提取公共代码块到函数
  add_routing_rules() {
    local rule_prefix=$1
    read -p "是否修改${rule_prefix}分流规则 (Y/N): " modify_rule
    if [[ "$modify_rule" == "y" || "$modify_rule" == "Y" ]]; then
      read -p "输入需要分流的域名或数据集，使用GeoIP/GeoSite，用逗号分隔: " domains
      IFS=',' read -ra ADDR <<< "$domains"

      # 设置缩进为4个空格
      indent="    " 

      # 读取文件内容到变量
      mapfile -t content < config.yaml

      # 逐行处理
      new_content=()
      for line in "${content[@]}"; do
        new_content+=("$line")
        # 使用 grep 命令判断是否包含 "- reject(geoip:cn)"
        if echo "$line" | grep -qE "^ *- reject\(geoip:cn\)$"; then
          for i in "${ADDR[@]}"; do
            new_content+=("${indent}- ${rule_prefix}(${i})")
          done
        fi
      done

      # 将修改后的内容写入文件
      printf "%s\n" "${new_content[@]}" > config.yaml
    fi
  }

  if [ "$ip_priority" = "A" ] || [ "$ip_priority" = "a" ]; then
    # IPv4优先
    sed -i 's/\bdefault\b/v4_first/g' config.yaml
    
    echo "IPv6分流"
    add_routing_rules "v6_first"

    read -p "是否修改Socks5分流规则 (Y/N): " modify_socks5
    if [[ "$modify_socks5" == "y" || "$modify_socks5" == "Y" ]]; then
      read -p "请输入Socks5分流的地址: " socks5_addr
      read -p "请输入Socks5分流的端口: " socks5_port
      read -p "请输入Socks5分流的用户名: " socks5_user
      read -p "请输入Socks5分流的密码: " socks5_pass
      configure_socks5
      add_routing_rules "my_socks5"
    fi
  
  elif [ "$ip_priority" = "B" ] || [ "$ip_priority" = "b" ]; then
    # IPv6优先
    sed -i 's/\bdefault\b/v6_first/g' config.yaml
  
    echo "IPv4分流"
    add_routing_rules "v4_first"

    read -p "是否修改Socks5分流规则 (Y/N): " modify_socks5
    if [[ "$modify_socks5" == "y" || "$modify_socks5" == "Y" ]]; then
      read -p "请输入Socks5分流的地址: " socks5_addr
      read -p "请输入Socks5分流的端口: " socks5_port
      read -p "请输入Socks5分流的用户名: " socks5_user
      read -p "请输入Socks5分流的密码: " socks5_pass
      configure_socks5
      add_routing_rules "my_socks5"
    fi

  else
    echo "无效的选择."
    exit 1
  fi
fi

# 重启容器使配置生效
docker restart hysteria

# 输出客户端配置
echo "客户端配置如下:"
cat proxy.yaml
