#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/backup.sh
# Tahap : ACTION (Pencadangan Penuh Sebelum Perubahan)
# Fungsi: 
#   1. Mencadangkan konfigurasi sensitif OS (/etc/ssh, ufw, cron, sudoers)
#   2. Men-dump database (PostgreSQL host & Docker)
#   3. Mencadangkan file docker-compose.yml & port mapping
# Sifat : Non-destruktif (Hanya membaca dan menyalin data)
# ==============================================================================

set -u

TS=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/security_agent_backup_${TS}"
sudo mkdir -p "$BACKUP_DIR/os_configs" "$BACKUP_DIR/databases" "$BACKUP_DIR/compose_configs"
sudo chmod 700 "$BACKUP_DIR"

echo "======================================================================"
echo "MEMULAI PENCADANGAN LENGKAP SISTEM & DATABASE"
echo "Direktori Cadangan: $BACKUP_DIR"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Backup Konfigurasi OS
# ------------------------------------------------------------------------------
echo "[1] MENCADANGKAN KONFIGURASI SISTEM OPERASI (OS)..."
if [ -d /etc/ssh ]; then sudo cp -rp /etc/ssh "$BACKUP_DIR/os_configs/ssh"; fi
if [ -f /etc/passwd ]; then sudo cp -p /etc/passwd "$BACKUP_DIR/os_configs/passwd"; fi
if [ -f /etc/group ]; then sudo cp -p /etc/group "$BACKUP_DIR/os_configs/group"; fi
if [ -f /etc/sudoers ]; then sudo cp -p /etc/sudoers "$BACKUP_DIR/os_configs/sudoers"; fi
if [ -d /etc/sudoers.d ]; then sudo cp -rp /etc/sudoers.d "$BACKUP_DIR/os_configs/sudoers.d"; fi
if [ -f /etc/crontab ]; then sudo cp -p /etc/crontab "$BACKUP_DIR/os_configs/crontab"; fi
if [ -d /etc/cron.d ]; then sudo cp -rp /etc/cron.d "$BACKUP_DIR/os_configs/cron.d"; fi
if [ -d /var/spool/cron/crontabs ]; then sudo cp -rp /var/spool/cron/crontabs "$BACKUP_DIR/os_configs/user_crontabs"; fi
if [ -d /etc/ufw ]; then sudo cp -rp /etc/ufw "$BACKUP_DIR/os_configs/ufw"; fi
echo "    Status: File SSH, UFW, Cron, dan Sudoers berhasil dicadangkan."
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Dump Database (PostgreSQL Host & Docker)
# ------------------------------------------------------------------------------
echo ""
echo "[2] MENCADANGKAN DATABASE (DUMP)..."
# Host Postgres
if command -v psql >/dev/null 2>&1 && sudo -u postgres psql -c '\q' >/dev/null 2>&1; then
    echo "    - Ditemukan PostgreSQL aktif pada host (port 5432)."
    echo "      Melakukan dump seluruh database (pg_dumpall)..."
    HOST_DUMP="$BACKUP_DIR/databases/host_postgresql_all_${TS}.sql.gz"
    if sudo -u postgres pg_dumpall | gzip > "$HOST_DUMP"; then
        DUMP_SIZE=$(du -h "$HOST_DUMP" | awk '{print $1}')
        echo "      BERHASIL: $HOST_DUMP ($DUMP_SIZE)"
    fi
fi

# Docker Database Containers
if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    PG_CONTAINERS=$(sudo docker ps --filter "ancestor=postgres" --format "{{.Names}}" 2>/dev/null || true)
    TS_CONTAINERS=$(sudo docker ps --filter "ancestor=timescale" --format "{{.Names}}" 2>/dev/null || true)
    for c in $PG_CONTAINERS $TS_CONTAINERS; do
        if [ -n "$c" ]; then
            C_DUMP="$BACKUP_DIR/databases/docker_${c}_${TS}.sql.gz"
            PG_USER=$(sudo docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^POSTGRES_USER=' | cut -d= -f2 || echo "postgres")
            if [ -z "$PG_USER" ]; then PG_USER="postgres"; fi
            if sudo docker exec "$c" pg_dumpall -U "$PG_USER" 2>/dev/null | gzip > "$C_DUMP"; then
                D_SIZE=$(du -h "$C_DUMP" | awk '{print $1}')
                echo "    - Docker Postgres '$c': $D_SIZE"
            fi
        fi
    done
fi
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Backup File docker-compose.yml
# ------------------------------------------------------------------------------
echo ""
echo "[3] MENCADANGKAN FILE DOCKER-COMPOSE..."
COMPOSE_COUNT=0
for f in $(sudo find /home /opt /var/www /root -maxdepth 4 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null || true); do
    if [ -f "$f" ]; then
        REL_NAME=$(echo "$f" | sed 's|^/||' | tr '/' '_')
        sudo cp -p "$f" "$BACKUP_DIR/compose_configs/${REL_NAME}"
        COMPOSE_COUNT=$((COMPOSE_COUNT + 1))
    fi
done
echo "    Total file docker-compose dicadangkan: $COMPOSE_COUNT file."
echo "======================================================================"
echo "PENCADANGAN SELESAI DENGAN AMAN!"
echo "Lokasi cadangan di server: $BACKUP_DIR"
echo "======================================================================"
