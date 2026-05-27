#!/bin/bash
# HQ-SRV setup script
# Tasks: 1, 3 (sshuser), 5 (SSH), 10 (DNS), 11, 12 (RAID0), 13 (NFS), 14 (chrony)

IFACE="ens19"
TIMEZONE="Asia/Yekaterinburg"

echo "=== [HQ-SRV] Installing packages ==="
apt-get update && apt-get install -y mdadm nfs-server dnsmasq chrony tzdata nano mc

echo "=== [HQ-SRV] Hostname ==="
hostnamectl set-hostname hq-srv.au-team.irpo

echo "=== [HQ-SRV] IP address: 192.168.1.2/27 (VLAN100) ==="
mkdir -p /etc/net/ifaces/$IFACE
cat > /etc/net/ifaces/$IFACE/options <<OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
echo "192.168.1.2/27" > /etc/net/ifaces/$IFACE/ipv4address
echo "default via 192.168.1.1" > /etc/net/ifaces/$IFACE/ipv4route
systemctl restart network

echo "=== [HQ-SRV] User sshuser (uid=2026) ==="
useradd -m -u 2026 sshuser 2>/dev/null || true
echo "sshuser:P@ssw0rd" | chpasswd
echo "sshuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sshuser

echo "=== [HQ-SRV] SSH config ==="
echo "Authorized access only" > /etc/mybanner
SSHD_CONFIG="/etc/openssh/sshd_config"
sed -i 's/^#*Port .*/Port 2026/' $SSHD_CONFIG
sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 2/' $SSHD_CONFIG
sed -i 's|^#*Banner .*|Banner /etc/mybanner|' $SSHD_CONFIG
grep -q "^AllowUsers" $SSHD_CONFIG && \
    sed -i 's/^AllowUsers.*/AllowUsers\tsshuser/' $SSHD_CONFIG || \
    echo -e "AllowUsers\tsshuser" >> $SSHD_CONFIG
systemctl restart sshd

echo "=== [HQ-SRV] Timezone ==="
timedatectl set-timezone $TIMEZONE

echo "=== [HQ-SRV] RAID0 setup ==="
echo "Available disks:"
lsblk
echo ""
read -p "Disk 1 [sdb]: " DISK1
read -p "Disk 2 [sdc]: " DISK2
DISK1=${DISK1:-sdb}
DISK2=${DISK2:-sdc}
mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/$DISK1 /dev/$DISK2 --force
mdadm --detail --scan >> /etc/mdadm.conf
mkfs.ext4 /dev/md0
mkdir -p /raid
UUID=$(blkid /dev/md0 | awk '{print $2}' | tr -d '"')
grep -q "/raid" /etc/fstab || echo "$UUID  /raid  ext4  defaults  0  0" >> /etc/fstab
mount -a
echo "RAID mounted: $(df -h /raid)"

echo "=== [HQ-SRV] NFS server ==="
mkdir -p /raid/nfs
chmod 777 /raid/nfs
echo "/raid/nfs  192.168.2.0/27(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports
exportfs -ra
systemctl restart nfs-server
systemctl enable --now nfs-server

echo "=== [HQ-SRV] DNS via dnsmasq ==="
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/au-team.conf <<DNS
domain=au-team.irpo
local=/au-team.irpo/
server=77.88.8.7
server=77.88.8.3
no-hosts
addn-hosts=/etc/dnsmasq.hosts
listen-address=127.0.0.1,192.168.1.2
DNS

cat > /etc/dnsmasq.hosts <<HOSTS
172.16.1.2    hq-rtr.au-team.irpo
172.16.2.2    br-rtr.au-team.irpo
192.168.1.2   hq-srv.au-team.irpo
192.168.2.2   hq-cli.au-team.irpo
192.168.3.2   br-srv.au-team.irpo
172.16.1.1    docker.au-team.irpo
172.16.2.1    web.au-team.irpo
HOSTS

dnsmasq --test 2>&1
systemctl restart dnsmasq
systemctl enable --now dnsmasq

echo "=== [HQ-SRV] Chrony client ==="
cat > /etc/chrony.conf <<CHRONY
server 172.16.1.1 iburst
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
CHRONY
systemctl restart chronyd
systemctl enable --now chronyd

echo "=== [HQ-SRV] DONE ==="
echo "Check: ss -tlnp | grep 2026"
echo "Check: exportfs -v"
echo "Check: cat /proc/mdstat"
echo "Check: dnsmasq --test"
