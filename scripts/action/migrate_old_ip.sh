#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/migrate_old_ip.sh
# Tahap : ACTION (Eksekusi Perbaikan Konfigurasi)
# Fungsi: Mengubah referensi IP lama (103.230.81.70) menjadi IP baru (163.128.54.32)
#         pada seluruh file .env aktif di /home dan /opt secara aman
# Sifat : Dilengkapi auto-backup (.bak_ip70_timestamp) sebelum file disentuh!
# ==============================================================================

set -euo pipefail

OLD_IP="103.230.81.70"
NEW_IP="163.128.54.32"
TS=$(date +"%Y%m%d_%H%M%S")

echo "======================================================================"
echo "MIGRASI IP LAMA ($OLD_IP) KE IP BARU ($NEW_IP)"
echo "======================================================================"

# 1. Cari seluruh file .env aktif yang masih mengandung OLD_IP
echo "1. Memindai file konfigurasi .env aktif di /home dan /opt..."
TARGET_FILES=$(find /home /opt -type f \( -name "*.env" -o -name "*.env.*" \) ! -name "*.bak*" ! -name "*.backup*" 2>/dev/null | xargs grep -l "$OLD_IP" 2>/dev/null || true)

if [ -z "$TARGET_FILES" ]; then
    echo "   Tidak ditemukan file .env aktif yang menggunakan IP $OLD_IP."
    echo "   Semua konfigurasi sudah bersih / telah dimigrasikan!"
    echo "======================================================================"
    exit 0
fi

TOTAL_FILES=$(echo "$TARGET_FILES" | wc -l | tr -d ' ')
echo "   Ditemukan $TOTAL_FILES file yang perlu dimigrasikan."
echo ""

echo "2. Mengeksekusi Migrasi Presisi (Dengan Auto-Backup per File):"
echo "----------------------------------------------------------------------"

MODIFIED_COUNT=0
while IFS= read -r f; do
    if [ -f "$f" ]; then
        # Buat backup individual
        BAK_FILE="${f}.bak_ip70_${TS}"
        cp "$f" "$BAK_FILE"
        
        # Simpan cuplikan sebelum
        BEFORE_LINES=$(grep "$OLD_IP" "$f" || true)
        
        # Ganti IP lama ke IP baru
        sed -i "s/$OLD_IP/$NEW_IP/g" "$f"
        
        # Simpan cuplikan sesudah
        AFTER_LINES=$(grep "$NEW_IP" "$f" | grep -E 'HOST|URL|DSN|NODES|ENDPOINT' || true)
        
        MODIFIED_COUNT=$((MODIFIED_COUNT + 1))
        echo "[$MODIFIED_COUNT/$TOTAL_FILES] File: $f"
        echo "   Backup  : $BAK_FILE"
        echo "   Sebelum : $(echo "$BEFORE_LINES" | head -n 1)"
        echo "   Sesudah : $(echo "$AFTER_LINES" | head -n 1)"
        echo "----------------------------------------------------------------------"
    fi
done <<< "$TARGET_FILES"

echo ""
echo "======================================================================"
echo "RINGKASAN HASIL MIGRASI IP:"
echo "Total File Dimigrasikan : $MODIFIED_COUNT file"
echo "IP Lama ($OLD_IP)       -> IP Baru ($NEW_IP)"
echo "Semua file asli dicadangkan dengan ekstensi: .bak_ip70_${TS}"
echo ""
echo "CATATAN OPERASIONAL DOCKER:"
echo "1. Mengubah file .env di disk TIDAK menimbulkan downtime mendadak."
echo "2. Service/container akan membaca IP baru saat di-restart / di-redeploy."
echo "======================================================================"
