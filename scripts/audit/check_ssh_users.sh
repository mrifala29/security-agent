#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/audit/check_ssh_users.sh
# Tahap : AUDIT (100% Read-Only)
# Fungsi: Memeriksa konfigurasi SSH daemon, akun pengguna, privilege sudo,
#         dan akun berisiko (UID 0 / empty password).
# Output:
#   1. Laporan teks bersih ke konsol
#   2. Blok JSON State (ssh_users_state.json)
# ==============================================================================

set -u

echo "======================================================================"
echo "AUDIT AUTENTIKASI SSH & AKUN PENGGUNA"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Konfigurasi SSH Daemon
# ------------------------------------------------------------------------------
echo "[1] KONFIGURASI AKTIF SSH DAEMON"
SSHD_CONFIG=""
if command -v sshd >/dev/null 2>&1; then
    SSHD_CONFIG=$(sudo sshd -T 2>/dev/null || true)
fi

get_sshd_val() {
    local param="$1"
    local default_val="$2"
    if [ -n "$SSHD_CONFIG" ]; then
        echo "$SSHD_CONFIG" | grep -i "^${param} " | awk '{print $2}' || echo "$default_val"
    else
        grep -i "^${param} " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "$default_val"
    fi
}

PASS_AUTH=$(get_sshd_val "passwordauthentication" "unknown")
ROOT_LOGIN=$(get_sshd_val "permitrootlogin" "unknown")
PUBKEY_AUTH=$(get_sshd_val "pubkeyauthentication" "unknown")
SSH_PORT=$(get_sshd_val "port" "22")
MAX_AUTH=$(get_sshd_val "maxauthtries" "6")

printf "    Port SSH                 : %s\n" "$SSH_PORT"
printf "    Password Authentication  : %s %s\n" "$PASS_AUTH" "$([ "$PASS_AUTH" == "yes" ] && echo "(PERLU DIAMANKAN - Rentan Brute Force)" || echo "(Aman)")"
printf "    Permit Root Login        : %s %s\n" "$ROOT_LOGIN" "$([ "$ROOT_LOGIN" == "yes" ] && echo "(PERLU DIAMANKAN - Root Langsung)" || echo "(Aman)")"
printf "    Pubkey Authentication    : %s\n" "$PUBKEY_AUTH"
printf "    Max Auth Tries           : %s\n" "$MAX_AUTH"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Akun dengan Hak Root (UID 0) & Empty Password
# ------------------------------------------------------------------------------
echo ""
echo "[2] AKUN DENGAN PRIVILEGE TERTINGGI (UID 0) & PASSWORD KOSONG"
UID_ZERO=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | tr '\n' ' ' | sed 's/ $//')
echo "    Akun UID 0 (Level Root): $UID_ZERO"
if [ "$UID_ZERO" != "root" ]; then
    echo "    PERINGATAN KRITIS: Ditemukan user selain root dengan UID 0!"
fi

EMPTY_PASS=$(sudo awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | tr '\n' ' ' || echo "N/A")
echo "    Pengecekan Akun Tanpa Password: Selesai."
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Pengguna Biasa & Anggota Grup Sudo
# ------------------------------------------------------------------------------
echo ""
echo "[3] DAFTAR USER & ANGGOTA GRUP SUDO"
echo "    User dengan hak Sudo / Admin:"
SUDO_USERS=$(grep -E '^(sudo|wheel|admin):' /etc/group | cut -d: -f4 | tr ',' ' ' || echo "None")
echo "    -> $SUDO_USERS"

echo ""
echo "    Daftar User Biasa (UID >= 1000):"
awk -F: '($3 >= 1000 && $3 < 65534) {printf "    - User: %-15s (UID: %-5s, Shell: %s)\n", $1, $3, $7}' /etc/passwd
echo "======================================================================"

# ==============================================================================
# OUTPUT STATE DATA JSON
# ==============================================================================
echo "###SSH_USERS_STATE_START###"
cat <<JSON_EOF
{
  "password_authentication": "$PASS_AUTH",
  "permit_root_login": "$ROOT_LOGIN",
  "pubkey_authentication": "$PUBKEY_AUTH",
  "ssh_port": "$SSH_PORT",
  "max_auth_tries": "$MAX_AUTH",
  "uid_zero_accounts": ["$(echo "$UID_ZERO" | sed 's/ /","/g')"],
  "sudo_members": ["$(echo "$SUDO_USERS" | sed 's/ /","/g')"]
}
JSON_EOF
echo "###SSH_USERS_STATE_END###"
