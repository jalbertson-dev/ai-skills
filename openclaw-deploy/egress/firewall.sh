#!/usr/bin/env bash
#
# Kernel-level egress backstop for the OpenClaw container (defense in depth).
#
# The egress overlay (docker-compose.egress.yml) already isolates the gateway on
# an internal Docker network with no route out. This script adds a second,
# independent guarantee at the kernel: it inserts rules into Docker's DOCKER-USER
# iptables chain that DROP any forwarded traffic from the gateway subnet to the
# public internet, while still allowing replies and traffic to private ranges
# (so gateway -> proxy keeps working). Even if the internal network were ever
# misconfigured, the gateway still cannot reach an arbitrary internet host.
#
# Safe by design: DOCKER-USER only affects container-forwarded traffic. It does
# NOT touch host SSH (INPUT) or the host's own outbound (OUTPUT), so you cannot
# lock yourself out of the box with this.
#
# Usage:
#   sudo ./firewall.sh enable     # install the backstop rules
#   sudo ./firewall.sh disable    # remove them
#   sudo ./firewall.sh status     # show current DOCKER-USER rules
#
# Override the gateway subnet if you changed it in the overlay:
#   GW_SUBNET=172.31.250.0/24 sudo ./firewall.sh enable

set -euo pipefail

GW_SUBNET="${GW_SUBNET:-172.31.250.0/24}"
CHAIN="DOCKER-USER"
TAG="openclaw-egress-backstop"

need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }; }

rules_present() { iptables -C "$CHAIN" -s "$GW_SUBNET" -m comment --comment "$TAG" -j DROP 2>/dev/null; }

enable() {
  need_root
  if rules_present; then echo "Backstop already enabled for $GW_SUBNET."; return; fi
  # Order matters: allow replies + private destinations BEFORE the catch-all DROP.
  # Insert at the top of DOCKER-USER (rules are evaluated top-down).
  iptables -I "$CHAIN" 1 -s "$GW_SUBNET" -m comment --comment "$TAG" -j DROP
  iptables -I "$CHAIN" 1 -s "$GW_SUBNET" -d 192.168.0.0/16 -m comment --comment "$TAG" -j RETURN
  iptables -I "$CHAIN" 1 -s "$GW_SUBNET" -d 172.16.0.0/12  -m comment --comment "$TAG" -j RETURN
  iptables -I "$CHAIN" 1 -s "$GW_SUBNET" -d 10.0.0.0/8     -m comment --comment "$TAG" -j RETURN
  iptables -I "$CHAIN" 1 -s "$GW_SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED \
    -m comment --comment "$TAG" -j RETURN
  echo "Enabled egress backstop: $GW_SUBNET may reach private ranges only."
  echo "NOTE: rules are not persistent across reboot. Install iptables-persistent"
  echo "      (netfilter-persistent save) or re-run this on boot to keep them."
}

disable() {
  need_root
  while iptables -L "$CHAIN" --line-numbers -n 2>/dev/null | grep -q "$TAG"; do
    local n
    n="$(iptables -L "$CHAIN" --line-numbers -n | awk -v t="$TAG" '$0 ~ t {print $1; exit}')"
    [[ -n "$n" ]] && iptables -D "$CHAIN" "$n" || break
  done
  echo "Removed egress backstop rules."
}

status() { iptables -L "$CHAIN" -n -v --line-numbers; }

case "${1:-}" in
  enable)  enable ;;
  disable) disable ;;
  status)  status ;;
  *) echo "Usage: $0 {enable|disable|status}" >&2; exit 1 ;;
esac
