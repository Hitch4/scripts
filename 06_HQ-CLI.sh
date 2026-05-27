#!/bin/bash
# HQ-CLI setup script
# Tasks: 1, 9 (DHCP client), 11 (timezone), 13 (NFS automount), 16 (Yandex Browser)

IFACE="ens19"
TIMEZONE="Asia/Yekaterinburg"

echo "=== [HQ-CLI] Hostname ==="
hostnamectl set-hostname hq-cli.au-team.irpo

echo "=== [HQ-CLI] DHCP client ==="
mkdir -p /etc/net/ifaces/$IFACE
cat > /etc/net/ifaces/$IFACE/options <<OPTS
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
systemctl restart network
echo "Got IP:"
ip -c a show $IFACE

echo "=== [HQ-CLI] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [HQ-CLI] NFS automount ==="
apt-get update && apt-get install -y nfs-utils tzdata
mkdir -p /mnt/nfs
grep -q "/mnt/nfs" /etc/fstab || \
    echo "192.168.1.2:/raid/nfs  /mnt/nfs  nfs  defaults,_netdev  0  0" >> /etc/fstab
mount -a
df -h /mnt/nfs 2>/dev/null || echo "NFS mount failed - check HQ-SRV connectivity"

echo "=== [HQ-CLI] Yandex Browser ==="
cd /tmp
wget -q "https://browser.yandex.ru/download/linux?os=rpm" -O yandex-browser.rpm
rpm -ivh yandex-browser.rpm 2>/dev/null || \
    echo "Install manually: rpm -ivh /tmp/yandex-browser.rpm"

echo "=== [HQ-CLI] DONE ==="
echo "Check: ip -c a"
echo "Check: ip route"
echo "Check: nslookup hq-srv.au-team.irpo"
echo "Check: df -h /mnt/nfs"
