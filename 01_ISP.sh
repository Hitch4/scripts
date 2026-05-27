#!/bin/bash
# ISP setup script
# Tasks: 2 (interfaces, NAT), 14 (chrony server), hostname, timezone

IFACE_WAN="ens19"   # WAN interface (DHCP from provider)
IFACE_HQ="ens20"    # interface toward HQ-RTR
IFACE_BR="ens21"    # interface toward BR-RTR
TIMEZONE="Asia/Yekaterinburg"

echo "=== [ISP] Installing packages ==="
apt-get update && apt-get install -y mc iptables tzdata chrony

echo "=== [ISP] Hostname ==="
hostnamectl set-hostname isp.au-team.irpo

echo "=== [ISP] Enable ip_forward ==="
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

echo "=== [ISP] Interface toward HQ-RTR: 172.16.1.1/28 ==="
mkdir -p /etc/net/ifaces/$IFACE_HQ
cat > /etc/net/ifaces/$IFACE_HQ/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "172.16.1.1/28" > /etc/net/ifaces/$IFACE_HQ/ipv4address

echo "=== [ISP] Interface toward BR-RTR: 172.16.2.1/28 ==="
mkdir -p /etc/net/ifaces/$IFACE_BR
cat > /etc/net/ifaces/$IFACE_BR/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "172.16.2.1/28" > /etc/net/ifaces/$IFACE_BR/ipv4address

echo "=== [ISP] Restart network ==="
systemctl restart network

echo "=== [ISP] NAT via $IFACE_WAN ==="
iptables -t nat -A POSTROUTING -o $IFACE_WAN -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables
systemctl enable --now iptables

echo "=== [ISP] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [ISP] Chrony server (stratum 5) ==="
cat > /etc/chrony.conf <<CHRONY
server 77.88.8.7 iburst
server 77.88.8.3 iburst
local stratum 5
allow 0.0.0.0/0
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
CHRONY
systemctl restart chronyd
systemctl enable --now chronyd

echo "=== [ISP] DONE ==="
echo "Check: ip -c a"
echo "Check: iptables -t nat -L -n"
echo "Check: chronyc tracking"
