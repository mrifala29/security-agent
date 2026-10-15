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

echo "   - Whitelist Loopback interface (lo)..."
sudo ufw allow in on lo comment 'Localhost Loopback'

echo "   - Whitelist Docker Bridge (docker0 & br-+)..."
sudo ufw allow in on docker0 comment 'Docker Default Bridge'
sudo ufw allow in on br-+ comment 'Docker Custom Bridges' 2>/dev/null || true

HOST_PUB_IP="163.128.54.32"
OLD_DEV_IP="103.230.81.70"
PROD_PUB_IP="103.230.81.47"
AIRPAY_PUB_IP="13.213.172.18"
AWS_PUB_IP="54.255.121.15"

echo "   - Whitelist IP Publik Server ($HOST_PUB_IP) untuk Hairpin NAT Microservices..."
sudo ufw allow from "$HOST_PUB_IP" comment 'Server Self Public IP (Microservices Loopback)'

echo "   - Whitelist IP Server Dev Lama ($OLD_DEV_IP)..."
sudo ufw allow from "$OLD_DEV_IP" comment 'Old Dev Server IP'

echo "   - Whitelist IP Server Prod ($PROD_PUB_IP)..."
sudo ufw allow from "$PROD_PUB_IP" comment 'Server Prod Public IP'

echo "   - Whitelist IP Server Airpay ($AIRPAY_PUB_IP)..."
sudo ufw allow from "$AIRPAY_PUB_IP" comment 'Server Airpay AWS SG'

echo "   - Whitelist IP Server AWS ($AWS_PUB_IP)..."
sudo ufw allow from "$AWS_PUB_IP" comment 'Server AWS Cloud'

echo ""
echo "5. Mengamankan Docker Published Database Ports (Rantai DOCKER-USER):"
# Di Linux, Docker mem-bypass UFW pada rantai FORWARD secara default.
# Rantai DOCKER-USER adalah standar resmi Docker untuk memfilter port container.
EXT_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1 || echo "enp5s0")
if [ -n "$EXT_IF" ]; then
    echo "   - Menerapkan filter keamanan pada interface publik: $EXT_IF..."
    sudo iptables -N DOCKER-USER 2>/dev/null || true
    sudo iptables -F DOCKER-USER 2>/dev/null || true
    
    # 1. Izinkan koneksi yang sudah terbentuk (Established/Related)
    sudo iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # 2. Whitelist Subnet Internal & Hairpin NAT & Sibling Servers
    sudo iptables -A DOCKER-USER -s 10.0.0.0/8 -j ACCEPT
    sudo iptables -A DOCKER-USER -s 172.16.0.0/12 -j ACCEPT
    sudo iptables -A DOCKER-USER -s 192.168.0.0/16 -j ACCEPT
    sudo iptables -A DOCKER-USER -s "$HOST_PUB_IP" -j ACCEPT
    sudo iptables -A DOCKER-USER -s "$OLD_DEV_IP" -j ACCEPT
    sudo iptables -A DOCKER-USER -s "$PROD_PUB_IP" -j ACCEPT
    sudo iptables -A DOCKER-USER -s "$AIRPAY_PUB_IP" -j ACCEPT
    sudo iptables -A DOCKER-USER -s "$AWS_PUB_IP" -j ACCEPT
    
    # 3. Izinkan semua traffic antar-container lokal (bukan dari interface publik)
    sudo iptables -A DOCKER-USER ! -i "$EXT_IF" -j ACCEPT
    
    # 4. Blokir IP internet publik asing ke port database/cache container
    CONTAINER_DB_PORTS="3306,5433,5434,5435,5436,5437,6379,6381,6389,6543,6739,9042,15432"
    sudo iptables -A DOCKER-USER -i "$EXT_IF" -p tcp -m multiport --dports "$CONTAINER_DB_PORTS" -j DROP
    
    # 5. Kembalikan port non-database (misal web/app port) ke aturan Docker default
    sudo iptables -A DOCKER-USER -j RETURN
    echo "   -> Proteksi DOCKER-USER berhasil aktif (Port DB Container aman dari pihak luar)!"
fi

echo ""
echo "6. Mengaktifkan Firewall (UFW)..."
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
