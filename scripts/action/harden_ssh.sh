#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/harden_ssh.sh
# Tahap : ACTION (Eksekusi Pengamanan SSH)
# Fungsi: Mematikan login password biasa dan mematikan login root langsung.
# Sifat : Tulis / Konfigurasi Sistem (Wajib ada developer user dengan SSH key!)
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo "EKSEKUSI PENGUATAN KONFIGURASI SSH (HARDEN SSH)"
echo "======================================================================"

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"

# 1. Backup file sshd_config asli
echo "1. Membuat salinan cadangan sshd_config..."
sudo cp -p "$SSHD_CONFIG" "$BACKUP_FILE"
echo "   -> Backup tersimpan di: $BACKUP_FILE"

# 2. Terapkan konfigurasi pengerasan SSH
echo ""
echo "2. Menerapkan konfigurasi keamanan SSH..."

set_sshd_param() {
    local param="$1"
    local value="$2"
    if grep -qE "^[#\s]*${param}\s+" "$SSHD_CONFIG"; then
        sudo sed -i -E "s/^[#\s]*${param}\s+.*/${param} ${value}/" "$SSHD_CONFIG"
    else
        echo "${param} ${value}" | sudo tee -a "$SSHD_CONFIG" >/dev/null
    fi
}

# Matikan Password Authentication (Wajib SSH Key)
set_sshd_param "PasswordAuthentication" "no"
echo "   - PasswordAuthentication -> no"

# Matikan Direct Root Login
set_sshd_param "PermitRootLogin" "no"
echo "   - PermitRootLogin -> no"

# Pastikan Pubkey Authentication Aktif
set_sshd_param "PubkeyAuthentication" "yes"
echo "   - PubkeyAuthentication -> yes"

# Batasi Percobaan Login Gagal
set_sshd_param "MaxAuthTries" "3"
echo "   - MaxAuthTries -> 3"

# 3. Uji Sintaks Sebelum Reload Service (ANTI-LOCKOUT SAFETY)
echo ""
echo "3. Menguji sintaks konfigurasi SSH (sshd -t)..."
if sudo sshd -t; then
    echo "   -> Sintaks 100% VALID! Tidak ada error."
    echo ""
    echo "4. Me-reload service SSH..."
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh
    else
        sudo service ssh reload
    fi
    echo "   -> Service SSH berhasil di-reload."
else
    echo "   -> ERROR: Sintaks konfigurasi tidak valid!"
    echo "   -> Melakukan RESTORE otomatis ke backup: $BACKUP_FILE"
    sudo cp -p "$BACKUP_FILE" "$SSHD_CONFIG"
    exit 1
fi

echo ""
echo "======================================================================"
echo "PENGUATAN SSH SELESAI!"
echo "PENTING: JANGAN TUTUP TERMINAL INI DULU!"
echo "Buka terminal baru di komputer Anda dan uji coba login SSH untuk"
echo "memastikan kunci SSH Anda dapat masuk tanpa kendala."
echo "======================================================================"
