#!/usr/bin/env bash
# ==============================================================================
# Script: check_ssh_users.sh
# Fungsi: Memeriksa konfigurasi SSH aktif, daftar user akun, dan hak sudo.
# Sifat : 100% READ-ONLY (Aman dijalankan kapan saja)
# ==============================================================================

set -u

echo "======================================================================"
echo " [1] STATUS KONFIGURASI SSH DAEMON"
echo "======================================================================"
if command -v sshd >/dev/null 2>&1; then
    sudo sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication|port|maxauthtries)' || true
elif [ -f /etc/ssh/sshd_config ]; then
    grep -E '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port|MaxAuthTries)' /etc/ssh/sshd_config || true
fi

echo ""
echo "======================================================================"
echo " [2] AKUN USER DENGAN AKSES LOGIN / SUDO"
echo "======================================================================"
echo "--- User Biasa (UID >= 1000) ---"
awk -F: '($3 >= 1000 && $3 < 65534) {printf "User: %-15s UID: %-5s Shell: %s\n", $1, $3, $7}' /etc/passwd

echo ""
echo "--- User dengan UID 0 (Level Root) ---"
awk -F: '($3 == 0) {printf "UID 0 User: %s\n", $1}' /etc/passwd

echo ""
echo "--- Anggota Grup Sudo / Admin ---"
grep -E '^(sudo|wheel|admin):' /etc/group || echo "Grup sudo tidak ditemukan"
