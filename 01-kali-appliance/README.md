# 01: Kali Testing Appliance

Lab work. Built, networked, hardened, and documented a Kali Linux VM in VirtualBox, modeled on how a testing appliance gets shipped into a client environment.

## Build

- Image: official Kali VirtualBox build (2026.3, amd64) from kali.org
- Integrity: SHA256 verified against the published checksum list. Caveat: the checksum file is hosted alongside the image, so it catches corruption, not a compromised mirror.
- Imported the `.vbox`, changed the default password, then `apt update && apt full-upgrade`
- Snapshots taken at each stable point: `clean-updated`, `clean-updated-noipv6`, `ssh-hardened-pre-ufw`, `project1-complete`

## Network modes

All four modes were configured and tested on the same VM. Each row shows what Kali received and whether the host could reach it.

| Mode | Kali address | Gateway | Host can reach Kali | Fits when |
|---|---|---|---|---|
| NAT | 10.0.2.15/24 (DHCP) | 10.0.2.2 (VirtualBox virtual router) | No, needs port forwarding | The appliance only needs outbound internet and should be isolated from the LAN |
| Bridged | 192.168.1.247/24 (DHCP) | 192.168.1.1 | Yes | The appliance sits on the client LAN as a peer device and must scan or be reached by internal hosts |
| NAT Network (`labnet`) | 192.168.50.3/24 (DHCP) | 192.168.50.1 | No, host has no route into the subnet | Several VMs need to talk to each other with outbound access, kept off the home LAN. Used in project 2 |
| Static (on Bridged) | 192.168.1.250/24 | 192.168.1.1 | Yes | The client has no DHCP or reserves fixed addresses for appliances |

Static IP detail: `nmcli connection modify` with `ipv4.method manual`. The route showed `proto static` and the address showed `valid_lft forever`, versus `proto dhcp` and a lease timer in DHCP mode. Reverted with `ipv4.method auto` and clearing the manual fields.

## Hardening

| Control | Setting | Verified by |
|---|---|---|
| SSH auth | Dedicated ed25519 key, `PasswordAuthentication no`, `KbdInteractiveAuthentication no` | Key-only login from host with no password prompt |
| Root login | `PermitRootLogin no` | Config drop-in |
| Address family | `AddressFamily inet` (IPv4 only) | `ss -tulpn` shows no IPv6 listeners |
| IPv6 | Disabled via `nmcli` | `ss -tulpn` |
| Firewall | `ufw`: default deny incoming, allow outgoing, allow 22/tcp | `ufw status verbose` |

SSH settings live in a drop-in, `/etc/ssh/sshd_config.d/10-lab-hardening.conf`, so the stock `sshd_config` stays untouched and the change is easy to audit or revert.

### Listening services after hardening

```
tcp  LISTEN  0.0.0.0:22  sshd
```

sshd on 22/tcp over IPv4 is the only listener. No UDP, no IPv6 sockets.

### Firewall verification (from the host)

| Test | Result |
|---|---|
| `Test-NetConnection <kali-ip> -Port 22` | `TcpTestSucceeded : True` |
| `Test-NetConnection <kali-ip> -Port 8080` | `TcpTestSucceeded : False` (hangs, because ufw drops rather than rejects) |
| Ping | Succeeds. ufw's default rules answer ICMP echo. |

Note: `ufw allow 22/tcp` also adds a `22/tcp (v6)` rule. It never matches anything because IPv6 is disabled and sshd is bound to IPv4 only.

## Connectivity check script

`scripts/conncheck.sh` checks whether the appliance has a working path out.

```
./conncheck.sh [-p] [-t seconds] [-H dns_host]
```

| Flag | Meaning | Default |
|---|---|---|
| `-p` | Also report the public IP | off |
| `-t` | Timeout in seconds for every check | 3 |
| `-H` | Hostname used for the DNS test | example.com |

Checks, in order: default gateway reachable (ping), DNS resolves, outbound TCP on 53, 80, and 443 to 1.1.1.1. TCP tests use an IP so DNS problems never mask a TCP result. Every check has a timeout. Exit code is 0 when everything passes, 1 when any check fails, 2 on bad usage.

Sample output, all passing (public IP is a documentation address):

```
$ ./conncheck.sh -p
PASS  default gateway 192.168.1.1 reachable
PASS  DNS resolves example.com
PASS  outbound TCP 53 to 1.1.1.1
PASS  outbound TCP 80 to 1.1.1.1
PASS  outbound TCP 443 to 1.1.1.1
PASS  public IP 203.0.113.10
$ echo $?
0
```

Sample output, DNS failure:

```
$ ./conncheck.sh -H nonexistent.invalid
PASS  default gateway 192.168.1.1 reachable
FAIL  DNS resolves nonexistent.invalid
PASS  outbound TCP 53 to 1.1.1.1
PASS  outbound TCP 80 to 1.1.1.1
PASS  outbound TCP 443 to 1.1.1.1
$ echo $?
1
```

Shell scripts are pinned to LF line endings in `.gitattributes` (`*.sh text eol=lf`).

## Export

Exported the finished VM as an OVA for portability. The file is not committed (`*.ova` is in `.gitignore`) and is written outside the repo.

```
VBoxManage export "<vm-name>" --output "<path>\kali-lab-appliance.ova" --ovf20
```

Resulting file size: 10.39 GB. A final snapshot (`project1-complete`) was taken first as a restore point.

Before sharing an exported appliance with anyone, treat it as containing secrets: it carries the account password, the authorized SSH key, and the SSH host keys. Change or remove those, and regenerate host keys, before handing it off.

## Troubleshooting

Each failure below was caused on purpose, observed with `conncheck.sh`, and fixed. The pattern of which checks fail tells you which layer is broken.

| Symptom | Likely cause | Fix |
|---|---|---|
| All five checks FAIL, gateway line reads "none configured", exit 1 | Interface is down. The kernel drops the default route with it. | `sudo ip link set eth0 up`, wait a few seconds for DHCP, rerun the check |
| Gateway and all TCP checks PASS, only DNS FAILS. `ping 1.1.1.1` works, `ping example.com` returns "Temporary failure in name resolution" | Bad or missing nameserver. In the test, `/etc/resolv.conf` held an unreachable server. | Clear the override: `nmcli connection modify "<profile>" ipv4.dns "" ipv4.ignore-auto-dns no`, then `nmcli connection up "<profile>"`, and confirm `resolv.conf` shows the router |
| Gateway line reads "none configured", DNS PASSES, all TCP checks FAIL. `ping <router>` works, `ping 1.1.1.1` returns "Network is unreachable" | Default route is missing. DNS still passes because the resolver is the router, on the local subnet. | Stopgap: `ip route add default via <gw> dev eth0`. Real fix: `nmcli connection up "<profile>"`, then confirm `proto dhcp` on the default route |
| `conncheck.sh` passes inside the VM, but the host cannot reach it. Old address returns `DestinationHostUnreachable`, new address times out | Adapter attached to the wrong mode (NAT Network instead of Bridged). The VM is healthy but on a subnet the host has no route into. | Power off the VM, `VBoxManage modifyvm <vm> --nic1 bridged --bridgeadapter1 "<host adapter>"`, verify with `showvminfo`, boot, confirm the expected subnet |
| `file conncheck.sh` reports "with CRLF line terminators" after copying from Windows. The usual failure is `bad interpreter` or stray `^M` errors | Script saved with Windows line endings before `.gitattributes` existed. scp copies bytes unchanged. | Convert the repo copy to LF, recopy, confirm `file` no longer mentions CRLF. `*.sh text eol=lf` in `.gitattributes` prevents it for later files |

Diagnostic notes: when testing from the host against a VM, confirm the VM is running first (`VBoxManage list runningvms`). A powered-off VM produces the same `DestinationHostUnreachable` as a misconfigured adapter.
