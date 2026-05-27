#!/bin/bash
# HQ-RTR setup script
# Tasks: 1, 3, 4 (VLANs), 6 (GRE), 7 (OSPF), 8 (NAT), 9 (DHCP), 11, 15 (port forward)

IFACE_WAN="ens20"   # toward ISP
IFACE_LAN="ens21"   # toward HQ-SW (trunk)
TIMEZONE="Asia/Yekaterinburg"

echo "=== [HQ-RTR] Installing packages ==="
apt-get update && apt-get install -y mc iptables frr nano tzdata chrony dhcp-server

echo "=== [HQ-RTR] Hostname ==="
hostnamectl set-hostname hq-rtr.au-team.irpo

echo "=== [HQ-RTR] Enable ip_forward ==="
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

echo "=== [HQ-RTR] WAN interface: 172.16.1.2/28 ==="
mkdir -p /etc/net/ifaces/$IFACE_WAN
cat > /etc/net/ifaces/$IFACE_WAN/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "172.16.1.2/28" > /etc/net/ifaces/$IFACE_WAN/ipv4address
echo "default via 172.16.1.1" > /etc/net/ifaces/$IFACE_WAN/ipv4route

echo "=== [HQ-RTR] LAN base interface (no IP, trunk) ==="
mkdir -p /etc/net/ifaces/$IFACE_LAN
cat > /etc/net/ifaces/$IFACE_LAN/options <<OPTS
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS

echo "=== [HQ-RTR] VLAN100 (HQ-SRV): 192.168.1.1/27 ==="
mkdir -p /etc/net/ifaces/${IFACE_LAN}.100
cat > /etc/net/ifaces/${IFACE_LAN}.100/options <<OPTS
TYPE=vlan
VID=100
HOST=${IFACE_LAN}
DISABLED=no
NM_CONTROLLED=no
BOOTPROTO=static
OPTS
echo "192.168.1.1/27" > /etc/net/ifaces/${IFACE_LAN}.100/ipv4address

echo "=== [HQ-RTR] VLAN200 (HQ-CLI): 192.168.2.1/27 ==="
mkdir -p /etc/net/ifaces/${IFACE_LAN}.200
cat > /etc/net/ifaces/${IFACE_LAN}.200/options <<OPTS
TYPE=vlan
VID=200
HOST=${IFACE_LAN}
DISABLED=no
NM_CONTROLLED=no
BOOTPROTO=static
OPTS
echo "192.168.2.1/27" > /etc/net/ifaces/${IFACE_LAN}.200/ipv4address

echo "=== [HQ-RTR] VLAN999 (mgmt): 10.10.1.1/29 ==="
mkdir -p /etc/net/ifaces/${IFACE_LAN}.999
cat > /etc/net/ifaces/${IFACE_LAN}.999/options <<OPTS
TYPE=vlan
VID=999
HOST=${IFACE_LAN}
DISABLED=no
NM_CONTROLLED=no
BOOTPROTO=static
OPTS
echo "10.10.1.1/29" > /etc/net/ifaces/${IFACE_LAN}.999/ipv4address

echo "=== [HQ-RTR] GRE tunnel: 10.0.1.1/30 ==="
mkdir -p /etc/net/ifaces/gre1
cat > /etc/net/ifaces/gre1/options <<OPTS
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.1.2
TUNREMOTE=172.16.2.2
DISABLED=no
NM_CONTROLLED=no
BOOTPROTO=static
OPTS
echo "10.0.1.1/30" > /etc/net/ifaces/gre1/ipv4address

echo "=== [HQ-RTR] Restart network ==="
systemctl restart network

echo "=== [HQ-RTR] User net_admin ==="
useradd -m net_admin 2>/dev/null || true
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/net_admin

echo "=== [HQ-RTR] OSPF via FRR ==="
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr
systemctl restart frr

vtysh <<VTYSH
configure terminal
router ospf
 passive-interface default
 network 10.0.1.0/30 area 0
 network 192.168.1.0/27 area 0
 network 192.168.2.0/27 area 0
 network 10.10.1.0/29 area 0
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

echo "=== [HQ-RTR] NAT ==="
iptables -t nat -A POSTROUTING -o $IFACE_WAN -j MASQUERADE
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables
systemctl enable --now iptables

echo "=== [HQ-RTR] DHCP for HQ-CLI (VLAN200) ==="
cat > /etc/dhcp/dhcpd.conf <<DHCP
subnet 192.168.2.0 netmask 255.255.255.224 {
    range 192.168.2.2 192.168.2.30;
    option routers 192.168.2.1;
    option domain-name-servers 192.168.1.2;
    option domain-name "au-team.irpo";
    default-lease-time 600;
    max-lease-time 7200;
}
DHCP
cat > /etc/sysconfig/dhcpd <<DHCPCFG
DHCPDARGS="${IFACE_LAN}.200"
DHCPCFG
systemctl restart dhcpd
systemctl enable --now dhcpd

echo "=== [HQ-RTR] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [HQ-RTR] Port forward 2055 -> HQ-SRV:2026 ==="
iptables -t nat -A PREROUTING -p tcp --dport 2055 -j DNAT --to-destination 192.168.1.2:2026
iptables -A FORWARD -p tcp -d 192.168.1.2 --dport 2026 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
systemctl restart iptables

echo "=== [HQ-RTR] DONE ==="
echo "Check: ip -c a"
echo "Check: vtysh -c 'show ip ospf neighbor'"
echo "Check: systemctl status dhcpd"
