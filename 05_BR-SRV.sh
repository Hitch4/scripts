#!/bin/bash
# BR-SRV setup script
# Tasks: 1, 3 (sshuser), 5 (SSH), 11 (timezone), 14 (chrony)

IFACE="ens19"
TIMEZONE="Asia/Yekaterinburg"

echo "=== [BR-SRV] Installing packages ==="
apt-get update && apt-get install -y chrony tzdata nano mc

echo "=== [BR-SRV] Hostname ==="
hostnamectl set-hostname br-srv.au-team.irpo

echo "=== [BR-SRV] IP address: 192.168.3.2/28 ==="
mkdir -p /etc/net/ifaces/$IFACE
cat > /etc/net/ifaces/$IFACE/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "192.168.3.2/28" > /etc/net/ifaces/$IFACE/ipv4address
echo "default via 192.168.3.1" > /etc/net/ifaces/$IFACE/ipv4route
systemctl restart network

echo "=== [BR-SRV] User sshuser (uid=2026) ==="
useradd -m -u 2026 sshuser 2>/dev/null || true
echo "sshuser:P@ssw0rd" | chpasswd
echo "sshuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sshuser

echo "=== [BR-SRV] SSH config ==="
echo "Authorized access only" > /etc/mybanner
SSHD_CONFIG="/etc/openssh/sshd_config"
sed -i 's/^#*Port .*/Port 2026/' $SSHD_CONFIG
sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 2/' $SSHD_CONFIG
sed -i 's|^#*Banner .*|Banner /etc/mybanner|' $SSHD_CONFIG
grep -q "^AllowUsers" $SSHD_CONFIG && \
    sed -i 's/^AllowUsers.*/AllowUsers\tsshuser/' $SSHD_CONFIG || \
    echo -e "AllowUsers\tsshuser" >> $SSHD_CONFIG
systemctl restart sshd

echo "=== [BR-SRV] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [BR-SRV] Chrony client ==="
cat > /etc/chrony.conf <<CHRONY
server 172.16.2.1 iburst
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
CHRONY
systemctl restart chronyd
systemctl enable --now chronyd

echo "=== [BR-SRV] DONE ==="
echo "Check: ss -tlnp | grep 2026"
echo "Check: chronyc tracking"
