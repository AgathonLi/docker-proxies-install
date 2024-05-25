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

# 创建hysteria目录
create_directory() {
    echo "创建并进入hysteria目录..."
    mkdir -p /home/hysteria && cd /home/hysteria
}

# 创建Hysteria目录
create_directory() {
    echo "创建并进入hysteria目录..."
    mkdir -p /home/hysteria && cd /home/hysteria
}

# 创建Hysteria的客户端配置信息
create_proxy_config() {
    echo "创建Hysteria配置信息..."
    cat > proxy.yaml <<EOF
    - {"name": "hysteria-IPv4","type": "hysteria2","server": "server_ipv4","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
    - {"name": "hysteria-IPv6","type": "hysteria2","server": "server_ipv6","port": server_port,"password": "server_password","sni": "server_domain","alpn": ["h3"],"up": 100,"down": 500}
    EOF

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
}

# 创建hysteria配置文件
cat > config.yaml <<EOF
listen: :443

acme:
  domains:
    - your.domain.net
  email: your@email.com
  ca: letsencrypt

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

  # 使用 sed 命令一次性修改配置文件
  sed -i '
    s/#  - name: my_socks5/  - name: my_socks5/
    s/#    type: socks5/    type: socks5/
    s/#    socks5:/    socks5:/
    s/#      addr:/      addr: '$socks5_addr'/
    s/#      port:/      port: '$socks5_port'/
    s/#      username:/      username: '$socks5_user'/
    s/#      password:/      password: '$socks5_pass'/
  ' config.yaml
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

      # 找到 - reject(geoip:cn) 行号
      reject_line=$(sed -n '/^ *- reject(geoip:cn)/=' config.yaml)

      # 在 - reject(geoip:cn) 行后插入新的分流规则
      insert_line=$((reject_line + 1))
      for i in "${ADDR[@]}"; do
        sed -i "${insert_line}i    - ${rule_prefix}($i)" config.yaml
        insert_line=$((insert_line + 1))
      done
    fi
  }

  if [ "$ip_priority" = "A" ] || [ "$ip_priority" = "a" ]; then
    # IPv4优先
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
    sed -i '/^ *- name: v4_first/{
      :a
      N
      /^\ *- name: v6_first\n *- type: direct\n *- direct:\n *- mode: 64$/!ba
      s/\(.*\)\n\([^]*\)/\2\n\1/
    }' config.yaml
  
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
