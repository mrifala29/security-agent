#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/evaluasi/verify_triage.sh
# Tahap : EVALUASI / VERIFIKASI (Read-Only)
# Fungsi: Memvalidasi kebersihan sistem dari sisa proses terlarang / backdoor.
# ==============================================================================

set -u

echo "======================================================================"
echo "SCORECARD EVALUASI KEBERSIHAN SISTEM (TRIAGE & MALWARE)"
echo "======================================================================"

SCORE_PASS=0
SCORE_WARN=0

# 1. Verifikasi Proses di Folder Temp
echo "[1] VERIFIKASI PROSES DI FOLDER /tmp & /dev/shm"
PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '(/tmp|/dev/shm|/var/tmp)' || true)
if [ -z "$PROCS" ]; then
    echo "    Status : BERSIH (LULUS - Tidak ada proses berjalan dari direktori temp)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : MENCURIGAKAN (GAGAL - Ditemukan proses berjalan dari direktori temp)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# 2. Verifikasi Cron Jobs
echo ""
echo "[2] VERIFIKASI TUGAS TERJADWAL (CRON)"
CRON_TMP=$(mktemp)
trap 'rm -f "$CRON_TMP"' EXIT

if [ -f /etc/crontab ]; then grep -vE '^\s*#' /etc/crontab >> "$CRON_TMP" || true; fi
if [ -d /etc/cron.d ]; then find /etc/cron.d -type f -exec grep -vE '^\s*#' {} + 2>/dev/null >> "$CRON_TMP" || true; fi
if [ -d /var/spool/cron/crontabs ]; then sudo cat /var/spool/cron/crontabs/* 2>/dev/null | grep -vE '^\s*#' >> "$CRON_TMP" || true; fi

SUSP=$(grep -E '(curl|wget|python|perl|bash -i|/dev/tcp|nc -e|/tmp/|/dev/shm)' "$CRON_TMP" 2>/dev/null || true)
if [ -z "$SUSP" ]; then
    echo "    Status : BERSIH (LULUS - Tidak ada cron job download script otomatis)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : PERINGATAN (GAGAL - Masih ada cron job memanggil URL eksternal)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# Ringkasan
echo ""
echo "======================================================================"
echo "HASIL KESIMPULAN EVALUASI TRIAGE:"
echo "Total Poin LULUS : $SCORE_PASS"
echo "Total Poin GAGAL : $SCORE_WARN"
if [ "$SCORE_WARN" -eq 0 ]; then
    echo "KESIMPULAN: SISTEM DINYATAKAN BERSIH DARI JEJAK BACKDOOR AKTIF (LULUS)!"
else
    echo "KESIMPULAN: DITEMUKAN INDIKASI YANG MEMERLUKAN TINDAKAN PEMBERSIHAN ULANG."
fi
echo "======================================================================"
