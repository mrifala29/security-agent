#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/audit/check_port_impact.sh
# Tahap : AUDIT & PRE-FLIGHT CHECK (100% Read-Only)
# Fungsi: Memeriksa dampak koneksi aktif sebelum menerapkan firewall/harden_ports.
#         Mendeteksi apakah penutupan port akan mengganggu aplikasi/user yang terhubung.
# ==============================================================================

set -u

echo "======================================================================"
echo "ANALISIS DAMPAK KONEKSI PORT (PRE-FLIGHT IMPACT CHECK)"
echo "======================================================================"

SENSITIVE_PORTS="3306|5432|5433|5434|5435|5436|5437|6379|6381|6389|6739|27017|9042|5672|6543|6544|15432"

RAW_CONNS=$(mktemp)
trap 'rm -f "$RAW_CONNS"' EXIT

# Ambil semua koneksi TCP ESTABLISHED ke port sensitif
ss -ant state established 2>/dev/null | grep -E ":($SENSITIVE_PORTS)\s+" > "$RAW_CONNS" || true

TOTAL_CONNS=$(wc -l < "$RAW_CONNS" | tr -d ' ')

echo "[1] TOTAL KONEKSI AKTIF KE PORT SENSITIF: $TOTAL_CONNS koneksi"
echo "----------------------------------------------------------------------"

if [ "$TOTAL_CONNS" -eq 0 ]; then
    echo "    Status: Tidak ada koneksi aktif ke port-port database/service saat ini."
    echo "    Dampak: Penerapan firewall/harden_ports 100% AMAN (Nol gangguan)."
    echo "======================================================================"
    exit 0
fi

# Parsing dan kelompokkan berdasarkan Remote IP dan Port Tujuan
echo "DAFTAR KONEKSI AKTIF & EVALUASI DAMPAK HARDENING:"
printf "  %-7s  %-22s  %-12s  %s\n" "PORT" "REMOTE IP" "TOTAL KONEKSI" "STATUS DAMPAK HARDEN_PORTS"
printf "  %-7s  %-22s  %-12s  %s\n" "-------" "----------------------" "------------" "--------------------------"

WARNING_COUNT=0
SAFE_COUNT=0

# Ekstrak remote IP dan local port
# Format ss output: Recv-Q Send-Q Local:Port Peer:Port
awk '{print $3, $4}' "$RAW_CONNS" | while read -r local_addr peer_addr; do
    # Bersihkan port lokal (ambil setelah titik dua terakhir)
    lport=$(echo "$local_addr" | awk -F: '{print $NF}')
    # Bersihkan IP remote dari format ipv4 / ipv6 mapped ipv4
    rip=$(echo "$peer_addr" | sed -E 's/.*:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+/\1/' | sed -E 's/\[::ffff:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\]:[0-9]+/\1/' | sed -E 's/:[0-9]+$//' | tr -d '[]')
    if [ -n "$rip" ] && [ -n "$lport" ]; then
        echo "$lport $rip"
    fi
done | sort | uniq -c | while read -r count lport rip; do
    # Evaluasi apakah IP ini masuk dalam Whitelist Internal (10.x, 172.16-31.x, 192.168.x, 127.x)
    is_safe="no"
    if [[ "$rip" =~ ^10\. ]] || [[ "$rip" =~ ^192\.168\. ]] || [[ "$rip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$rip" =~ ^127\. ]]; then
        is_safe="yes"
    fi

    if [ "$is_safe" == "yes" ]; then
        printf "  %-7s  %-22s  %-12s  %s\n" "$lport" "$rip" "$count session" "AMAN (Termasuk Whitelist Internal)"
    else
        printf "  %-7s  %-22s  %-12s  %s\n" "$lport" "$rip" "$count session" "PERINGATAN (IP Publik - Akan Terputus!)"
        echo "WARN_FOUND" >> "$RAW_CONNS.warn"
    fi
done

echo "----------------------------------------------------------------------"
echo ""
echo "[2] KESIMPULAN ANALISIS DAMPAK:"

if [ -f "$RAW_CONNS.warn" ]; then
    WARN_NUM=$(wc -l < "$RAW_CONNS.warn" | tr -d ' ')
    rm -f "$RAW_CONNS.warn"
    echo "    KESIMPULAN: PERINGATAN! Ditemukan $WARN_NUM IP eksternal/publik yang aktif terhubung."
    echo "    TINDAKAN  : Jangan langsung aktifkan firewall tanpa mendaftarkan IP publik tersebut"
    echo "                ke daftar whitelist UFW, atau pindahkan akses mereka ke VPN / SSH Tunnel."
else
    echo "    KESIMPULAN: 100% AMAN! Seluruh koneksi aktif ($TOTAL_CONNS koneksi) berasal dari"
    echo "                jaringan internal VPC (10.0.0.0/8 & 192.168.0.0/16)."
    echo "    DAMPAK    : Menerapkan harden_ports TIDAK AKAN mengganggu atau memutus sistem aplikasi!"
fi

echo "======================================================================"
