#!/usr/bin/env bash
# conncheck.sh: connectivity check for a testing appliance
# Usage: ./conncheck.sh [-p] [-t seconds] [-H dns_host]
#   -p  also report public IP
#   -t  per-check timeout in seconds (default 3)
#   -H  hostname used for the DNS test (default example.com)
# Exits 0 if all checks pass, 1 if any fail, 2 on bad usage.

TIMEOUT=3
DNS_HOST="example.com"
TCP_TARGET="1.1.1.1"   # listens on 53, 80, 443; IP avoids mixing DNS into TCP tests
SHOW_PUBLIC=0
FAIL=0

while getopts "pt:H:" opt; do
  case $opt in
    p) SHOW_PUBLIC=1 ;;
    t) TIMEOUT=$OPTARG ;;
    H) DNS_HOST=$OPTARG ;;
    *) echo "Usage: $0 [-p] [-t seconds] [-H dns_host]"; exit 2 ;;
  esac
done

report() {
  if [ "$1" -eq 0 ]; then
    printf 'PASS  %s\n' "$2"
  else
    printf 'FAIL  %s\n' "$2"
    FAIL=1
  fi
}

# 1. Default gateway reachability
GW=$(ip route | awk '/^default/ {print $3; exit}')
if [ -z "$GW" ]; then
  report 1 "default gateway (none configured)"
else
  timeout "$TIMEOUT" ping -c 1 -W "$TIMEOUT" "$GW" >/dev/null 2>&1
  report $? "default gateway $GW reachable"
fi

# 2. DNS resolution
timeout "$TIMEOUT" getent hosts "$DNS_HOST" >/dev/null 2>&1
report $? "DNS resolves $DNS_HOST"

# 3. Outbound TCP
for port in 53 80 443; do
  timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$TCP_TARGET/$port" >/dev/null 2>&1
  report $? "outbound TCP $port to $TCP_TARGET"
done

# 4. Optional public IP
if [ "$SHOW_PUBLIC" -eq 1 ]; then
  IP=$(curl -s --max-time "$TIMEOUT" https://api.ipify.org)
  if [ -n "$IP" ]; then
    report 0 "public IP $IP"
  else
    report 1 "public IP lookup"
  fi
fi

exit $FAIL