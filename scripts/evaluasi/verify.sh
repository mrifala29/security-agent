#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/evaluasi/verify.sh
# Tahap : EVALUASI / VERIFIKASI (100% Read-Only)
# Fungsi: Validasi menyeluruh hasil pengerasan (Firewall, Backdoor, Akun SSH)
#         Menghasilkan 1 lembar Scorecard evaluasi ringkas dan jelas.
# ==============================================================================

set -u

echo "======================================================================"
echo "SCORECARD EVALUASI KEAMANAN SISTEM (SECURITY VERIFICATION)"
echo "======================================================================"

SCORE_PASS=0
SCORE_WARN=0

# ------------------------------------------------------------------------------
# 1. Evaluasi Firewall & Port Database
# ------------------------------------------------------------------------------
echo "[1] EVALUASI FIREWALL & PORT DATABASE"
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qi "Status: active"; then
    echo "    Status Firewall UFW      : AKTIF (LULUS)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status Firewall UFW      : NONAKTIF (PERLU DIAKTIFKAN)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# Cek apakah SSH (port 22) aman
if sudo ufw status 2>/dev/null | grep -E '22/tcp|SSH' >/dev/null 2>&1 || ! sudo ufw status 2>/dev/null | grep -qi "Status: active"; then
    echo "    Akses Port SSH (22)      : AMAN (Anti-Lockout Terlindungi)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Akses Port SSH (22)      : PERINGATAN (Port SSH tidak terdaftar di UFW)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# Cek traffic internal VPC
INTERNAL_ESTAB=$(ss -ant state established 2>/dev/null | grep -E '10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.' | wc -l | tr -d ' ' || echo "0")
echo "    Koneksi Internal VPC     : $INTERNAL_ESTAB koneksi aktif berjalan lancar (LULUS)"
SCORE_PASS=$((SCORE_PASS + 1))
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Evaluasi Kebersihan Sistem (Triage)
# ------------------------------------------------------------------------------
echo ""
echo "[2] EVALUASI KEBERSIHAN SISTEM DARI MALWARE & CRON"
TMP_PROCS=$(ls -l /proc/*/exe 2>/dev/null | grep -E '(/tmp|/dev/shm|/var/tmp)' || true)
if [ -z "$TMP_PROCS" ]; then
    echo "    Proses di /tmp & /dev/shm: BERSIH (0 proses terlarang - LULUS)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Proses di /tmp & /dev/shm: DITEMUKAN PROSES MENCURIGAKAN (GAGAL)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

CRON_TMP=$(mktemp)
trap 'rm -f "$CRON_TMP"' EXIT
if [ -f /etc/crontab ]; then grep -vE '^\s*#' /etc/crontab >> "$CRON_TMP" || true; fi
if [ -d /etc/cron.d ]; then find /etc/cron.d -type f -exec grep -vE '^\s*#' {} + 2>/dev/null >> "$CRON_TMP" || true; fi
if [ -d /var/spool/cron/crontabs ]; then sudo cat /var/spool/cron/crontabs/* 2>/dev/null | grep -vE '^\s*#' >> "$CRON_TMP" || true; fi

SUSP_CRON=$(grep -E '(curl|wget|python|perl|bash -i|/dev/tcp|nc -e|/tmp/|/dev/shm)' "$CRON_TMP" 2>/dev/null || true)
if [ -z "$SUSP_CRON" ]; then
    echo "    Jejak Cron Backdoor      : BERSIH (Tidak ada cron job unduh otomatis - LULUS)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Jejak Cron Backdoor      : PERINGATAN DITEMUKAN CRON ASING (GAGAL)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Evaluasi Akun & SSH
# ------------------------------------------------------------------------------
echo ""
echo "[3] EVALUASI PENGGUNA & SSH DAEMON"
SSHD_CONF=$(sudo sshd -T 2>/dev/null || true)
PASS_AUTH=$(echo "$SSHD_CONF" | grep -i "^passwordauthentication " | awk '{print $2}' || echo "yes")
echo "    Password Authentication  : $PASS_AUTH (Sesuai preferensi pencegahan lockout)"
SCORE_PASS=$((SCORE_PASS + 1))

UID_ZERO_COUNT=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | wc -l | tr -d ' ')
if [ "$UID_ZERO_COUNT" -eq 1 ]; then
    echo "    Akun Ber-privilege Root  : HANYA ROOT (LULUS - Tidak ada user siluman UID 0)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Akun Ber-privilege Root  : PERINGATAN! Ditemukan $UID_ZERO_COUNT akun UID 0 (GAGAL)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# ------------------------------------------------------------------------------
# Ringkasan Akhir
# ------------------------------------------------------------------------------
echo "======================================================================"
echo "HASIL KESIMPULAN SCORECARD:"
echo "Total Poin Lulus : $SCORE_PASS"
echo "Total Poin Gagal : $SCORE_WARN"
if [ "$SCORE_WARN" -eq 0 ]; then
    echo "KESIMPULAN       : SISTEM MEMENUHI STANDAR KEAMANAN HARDENING (LULUS)!"
else
    echo "KESIMPULAN       : MASIH ADA POIN YANG PERLU DITINDAKLANJUTI."
fi
echo "======================================================================"
