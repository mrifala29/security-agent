#!/usr/bin/env bash
# ==============================================================================
# Script: check_triage.sh
# Fungsi: Memeriksa sisa-sisa indikasi penyusup (cron jobs, unauthorized keys,
#         proses mencurigakan dari /tmp atau /dev/shm).
# Sifat : 100% READ-ONLY (Aman dijalankan kapan saja)
# ==============================================================================

set -u

echo "======================================================================"
echo " [1] CEK TUGAS TERJADWAL (CRON JOBS)"
echo "======================================================================"
echo "--- /etc/crontab ---"
grep -vE '^\s*#' /etc/crontab 2>/dev/null | grep -v '^\s*$' || echo "Kosong"

echo "--- /etc/cron.d/ ---"
ls -la /etc/cron.d/ 2>/dev/null

echo "--- Crontab Users (/var/spool/cron/crontabs) ---"
if [ -d /var/spool/cron/crontabs ]; then
    sudo ls -la /var/spool/cron/crontabs 2>/dev/null || echo "Perlu sudo untuk melihat crontabs user"
fi

echo ""
echo "======================================================================"
echo " [2] CEK AUTHORIZED KEYS (KUNCI SSH YANG DIIZINKAN MASUK)"
echo "======================================================================"
echo "--- Root Authorized Keys ---"
if [ -f /root/.ssh/authorized_keys ]; then
    sudo cat /root/.ssh/authorized_keys 2>/dev/null || echo "Perlu sudo untuk membaca /root/.ssh/authorized_keys"
else
    echo "Tidak ada /root/.ssh/authorized_keys"
fi

echo "--- User Home Authorized Keys ---"
for userdir in /home/*; do
    if [ -d "$userdir/.ssh" ] && [ -f "$userdir/.ssh/authorized_keys" ]; then
        echo "[$userdir/.ssh/authorized_keys]:"
        cat "$userdir/.ssh/authorized_keys" 2>/dev/null || sudo cat "$userdir/.ssh/authorized_keys"
    fi
done

echo ""
echo "======================================================================"
echo " [3] CEK PROSES YANG BERJALAN DARI FOLDER SEMENTARA (/tmp, /dev/shm)"
echo "======================================================================"
SUSPICIOUS_PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '(/tmp|/dev/shm|/var/tmp)' || true)
if [ -n "$SUSPICIOUS_PROCS" ]; then
    echo "PERINGATAN: Ditemukan proses berjalan dari folder sementara:"
    echo "$SUSPICIOUS_PROCS"
else
    echo "Bersih: Tidak ada proses yang berjalan dari /tmp atau /dev/shm."
fi
