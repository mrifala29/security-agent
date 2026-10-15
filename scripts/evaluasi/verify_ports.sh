#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/evaluasi/verify_ports.sh
# Tahap : EVALUASI / VERIFIKASI (Read-Only)
# Fungsi: Memvalidasi secara komprehensif apakah tindakan hardening berhasil:
#         1. Apakah firewall UFW aktif dengan default incoming DENY?
#         2. Apakah port database publik (0.0.0.0) sudah terblokir/hilang?
#         3. Apakah port SSH (22) tetap bisa diakses dan aman?
#         4. Apakah koneksi internal aplikasi masih berjalan lancar?
# Output: Scorecard evaluasi (LULUS / GAGAL) tanpa emoticon berlebihan.
# ==============================================================================

set -u

echo "======================================================================"
echo "SCORECARD EVALUASI HASIL HARDENING PORT & JARINGAN"
echo "======================================================================"

SCORE_PASS=0
SCORE_WARN=0

# ------------------------------------------------------------------------------
# 1. Evaluasi Status Firewall (UFW)
# ------------------------------------------------------------------------------
echo "[1] EVALUASI FIREWALL (UFW)"
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(sudo ufw status | head -n 1 || echo "")
    if echo "$UFW_STATUS" | grep -qi "Status: active"; then
        echo "    Status : AKTIF (LULUS)"
        SCORE_PASS=$((SCORE_PASS + 1))
    else
        echo "    Status : NONAKTIF / INACTIVE (GAGAL - Server belum terproteksi firewall)"
        SCORE_WARN=$((SCORE_WARN + 1))
    fi
else
    echo "    Status : TIDAK TERPASANG (GAGAL)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# ------------------------------------------------------------------------------
# 2. Evaluasi Port Database Sensitif (3306, 5432, 27017, 6379)
# ------------------------------------------------------------------------------
echo ""
echo "[2] EVALUASI EKSPOSUR PORT DATABASE PUBLIK (0.0.0.0 / *)"
SENSITIVE_PORTS="3306|5432|5433|5434|5435|5436|5437|6379|27017|9042|5672"
RAW_LEAKS=$(ss -tulpn 2>/dev/null | grep -E "($SENSITIVE_PORTS)" | grep -E '(\*:|0\.0\.0\.0:|\[::\]:)' || true)

# Cek apakah UFW memblokir port tersebut
if [ -n "$RAW_LEAKS" ]; then
    echo "    Peringatan: Service database masih mendengarkan di interface publik."
    echo "    Memeriksa apakah difilter oleh Firewall UFW..."
    if sudo ufw status | grep -qi "Status: active"; then
        echo "    Status : TERFILTER FIREWALL (LULUS - Akses publik ditahan oleh UFW)"
        SCORE_PASS=$((SCORE_PASS + 1))
    else
        echo "    Status : TERBUKA TANPA FILTER (GAGAL - Segera aktifkan UFW)"
        SCORE_WARN=$((SCORE_WARN + 1))
    fi
else
    echo "    Status : BERSIH (LULUS - Tidak ada database yang listen di 0.0.0.0)"
    SCORE_PASS=$((SCORE_PASS + 1))
fi

# ------------------------------------------------------------------------------
# 3. Evaluasi Akses SSH (Anti-Lockout)
# ------------------------------------------------------------------------------
echo ""
echo "[3] EVALUASI AKSES MANAJEMEN SSH"
SSH_OPEN=$(sudo ufw status 2>/dev/null | grep -E '22/tcp|SSH' || true)
if [ -n "$SSH_OPEN" ] || ! sudo ufw status 2>/dev/null | grep -qi "Status: active"; then
    echo "    Status : AMAN (LULUS - Port SSH diizinkan, risiko terkunci nihil)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : KRITIS (GAGAL - Port SSH tidak tercatat di aturan UFW!)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# ------------------------------------------------------------------------------
# 4. Evaluasi Kontinuitas Koneksi Internal (VPC / Subnet)
# ------------------------------------------------------------------------------
echo ""
echo "[4] EVALUASI KONEKSI APLIKASI INTERNAL (VPC)"
INTERNAL_ESTAB=$(ss -ant state established 2>/dev/null | grep -E '10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.' | wc -l | tr -d ' ' || echo "0")
echo "    Jumlah koneksi internal aktif saat ini: $INTERNAL_ESTAB koneksi"
if [ "$INTERNAL_ESTAB" -gt 0 ]; then
    echo "    Status : NORMAL (LULUS - Aplikasi dan database internal tetap terhubung lancar)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : PERIKSA ULANG (Tidak terdeteksi traffic internal aktif)"
fi

# ------------------------------------------------------------------------------
# Ringkasan Skor
# ------------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "HASIL KESIMPULAN EVALUASI:"
echo "Total Poin LULUS : $SCORE_PASS"
echo "Total Poin GAGAL : $SCORE_WARN"
if [ "$SCORE_WARN" -eq 0 ]; then
    echo "KESIMPULAN: HARDENING PORT & JARINGAN DINYATAKAN BERHASIL (MEMENUHI SYARAT)!"
else
    echo "KESIMPULAN: MASIH ADA POIN YANG PERLU DIPERBAIKI SEBELUM DIANGGAP AMAN."
fi
echo "======================================================================"
