#!/bin/bash
set -euo pipefail


########################################

# Tor config
TOR_HIDDEN_SERVICE_DIR="/var/lib/tor/shadowsocks-domain"
TOR_WAIT=10

# frp config
FRP_VERSION="0.62.1"
FRP_PORT=7000
FRP_INSTALL_DIR="/usr/local/bin"
FRP_CONF_DIR="/etc/frp"


# Shadowsocks config
SS_PORT=9951
SS_METHOD="aes-256-gcm"

# Logging
LOG_TAG="vps-setup"


########################################

log() {
  logger -t "$LOG_TAG" "$1"
  echo "[*] $1"
}

err() {
  logger -t "$LOG_TAG" "[ERROR] $1"
  echo "[!] ERROR: $1" >&2
  exit 1
}


########################################

# Basic config
log "Installing dependencies..."
apt update && apt install -y tor shadowsocks-libev jq curl || err "Package installation failed"

# frp setup
_FRP_TOKEN="$(openssl rand -hex 16)"

log "Installing frp server (frps)..."
mkdir -p "$FRP_CONF_DIR"
cd /tmp
curl -fsSL -o frp.tar.gz https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz || err "Failed to download frp"
tar -xzf frp.tar.gz
cd frp_${FRP_VERSION}_linux_amd64
install -m 755 frps "$FRP_INSTALL_DIR/frps"

log "Writing frps.ini config..."
{
  echo ""
  echo "# frps config (reverse proxy server)"
  echo "[common]"
  echo "bind_addr = 127.0.0.1"
  echo "bind_port = $FRP_PORT"
  echo "token = $_FRP_TOKEN"
} >> "$FRP_CONF_DIR/frps.ini"



log "Creating systemd service for frps..."
{
  echo ""
  echo "# systemd service for frps"
  echo "[Unit]"
  echo "Description=frp server"
  echo "After=network.target"
  echo ""
  echo "[Service]"
  echo "ExecStart=$FRP_INSTALL_DIR/frps -c $FRP_CONF_DIR/frps.ini"
  echo "Restart=on-failure"
  echo ""
  echo "[Install]"
  echo "WantedBy=multi-user.target"
} >> /etc/systemd/system/frps.service

log "Enabling and starting frps..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable frps
systemctl start frps

# shadosocks setup
log "Generating Shadowsocks password..."
_SS_PASSWORD=$(openssl rand -hex 16) || err "Password generation failed"

log "Writing Shadowsocks config using jq..."
mkdir -p /etc/shadowsocks-libev

jq -n \
  --arg server "127.0.0.1" \
  --arg password "$_SS_PASSWORD" \
  --arg method "$SS_METHOD" \
  --arg mode "tcp_and_udp" \
  --argjson server_port "$SS_PORT" \
  --argjson timeout 300 \
  '$ARGS.named' > /etc/shadowsocks-libev/config.json

log "Enabling and starting Shadowsocks..."
systemctl enable shadowsocks-libev || err "Failed to enable shadowsocks"
systemctl restart shadowsocks-libev || err "Failed to start shadowsocks"

# tor setup
log "Configuring Tor hidden service (Single Hop)..."
mkdir -p "$TOR_HIDDEN_SERVICE_DIR"

if ! grep -q "$TOR_HIDDEN_SERVICE_DIR" /etc/tor/torrc; then
  log "Updating /etc/tor/torrc with hidden service config..."

  {
    echo ""
    echo "# Shadowsocks Hidden Service (Single Hop)"
    echo "HiddenServiceDir $TOR_HIDDEN_SERVICE_DIR"
    echo "HiddenServicePort $SS_PORT 127.0.0.1:$SS_PORT"
    echo "HiddenServicePort $FRP_PORT 127.0.0.1:$FRP_PORT"
    echo "HiddenServiceSingleHopMode 1"
    echo "HiddenServiceNonAnonymousMode 1"
  } >> /etc/tor/torrc
else
  log "Hidden Service already configured in torrc"
fi

log "Enabling and starting Tor..."
systemctl enable tor || err "Failed to enable tor"
systemctl restart tor || err "Failed to start tor"

log "Waiting for .onion hostname..."
for i in $(seq 1 "$TOR_WAIT"); do
  [ -f "$TOR_HIDDEN_SERVICE_DIR/hostname" ] && break
  sleep 1
done

[ -f "$TOR_HIDDEN_SERVICE_DIR/hostname" ] || err "Failed to retrieve .onion address"

_TOR_ONION_HOSTNAME=$(cat "$TOR_HIDDEN_SERVICE_DIR/hostname")


########################################

echo
echo "Server successfully configured"
echo "----------------------------------------"
echo "Shadowsocks endpoint:    $_TOR_ONION_HOSTNAME:$SS_PORT"
echo "Shadowsocks password:    $_SS_PASSWORD"
echo "Encryption method:       $SS_METHOD"
echo "----------------------------------------"
echo "FRP .onion endpoint:     $_TOR_ONION_HOSTNAME:$FRP_PORT"
echo "FRP token:               $_FRP_TOKEN"
echo "----------------------------------------"
