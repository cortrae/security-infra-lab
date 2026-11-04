\# 01: Kali Testing Appliance



Lab work. Built, networked, hardened, and documented a Kali Linux VM in VirtualBox, modeled on how a testing appliance gets shipped into a client environment.



\## Build



\- Image: official Kali VirtualBox build (2026.3, amd64) from kali.org

\- Integrity: SHA256 verified against the published checksum list. Caveat: the checksum file is hosted alongside the image, so it catches corruption, not a compromised mirror.

\- Imported the `.vbox`, changed the default password, then `apt update \&\& apt full-upgrade`

\- Snapshots taken at each stable point: `clean-updated`, `clean-updated-noipv6`, `ssh-hardened-pre-ufw`



\## Hardening



| Control | Setting | Verified by |

|---|---|---|

| SSH auth | Dedicated ed25519 key, `PasswordAuthentication no`, `KbdInteractiveAuthentication no` | Key-only login from host with no password prompt |

| Root login | `PermitRootLogin no` | Config drop-in |

| Address family | `AddressFamily inet` (IPv4 only) | `ss -tulpn` shows no IPv6 listeners |

| IPv6 | Disabled via `nmcli` | `ss -tulpn` |

| Firewall | `ufw`: default deny incoming, allow outgoing, allow 22/tcp | `ufw status verbose` |



SSH settings live in a drop-in, `/etc/ssh/sshd\_config.d/10-lab-hardening.conf`, so the stock `sshd\_config` stays untouched and the change is easy to audit or revert.



\### Listening services after hardening



```

tcp  LISTEN  0.0.0.0:22  sshd

```



sshd on 22/tcp over IPv4 is the only listener. No UDP, no IPv6 sockets.



\### Firewall verification (from the host)



| Test | Result |

|---|---|

| `Test-NetConnection <kali-ip> -Port 22` | `TcpTestSucceeded : True` |

| `Test-NetConnection <kali-ip> -Port 8080` | `TcpTestSucceeded : False` (hangs, because ufw drops rather than rejects) |

| Ping | Succeeds. ufw's default rules answer ICMP echo. |



Note: `ufw allow 22/tcp` also adds a `22/tcp (v6)` rule. It never matches anything because IPv6 is disabled and sshd is bound to IPv4 only.



\## Network modes



\_To be written after each mode is documented.\_



\## Connectivity check script



\_To be written after `conncheck.sh` is tested.\_



\## Troubleshooting



\_To be written after the break-things exercises.\_

