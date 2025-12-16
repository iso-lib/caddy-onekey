#!/bin/bash

# Caddy 二进制文件安装脚本 (支持 systemctl 管理)
# 使用方法: bash install_caddy.sh

set -e

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 sudo 运行此脚本"
    exit 1
fi

echo "=========================================="
echo "开始安装 Caddy..."
echo "=========================================="

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        CADDY_ARCH="amd64"
        ;;
    aarch64|arm64)
        CADDY_ARCH="arm64"
        ;;
    armv7l)
        CADDY_ARCH="armv7"
        ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac

echo "检测到系统架构: $ARCH (Caddy架构: $CADDY_ARCH)"

# 1. 下载 Caddy 二进制文件
echo ""
echo "步骤 1/9: 下载 Caddy 二进制文件..."
cd /tmp
curl -L -o caddy.tar.gz "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}"

# 2. 解压并安装
echo "步骤 2/9: 解压并安装到 /usr/bin/..."
tar -xzf caddy.tar.gz caddy
chmod +x caddy
mv caddy /usr/bin/
rm -f caddy.tar.gz

# 验证安装
/usr/bin/caddy version

# 3. 创建 Caddy 用户和组
echo "步骤 3/9: 创建 Caddy 用户和组..."
if ! getent group caddy > /dev/null 2>&1; then
    groupadd --system caddy
    echo "已创建 caddy 组"
else
    echo "caddy 组已存在"
fi

if ! id -u caddy > /dev/null 2>&1; then
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy
    echo "已创建 caddy 用户"
else
    echo "caddy 用户已存在"
fi

# 4. 创建必要的目录
echo "步骤 4/9: 创建配置和数据目录..."
mkdir -p /etc/caddy
mkdir -p /var/lib/caddy
mkdir -p /var/log/caddy

# 5. 创建默认 Caddyfile
echo "步骤 5/9: 创建默认配置文件..."
if [ ! -f /etc/caddy/Caddyfile ]; then
    cat > /etc/caddy/Caddyfile <<'EOF'
# Caddy 默认配置文件
# 文档: https://caddyserver.com/docs/caddyfile

# 监听 80 端口，返回欢迎信息
:80 {
    respond "Hello from Caddy! 🎉 Edit /etc/caddy/Caddyfile to configure."
}

# 配置示例：静态文件服务器
# example.com {
#     root * /var/www/html
#     file_server
# }

# 配置示例：反向代理
# api.example.com {
#     reverse_proxy localhost:8080
# }
EOF
    echo "已创建默认 Caddyfile"
else
    echo "Caddyfile 已存在，跳过创建"
fi

# 6. 设置权限
echo "步骤 6/9: 设置文件权限..."
chown -R caddy:caddy /etc/caddy
chown -R caddy:caddy /var/lib/caddy
chown -R caddy:caddy /var/log/caddy
chown root:root /usr/bin/caddy

# 7. 给 Caddy 绑定低端口的能力
echo "步骤 7/9: 配置 Caddy 端口绑定权限..."
if command -v setcap > /dev/null 2>&1; then
    setcap 'cap_net_bind_service=+ep' /usr/bin/caddy
    echo "已授予 Caddy 绑定低端口权限"
else
    echo "警告: setcap 命令不可用，可能需要手动安装 libcap2-bin"
fi

# 8. 创建 systemd 服务文件
echo "步骤 8/9: 创建 systemd 服务..."
cat > /etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy Web Server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo "已创建 systemd 服务文件"

# 9. 重载 systemd 并启用服务
echo "步骤 9/9: 配置并启动服务..."
systemctl daemon-reload
systemctl enable caddy
systemctl start caddy

# 等待服务启动
sleep 2

# 检查服务状态
if systemctl is-active --quiet caddy; then
    echo ""
    echo "=========================================="
    echo "✅ Caddy 安装成功！"
    echo "=========================================="
    echo ""
    echo "服务状态:"
    systemctl status caddy --no-pager -l
    echo ""
    echo "常用命令:"
    echo "  启动服务: sudo systemctl start caddy"
    echo "  停止服务: sudo systemctl stop caddy"
    echo "  重启服务: sudo systemctl restart caddy"
    echo "  重载配置: sudo systemctl reload caddy"
    echo "  查看状态: sudo systemctl status caddy"
    echo "  查看日志: sudo journalctl -u caddy -f"
    echo ""
    echo "配置文件: /etc/caddy/Caddyfile"
    echo "数据目录: /var/lib/caddy"
    echo ""
    echo "测试访问: curl http://localhost"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "❌ 服务启动失败，请检查日志:"
    echo "sudo journalctl -u caddy -n 50"
    echo "=========================================="
    exit 1
fi
