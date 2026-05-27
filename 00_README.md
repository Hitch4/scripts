# EXAM CHEATSHEET - PM02

## WARNING: check interface names before running each script!
## Run: ip -c a
## Change IFACE_* variables at the top of each script!
## Run as root: bash 01_ISP.sh

---

## SCRIPT ORDER

| # | Script       | Machine  | What it does                              |
|---|--------------|----------|-------------------------------------------|
| 1 | 01_ISP.sh    | ISP      | interfaces, NAT, chrony server            |
| 2 | 02_HQ-RTR.sh | HQ-RTR   | VLANs, GRE, OSPF, NAT, DHCP, portfwd     |
| 3 | 03_BR-RTR.sh | BR-RTR   | interfaces, GRE, OSPF, NAT, portfwd       |
| 4 | 04_HQ-SRV.sh | HQ-SRV   | SSH, RAID0, NFS, DNS, chrony              |
| 5 | 05_BR-SRV.sh | BR-SRV   | IP, SSH, chrony                           |
| 6 | 06_HQ-CLI.sh | HQ-CLI   | DHCP client, NFS mount, Yandex Browser    |

---

## IP ADDRESS TABLE (for report)

| Device   | Interface          | IP             | Gateway     |
|----------|--------------------|----------------|-------------|
| ISP      | ens19 (WAN)        | DHCP           | -           |
| ISP      | ens20 (->HQ-RTR)   | 172.16.1.1/28  | -           |
| ISP      | ens21 (->BR-RTR)   | 172.16.2.1/28  | -           |
| HQ-RTR   | ens20 (->ISP)      | 172.16.1.2/28  | 172.16.1.1  |
| HQ-RTR   | ens21.100 (VLAN100)| 192.168.1.1/27 | -           |
| HQ-RTR   | ens21.200 (VLAN200)| 192.168.2.1/27 | -           |
| HQ-RTR   | ens21.999 (VLAN999)| 10.10.1.1/29   | -           |
| HQ-RTR   | gre1               | 10.0.1.1/30    | -           |
| BR-RTR   | ens20 (->ISP)      | 172.16.2.2/28  | 172.16.2.1  |
| BR-RTR   | ens21 (->BR-SRV)   | 192.168.3.1/28 | -           |
| BR-RTR   | gre1               | 10.0.1.2/30    | -           |
| HQ-SRV   | ens19 (VLAN100)    | 192.168.1.2/27 | 192.168.1.1 |
| HQ-CLI   | ens19 (VLAN200)    | DHCP           | 192.168.2.1 |
| BR-SRV   | ens19              | 192.168.3.2/28 | 192.168.3.1 |

---

## PROXMOX (manual! scripts cannot do this)
- Network -> HQ-Net -> enable "Vlan aware"
- HQ-SRV: VLAN tag = 100
- HQ-CLI: VLAN tag = 200
- Disable firewall on HQ-RTR (net2), HQ-SRV, HQ-CLI

---

## USERS
| User      | Password  | Where              | Notes              |
|-----------|-----------|--------------------|--------------------|
| sshuser   | P@ssw0rd  | HQ-SRV, BR-SRV     | uid=2026, nopasswd |
| net_admin | P@ssw0rd  | HQ-RTR, BR-RTR     | nopasswd sudo      |

---

## GRE TUNNEL
| Param     | HQ-RTR     | BR-RTR     |
|-----------|------------|------------|
| TUNLOCAL  | 172.16.1.2 | 172.16.2.2 |
| TUNREMOTE | 172.16.2.2 | 172.16.1.2 |
| tunnel IP | 10.0.1.1/30| 10.0.1.2/30|

---

## DHCP (HQ-RTR -> HQ-CLI)
- subnet:  192.168.2.0/27
- range:   192.168.2.2 - 192.168.2.30
- gateway: 192.168.2.1
- dns:     192.168.1.2
- suffix:  au-team.irpo

---

## DNS hosts on HQ-SRV (/etc/dnsmasq.hosts)
172.16.1.2    hq-rtr.au-team.irpo
172.16.2.2    br-rtr.au-team.irpo
192.168.1.2   hq-srv.au-team.irpo
192.168.2.2   hq-cli.au-team.irpo
192.168.3.2   br-srv.au-team.irpo
172.16.1.1    docker.au-team.irpo
172.16.2.1    web.au-team.irpo

---

## CHECKLIST
- [ ] ip -c a                           -- all interfaces have IP
- [ ] ping 172.16.1.1 from HQ-RTR       -- ISP reachable
- [ ] ping 10.0.1.2 from HQ-RTR         -- GRE tunnel works
- [ ] vtysh -c "show ip ospf neighbor"  -- OSPF neighbors up
- [ ] ping 192.168.3.2 from HQ-RTR      -- OSPF routes work
- [ ] systemctl status dhcpd            -- DHCP running
- [ ] ssh -p 2026 sshuser@192.168.1.2   -- SSH works
- [ ] cat /proc/mdstat                  -- RAID0 active
- [ ] df -h /raid                       -- RAID mounted
- [ ] exportfs -v                       -- NFS exported
- [ ] df -h /mnt/nfs on HQ-CLI         -- NFS mounted
- [ ] nslookup hq-srv.au-team.irpo      -- DNS works
- [ ] chronyc tracking                  -- time synced
