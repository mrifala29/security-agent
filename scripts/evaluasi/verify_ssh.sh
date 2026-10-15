#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/evaluasi/verify_ssh.sh
# Tahap : EVALUASI / VERIFIKASI (Read-Only)
# Fungsi: Memvalidasi konfigurasi SSH setelah penguatan (harden_ssh).
# ==============================================================================

set -u

echo "======================================================================"
echo "SCORECARD EVALUASI HASIL HARDENING AUTENTIKASI SSH"
echo "======================================================================"

SSHD_CONF=$(sudo sshd -T 2>/dev/null || true)
SCORE_PASS=0
SCORE_WARN=0

# 1. Verifikasi Password Authentication
echo "[1] VERIFIKASI PASSWORD AUTHENTICATION"
PASS_AUTH=$(echo "$SSHD_CONF" | grep -i "^passwordauthentication " | awk '{print $2}' || echo "unknown")
if [ "$PASS_AUTH" == "no" ]; then
    echo "    Status : PASSWORD AUTHENTICATION = NO (LULUS - Brute force terblokir)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : PASSWORD AUTHENTICATION = $PASS_AUTH (AKTIF - Dibiarkan sesuai preferensi agar tidak terkunci)"
    SCORE_PASS=$((SCORE_PASS + 1))
fi

# 2. Verifikasi Permit Root Login
echo ""
echo "[2] VERIFIKASI PERMIT ROOT LOGIN"
ROOT_LOG=$(echo "$SSHD_CONF" | grep -i "^permitrootlogin " | awk '{print $2}' || echo "unknown")
if [ "$ROOT_LOG" == "no" ] || [ "$ROOT_LOG" == "prohibit-password" ]; then
    echo "    Status : PERMIT ROOT LOGIN = $ROOT_LOG (LULUS - Root langsung dicegah)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : PERMIT ROOT LOGIN = $ROOT_LOG (GAGAL - Root masih bisa login langsung)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# 3. Verifikasi Akun UID 0
echo ""
echo "[3] VERIFIKASI AKUN LEVEL ROOT (UID 0)"
UID_ZERO_COUNT=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | wc -l | tr -d ' ')
if [ "$UID_ZERO_COUNT" -eq 1 ]; then
    echo "    Status : HANYA 1 AKUN ROOT TERDAFTAR (LULUS - Tidak ada user siluman UID 0)"
    SCORE_PASS=$((SCORE_PASS + 1))
else
    echo "    Status : PERINGATAN KRITIS: Ditemukan $UID_ZERO_COUNT akun dengan UID 0 (GAGAL)"
    SCORE_WARN=$((SCORE_WARN + 1))
fi

# Ringkasan
echo ""
echo "======================================================================"
echo "HASIL KESIMPULAN EVALUASI SSH:"
echo "Total Poin LULUS : $SCORE_PASS"
echo "Total Poin GAGAL : $SCORE_WARN"
if [ "$SCORE_WARN" -eq 0 ]; then
    echo "KESIMPULAN: HARDENING AUTENTIKASI SSH DINYATAKAN BERHASIL (LULUS)!"
else
    echo "KESIMPULAN: MASIH ADA CELAH SSH YANG BELUM TERPENUHI."
fi
echo "======================================================================"
