#!/bin/sh

# Update package list
apk update

# Install Docker and Docker Compose
apk add docker docker-compose

# Add Docker to system startup
rc-update add docker boot

# Start Docker service
service docker start

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

echo "x-ui installation complete. Access the web interface at http://[your-server-ip]:2053"
