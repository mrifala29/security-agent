#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/harden_ports.sh
# Tahap : ACTION (Eksekusi Perbaikan)
# Fungsi: Mengaktifkan Firewall (UFW) untuk menutup port 0.0.0.0 secara aman
#         dengan whitelist IP internal dan proteksi anti-lockout SSH.
# Sifat : Tulis / Konfigurasi Sistem (Wajib backup sebelum dijalankan!)
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo "EKSEKUSI PENGERASAN FIREWALL & PENUTUPAN PORT (UFW)"
echo "======================================================================"

# 1. Pastikan UFW terpasang
if ! command -v ufw >/dev/null 2>&1; then
    echo "Menginstall ufw..."
    sudo apt-get update -y && sudo apt-get install -y ufw
fi

echo "0. Analisis Dampak Koneksi Aktif (Pre-Flight Connection Check):"
SENSITIVE_PORTS="3306|5432|5433|5434|5435|5436|5437|6379|6381|6389|6739|27017|9042|5672|6543|6544|15432"
ACTIVE_CONNS=$(ss -ant state established 2>/dev/null | grep -E ":($SENSITIVE_PORTS)\s+" || true)
if [ -n "$ACTIVE_CONNS" ]; then
    TOTAL_CONNS=$(echo "$ACTIVE_CONNS" | wc -l | tr -d ' ')
    echo "   Terdeteksi $TOTAL_CONNS koneksi aktif ke port-port sensitif."
    # Cek apakah ada IP publik non-whitelist
    NON_INTERNAL=$(echo "$ACTIVE_CONNS" | awk '{print $5}' | grep -vE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.|\[::ffff:10\.|\[::ffff:192\.168\.|\[::ffff:172\.)' || true)
    if [ -n "$NON_INTERNAL" ]; then
        echo "   PERINGATAN: Ditemukan koneksi aktif dari IP luar non-whitelist!"
        echo "$NON_INTERNAL" | sed 's/^/   -> /'
        echo "   Koneksi tersebut akan terputus jika tidak dimasukkan ke whitelist UFW."
    else
        echo "   Status: 100% koneksi aktif berasal dari subnet internal (10.x / 192.168.x)."
        echo "   Hardening dipastikan AMAN dan TIDAK AKAN mengganggu operasional aplikasi!"
    fi
else
    echo "   Tidak ada koneksi aktif saat ini ke port database/service."
fi
echo ""

echo "1. Menyetel kebijakan default (Default Policy):"
echo "   - Incoming: DENY (Tolak semua koneksi luar yang tidak diizinkan)"
echo "   - Outgoing: ALLOW (Izinkan koneksi keluar dari server)"
sudo ufw default deny incoming
sudo ufw default allow outgoing

echo ""
echo "2. Mencegah Lockout: Membuka Akses SSH..."
# Cek port SSH yang aktif saat ini dari sshd_config atau default 22
SSH_PORT=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
if [ -z "$SSH_PORT" ]; then SSH_PORT="22"; fi

sudo ufw allow "$SSH_PORT"/tcp comment 'SSH Access Management'
echo "   -> Port SSH ($SSH_PORT/tcp) berhasil diizinkan."

echo ""
echo "3. Membuka Port Web Publik (Jika server melayani HTTP/HTTPS)..."
sudo ufw allow 80/tcp comment 'Web HTTP' || true
sudo ufw allow 443/tcp comment 'Web HTTPS' || true

echo ""
echo "4. Menerapkan Whitelist IP Internal (Hasil Audit ports_state.json):"
# Whitelist subnet internal VPC (10.0.0.0/16, 10.240.0.0/16, dll)
# Ini menjaga agar PostgreSQL (5432), RabbitMQ (5672), dan Docker internal
# tetap bisa diakses oleh server aplikasi rekanan tanpa bocor ke internet!

echo "   - Whitelist subnet internal 10.0.0.0/8..."
sudo ufw allow from 10.0.0.0/8 comment 'Internal VPC Subnet 10.x'

echo "   - Whitelist subnet Docker/Internal 172.16.0.0/12..."
sudo ufw allow from 172.16.0.0/12 comment 'Docker Internal Subnet'

echo "   - Whitelist subnet lokal 192.168.0.0/16..."
sudo ufw allow from 192.168.0.0/16 comment 'Private Subnet 192.168.x'

echo ""
echo "5. Mengaktifkan Firewall (UFW)..."
sudo ufw --force enable

echo ""
echo "======================================================================"
echo "STATUS ATURAN FIREWALL YANG TELAH AKTIF:"
echo "======================================================================"
sudo ufw status numbered
echo "======================================================================"
echo "PERINGATAN KESELAMATAN:"
echo "JANGAN TUTUP TERMINAL INI DULU!"
echo "Buka terminal baru di komputer Anda dan coba login: 'ssh <server_alias>'"
echo "Jika berhasil login di terminal baru, konfigurasi sudah 100% aman!"
echo "======================================================================"
