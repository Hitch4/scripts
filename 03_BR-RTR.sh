#!/bin/bash
# BR-RTR setup script
# Tasks: 1, 3, 6 (GRE), 7 (OSPF), 8 (NAT), 11, 14 (chrony), 15 (port forward)

IFACE_WAN="ens20"   # toward ISP
IFACE_LAN="ens21"   # toward BR-SRV
TIMEZONE="Asia/Yekaterinburg"

echo "=== [BR-RTR] Installing packages ==="
apt-get update && apt-get install -y mc iptables frr nano tzdata chrony

echo "=== [BR-RTR] Hostname ==="
hostnamectl set-hostname br-rtr.au-team.irpo

echo "=== [BR-RTR] Enable ip_forward ==="
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

echo "=== [BR-RTR] WAN interface: 172.16.2.2/28 ==="
mkdir -p /etc/net/ifaces/$IFACE_WAN
cat > /etc/net/ifaces/$IFACE_WAN/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "172.16.2.2/28" > /etc/net/ifaces/$IFACE_WAN/ipv4address
echo "default via 172.16.2.1" > /etc/net/ifaces/$IFACE_WAN/ipv4route

echo "=== [BR-RTR] LAN interface (BR-SRV): 192.168.3.1/28 ==="
mkdir -p /etc/net/ifaces/$IFACE_LAN
cat > /etc/net/ifaces/$IFACE_LAN/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "192.168.3.1/28" > /etc/net/ifaces/$IFACE_LAN/ipv4address

echo "=== [BR-RTR] GRE tunnel: 10.0.1.2/30 ==="
mkdir -p /etc/net/ifaces/gre1
cat > /etc/net/ifaces/gre1/options <<OPTS
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.2.2
TUNREMOTE=172.16.1.2
DISABLED=no
NM_CONTROLLED=no
BOOTPROTO=static
OPTS
echo "10.0.1.2/30" > /etc/net/ifaces/gre1/ipv4address

echo "=== [BR-RTR] Restart network ==="
systemctl restart network

echo "=== [BR-RTR] User net_admin ==="
useradd -m net_admin 2>/dev/null || true
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/net_admin

echo "=== [BR-RTR] OSPF via FRR ==="
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr
systemctl restart frr

vtysh <<VTYSH
configure terminal
router ospf
 passive-interface default
 network 10.0.1.0/30 area 0
 network 192.168.3.0/28 area 0
 exit
interface gre1
 ip ospf authentication-key P@ssw0rd
 ip ospf authentication
 no ip ospf passive
 exit
end
write
exit
VTYSH
systemctl restart frr

echo "=== [BR-RTR] NAT ==="
iptables -t nat -A POSTROUTING -o $IFACE_WAN -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables
systemctl enable --now iptables

echo "=== [BR-RTR] Port forward 2055 -> BR-SRV:2026 ==="
iptables -t nat -A PREROUTING -p tcp --dport 2055 -j DNAT --to-destination 192.168.3.2:2026
iptables -A FORWARD -p tcp -d 192.168.3.2 --dport 2026 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

echo "=== [BR-RTR] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [BR-RTR] Chrony client ==="
cat > /etc/chrony.conf <<CHRONY
server 172.16.2.1 iburst
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
CHRONY
systemctl restart chronyd
systemctl enable --now chronyd

echo "=== [BR-RTR] DONE ==="
echo "Check: ip -c a"
echo "Check: ping 10.0.1.1"
echo "Check: vtysh -c 'show ip ospf neighbor'"
