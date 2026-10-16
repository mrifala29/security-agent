#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/create_developer_user.sh
# Tahap : ACTION (Eksekusi Pengguna)
# Fungsi: Membuat akun developer baru dengan SSH Public Key & akses sudo aman.
# Penggunaan:
#   sudo ./create_developer_user.sh <username> "<public_key_string>"
# ==============================================================================

set -euo pipefail

DEV_USER="${1:-}"
PUB_KEY="${2:-}"

if [ -z "$DEV_USER" ] || [ -z "$PUB_KEY" ]; then
    echo "======================================================================"
    echo "PANDUAN PEMBUATAN AKUN DEVELOPER"
    echo "======================================================================"
    echo "Format Penggunaan:"
    echo "  sudo ./create_developer_user.sh <nama_user> \"<ssh_public_key>\""
    echo ""
    echo "Contoh:"
    echo "  sudo ./create_developer_user.sh dev-budi \"ssh-ed25519 AAAAC3... budi@laptop\""
    echo "======================================================================"
    exit 1
fi

echo "1. Membuat user '$DEV_USER'..."
if id "$DEV_USER" >/dev/null 2>&1; then
    echo "   User '$DEV_USER' sudah ada di sistem."
else
    sudo adduser --disabled-password --gecos "" "$DEV_USER"
    echo "   User '$DEV_USER' berhasil dibuat (login password biasa dimatikan)."
fi

echo "2. Menambahkan ke grup 'sudo'..."
sudo usermod -aG sudo "$DEV_USER"

echo "3. Menyiapkan folder SSH & authorized_keys..."
USER_HOME=$(eval echo "~$DEV_USER")
sudo mkdir -p "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"

# Tambahkan public key (idempoten)
sudo touch "$USER_HOME/.ssh/authorized_keys"
if ! sudo grep -qxF "$PUB_KEY" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null; then
    echo "$PUB_KEY" | sudo tee -a "$USER_HOME/.ssh/authorized_keys" >/dev/null
fi
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"
sudo chown -R "$DEV_USER:$DEV_USER" "$USER_HOME/.ssh"

echo "4. Mengonfigurasi hak akses Sudo (Passwordless Sudo untuk User Berbasis SSH Key)..."
echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$DEV_USER" >/dev/null
sudo chmod 440 "/etc/sudoers.d/$DEV_USER"

echo "======================================================================"
echo "AKUN DEVELOPER SELESAI DIBUAT!"
echo "User       : $DEV_USER"
echo "Akses Sudo : Aktif"
echo "Kunci SSH  : Terdaftar di $USER_HOME/.ssh/authorized_keys"
echo "======================================================================"
