#!/bin/bash
set -e

# ================= 基础配置 =================
SS_PORT=5555
SS_PASSWORD="1"
SS_METHOD="chacha20-ietf-poly1305"

SS_CONFIG="/etc/shadowsocks-libev/config.json"
SS_SERVICE="/etc/systemd/system/ss-auto.service"

# ================= 检查 ROOT =================
[ "$(id -u)" != "0" ] && echo "请使用 root 运行" && exit 1

# ================= 获取 IP =================
get_ip() {
    curl -s --max-time 5 ip.sb || \
    curl -s --max-time 5 checkip.amazonaws.com || \
    curl -s --max-time 5 ifconfig.me
}

# ================= 系统优化（ARM + 香港） =================
sys_optimize() {
    echo "[+] 启用 BBR + TCP Fast Open"

    cat > /etc/sysctl.d/99-ss-opt.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.ip_forward = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_mtu_probing = 1
EOF

    sysctl --system >/dev/null
}

# ================= 安装 Shadowsocks =================
install_ss() {
    echo "[+] 安装 shadowsocks-libev"

    if command -v apt &>/dev/null; then
        apt update
        apt install -y shadowsocks-libev curl iptables
    elif command -v yum &>/dev/null; then
        yum install -y epel-release
        yum install -y shadowsocks-libev curl iptables-services
    else
        echo "[-] 不支持的系统"
        exit 1
    fi
}

# ================= 配置 SS =================
config_ss() {
    echo "[+] 写入 SS 配置"
    mkdir -p /etc/shadowsocks-libev

    cat > ${SS_CONFIG} <<EOF
{
    "server":"0.0.0.0",
    "server_port":${SS_PORT},
    "password":"${SS_PASSWORD}",
    "timeout":300,
    "method":"${SS_METHOD}",
    "fast_open":true,
    "mode":"tcp_and_udp"
}
EOF
}

# ================= 防火墙 =================
open_firewall() {
    iptables -C INPUT -p tcp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp --dport ${SS_PORT} -j ACCEPT

    iptables -C INPUT -p udp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p udp --dport ${SS_PORT} -j ACCEPT
}

# ================= systemd 服务 =================
create_service() {
    echo "[+] 创建 systemd 服务"

    cat > ${SS_SERVICE} <<EOF
[Unit]
Description=Shadowsocks Server (ARM Optimized)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -c ${SS_CONFIG} -u --fast-open
Restart=always
RestartSec=2
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable ss-auto
    systemctl restart ss-auto
}

# ================= 主流程 =================
echo "====== AWS 香港 ARM Shadowsocks 极速部署 ======"

sys_optimize
command -v ss-server &>/dev/null || install_ss
config_ss
open_firewall
create_service

IP=$(get_ip)

echo
echo "====== 部署完成 ======"
echo "服务器 IP : $IP"
echo "端口      : $SS_PORT"
echo "密码      : $SS_PASSWORD"
echo "加密方式  : $SS_METHOD"
echo
echo "⚠️ 请确认 AWS 安全组已放行 TCP/UDP ${SS_PORT}"
echo "============================================"
