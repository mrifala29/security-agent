#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/audit/check_triage.sh
# Tahap : AUDIT (100% Read-Only)
# Fungsi: Memeriksa indikasi sisa penyusup (cron jobs, authorized_keys, proses /tmp)
# Output:
#   1. Laporan teks bersih ke konsol
#   2. Blok JSON State (triage_state.json)
# ==============================================================================

set -u

echo "======================================================================"
echo "AUDIT INDIKASI PENYUSUP & BACKDOOR (TRIAGE)"
echo "======================================================================"

TMP_CRON=$(mktemp)
TMP_KEYS=$(mktemp)
TMP_PROCS=$(mktemp)
trap 'rm -f "$TMP_CRON" "$TMP_KEYS" "$TMP_PROCS"' EXIT

# ------------------------------------------------------------------------------
# 1. Cek Tugas Terjadwal (Cron Jobs)
# ------------------------------------------------------------------------------
echo "[1] MEMERIKSA TUGAS TERJADWAL (CRON JOBS)"
CRON_SUSP_COUNT=0

# System Crontab
if [ -f /etc/crontab ]; then
    grep -vE '^\s*#' /etc/crontab | grep -v '^\s*$' > "$TMP_CRON" || true
fi

# Cron.d
if [ -d /etc/cron.d ]; then
    find /etc/cron.d -type f -exec grep -vE '^\s*#' {} + 2>/dev/null >> "$TMP_CRON" || true
fi

# User crontabs
if [ -d /var/spool/cron/crontabs ]; then
    sudo ls -1 /var/spool/cron/crontabs 2>/dev/null | while read -r u; do
        sudo grep -vE '^\s*#' "/var/spool/cron/crontabs/$u" 2>/dev/null | awk -v user="$u" '{print user ": " $0}' >> "$TMP_CRON" || true
    done
fi

# Deteksi perintah mencurigakan di cron (curl/wget pipe to sh, nc, python reverse shell)
SUSP_CRON=$(grep -E '(curl|wget|python|perl|bash -i|/dev/tcp|nc -e|/tmp/|/dev/shm)' "$TMP_CRON" || true)

if [ -n "$SUSP_CRON" ]; then
    echo "    PERINGATAN: Ditemukan cron job mencurigakan yang memanggil script eksternal/temp:"
    echo "$SUSP_CRON" | sed 's/^/    /'
    CRON_SUSP_COUNT=$(echo "$SUSP_CRON" | wc -l | tr -d ' ')
else
    echo "    Status: Tidak ditemukan cron job mencurigakan (Bersih)."
fi
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Cek Kunci SSH (Authorized Keys)
# ------------------------------------------------------------------------------
echo ""
echo "[2] MEMERIKSA KUNCI SSH TERDAFTAR (AUTHORIZED KEYS)"
ROOT_KEYS_COUNT=0
TOTAL_USER_KEYS=0

# Root keys
if [ -f /root/.ssh/authorized_keys ]; then
    ROOT_KEYS_COUNT=$(sudo grep -vE '^\s*#' /root/.ssh/authorized_keys 2>/dev/null | grep -v '^\s*$' | wc -l | tr -d ' ' || echo "0")
    echo "    Kunci terdaftar di /root/.ssh/authorized_keys: $ROOT_KEYS_COUNT kunci"
    sudo grep -vE '^\s*#' /root/.ssh/authorized_keys 2>/dev/null | grep -v '^\s*$' | awk '{printf "    - Type: %-15s Comment: %s\n", $1, $3}' || true
else
    echo "    /root/.ssh/authorized_keys: Tidak ada kunci (Aman)"
fi

# User keys
echo "    Kunci terdaftar di direktori /home/*/.ssh/:"
for userdir in /home/*; do
    if [ -d "$userdir/.ssh" ] && [ -f "$userdir/.ssh/authorized_keys" ]; then
        uname=$(basename "$userdir")
        ukey_count=$(sudo grep -vE '^\s*#' "$userdir/.ssh/authorized_keys" 2>/dev/null | grep -v '^\s*$' | wc -l | tr -d ' ' || echo "0")
        TOTAL_USER_KEYS=$((TOTAL_USER_KEYS + ukey_count))
        echo "    - User '$uname': $ukey_count kunci terdaftar"
        sudo grep -vE '^\s*#' "$userdir/.ssh/authorized_keys" 2>/dev/null | grep -v '^\s*$' | awk '{printf "      * Type: %-15s Comment: %s\n", $1, $3}' || true
    fi
done
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Cek Proses dari Folder Sementara (/tmp, /dev/shm, /var/tmp)
# ------------------------------------------------------------------------------
echo ""
echo "[3] MEMERIKSA PROSES YANG BERJALAN DARI FOLDER SEMENTARA"
ls -l /proc/*/exe 2>/dev/null | grep -E '(/tmp|/dev/shm|/var/tmp)' > "$TMP_PROCS" || true
PROC_SUSP_COUNT=$(wc -l < "$TMP_PROCS" | tr -d ' ')

if [ "$PROC_SUSP_COUNT" -gt 0 ]; then
    echo "    PERINGATAN: Ditemukan proses berjalan dari direktori temp:"
    cat "$TMP_PROCS" | sed 's/^/    /'
else
    echo "    Status: Tidak ada proses berjalan dari /tmp atau /dev/shm (Bersih)."
fi
echo "======================================================================"

# ==============================================================================
# OUTPUT STATE DATA JSON
# ==============================================================================
echo "###TRIAGE_STATE_START###"
cat <<JSON_EOF
{
  "suspicious_cron_count": $CRON_SUSP_COUNT,
  "suspicious_process_count": $PROC_SUSP_COUNT,
  "root_ssh_keys_count": $ROOT_KEYS_COUNT,
  "total_user_ssh_keys": $TOTAL_USER_KEYS,
  "status": "$([ $((CRON_SUSP_COUNT + PROC_SUSP_COUNT)) -eq 0 ] && echo "CLEAN" || echo "SUSPICIOUS")"
}
JSON_EOF
echo "###TRIAGE_STATE_END###"
