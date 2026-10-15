#!/usr/bin/env bash
# ==============================================================================
# Script: backup_configs.sh
# Fungsi: Membuat backup file konfigurasi sensitif (SSH, UFW, Users, Cron)
#         sebelum dilakukan perubahan apapun pada sistem.
# Sifat : Non-destruktif (Hanya menyalin file)
# ==============================================================================

set -euo pipefail

BACKUP_DIR="/var/backups/security_agent_$(date +%Y%m%d_%H%M%S)"

echo "Membuat direktori backup di server: $BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"

# 1. Backup SSH Configuration
if [ -d /etc/ssh ]; then
    echo "Mencadangkan /etc/ssh ..."
    sudo cp -rp /etc/ssh "$BACKUP_DIR/ssh"
fi

# 2. Backup Accounts & Sudoers
echo "Mencadangkan passwd, group, dan sudoers ..."
sudo cp -p /etc/passwd "$BACKUP_DIR/passwd"
sudo cp -p /etc/group "$BACKUP_DIR/group"
sudo cp -p /etc/sudoers "$BACKUP_DIR/sudoers"
if [ -d /etc/sudoers.d ]; then
    sudo cp -rp /etc/sudoers.d "$BACKUP_DIR/sudoers.d"
fi

# 3. Backup Crontabs
echo "Mencadangkan konfigurasi Cron ..."
if [ -f /etc/crontab ]; then
    sudo cp -p /etc/crontab "$BACKUP_DIR/crontab"
fi
if [ -d /etc/cron.d ]; then
    sudo cp -rp /etc/cron.d "$BACKUP_DIR/cron.d"
fi
if [ -d /var/spool/cron/crontabs ]; then
    sudo cp -rp /var/spool/cron/crontabs "$BACKUP_DIR/user_crontabs"
fi

# 4. Backup UFW rules if exists
if [ -d /etc/ufw ]; then
    echo "Mencadangkan aturan UFW ..."
    sudo cp -rp /etc/ufw "$BACKUP_DIR/ufw"
fi

echo ""
echo "======================================================================"
echo "BACKUP SELESAI!"
echo "Lokasi cadangan di server: $BACKUP_DIR"
echo "======================================================================"
