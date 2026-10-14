#!/usr/bin/env bash
# Build your own VPN server in 5 minutes
# https://github.com/tvcregion/vpn-in-5-minutes
#
# A small, auditable wrapper around angristan/wireguard-install (MIT):
#   1. downloads the upstream installer pinned to a reviewed commit,
#   2. verifies its SHA-256 before running anything,
#   3. runs it interactively (also works when piped into bash),
#   4. opens the WireGuard UDP port in ufw if ufw is active.
#
# Usage, as root on a fresh Ubuntu / Debian VPS:
#   bash <(curl -fsSL https://raw.githubusercontent.com/tvcregion/vpn-in-5-minutes/main/install.sh)
#
# Run it again to add devices, list or revoke them, or uninstall WireGuard.

set -euo pipefail

UPSTREAM_REPO="angristan/wireguard-install"
UPSTREAM_COMMIT="832fb9833501a7220e2900cffb61082841dedba8"
UPSTREAM_SHA256="e5729fa20d6cc48e1de7616427762bbfde905eb3c806fef5810d71dc65bd681c"
UPSTREAM_URL="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_COMMIT}/wireguard-install.sh"

green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
red() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

VERIFY_ONLY=0
if [[ "${1:-}" == "--verify-only" ]]; then
	VERIFY_ONLY=1
fi

if [[ $VERIFY_ONLY -eq 0 && $EUID -ne 0 ]]; then
	red "Please run this as root (for example: sudo -i, then run the command again)."
	exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

green "==> Downloading the WireGuard installer (${UPSTREAM_REPO}@${UPSTREAM_COMMIT:0:7})"
curl -fsSL "$UPSTREAM_URL" -o "$tmp/wireguard-install.sh"

actual="$(sha256 "$tmp/wireguard-install.sh")"
if [[ "$actual" != "$UPSTREAM_SHA256" ]]; then
	red "Checksum mismatch, refusing to run."
	red "  expected: $UPSTREAM_SHA256"
	red "  got:      $actual"
	exit 1
fi
green "==> Checksum OK"

if [[ $VERIFY_ONLY -eq 1 ]]; then
	exit 0
fi

# The installer asks questions, so read answers from the terminal even if
# this wrapper itself arrived through a pipe.
bash "$tmp/wireguard-install.sh" </dev/tty

params=/etc/wireguard/params
if [[ -f $params ]]; then
	port="$(grep -E '^SERVER_PORT=' "$params" | cut -d= -f2)"
	if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
		ufw allow "${port}/udp" >/dev/null
		green "==> ufw: allowed ${port}/udp"
	fi
	echo
	yellow "Phone won't connect? Open UDP port ${port} in your VPS provider's firewall panel."
fi
