#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/action/backup_databases.sh
# Tahap : ACTION (Pencadangan Data Kritis)
# Fungsi: Melakukan dump seluruh database (PostgreSQL host & Docker containers)
#         serta mencadangkan file docker-compose.yml sebelum port diubah ke privat/firewall diaktifkan.
# ==============================================================================

set -u

echo "======================================================================"
echo "MEMULAI PENCADANGAN DATABASE (DATABASE DUMP & COMPOSE BACKUP)"
echo "======================================================================"

TS=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/db_dumps_${TS}"
sudo mkdir -p "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"

echo "Direktori cadangan: $BACKUP_DIR"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 1. Backup Native Host PostgreSQL
# ------------------------------------------------------------------------------
echo "[1] MEMERIKSA POSTGRESQL NATIVE (HOST)..."
if command -v psql >/dev/null 2>&1 && sudo -u postgres psql -c '\q' >/dev/null 2>&1; then
    echo "    Ditemukan PostgreSQL aktif pada host (port 5432)."
    echo "    Melakukan dump seluruh database (pg_dumpall) + kompresi gzip..."
    HOST_DUMP="$BACKUP_DIR/host_postgresql_all_${TS}.sql.gz"
    if sudo -u postgres pg_dumpall | gzip > "$HOST_DUMP"; then
        DUMP_SIZE=$(du -h "$HOST_DUMP" | awk '{print $1}')
        echo "    BERHASIL: $HOST_DUMP ($DUMP_SIZE)"
    else
        echo "    PERINGATAN: Gagal melakukan dump host postgresql."
    fi
else
    echo "    Tidak ada service PostgreSQL native yang terdeteksi aktif di host."
fi
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Backup Database di Docker Containers
# ------------------------------------------------------------------------------
echo ""
echo "[2] MEMERIKSA DATABASE DI DOCKER CONTAINERS..."
if command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    # Cari container Postgres yang berjalan
    PG_CONTAINERS=$(sudo docker ps --filter "ancestor=postgres" --format "{{.Names}}" 2>/dev/null || true)
    TS_CONTAINERS=$(sudo docker ps --filter "ancestor=timescale" --format "{{.Names}}" 2>/dev/null || true)
    ALL_PG="$PG_CONTAINERS $TS_CONTAINERS"

    for c in $ALL_PG; do
        if [ -n "$c" ]; then
            echo "    -> Menemukan container PostgreSQL: $c"
            C_DUMP="$BACKUP_DIR/docker_${c}_${TS}.sql.gz"
            # Coba pg_dumpall dengan user postgres atau user container
            PG_USER=$(sudo docker inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^POSTGRES_USER=' | cut -d= -f2 || echo "postgres")
            if [ -z "$PG_USER" ]; then PG_USER="postgres"; fi
            
            if sudo docker exec "$c" pg_dumpall -U "$PG_USER" 2>/dev/null | gzip > "$C_DUMP"; then
                D_SIZE=$(du -h "$C_DUMP" | awk '{print $1}')
                echo "       BERHASIL: $C_DUMP ($D_SIZE)"
            else
                rm -f "$C_DUMP"
                echo "       Mencoba pg_dumpall tanpa argumen user..."
                if sudo docker exec "$c" pg_dumpall 2>/dev/null | gzip > "$C_DUMP"; then
                    D_SIZE=$(du -h "$C_DUMP" | awk '{print $1}')
                    echo "       BERHASIL: $C_DUMP ($D_SIZE)"
                else
                    echo "       Gagal dump otomatis container $c (Periksa credential/user container)."
                    rm -f "$C_DUMP"
                fi
            fi
        fi
    done

    # Cari container MySQL / MariaDB yang berjalan
    MYSQL_CONTAINERS=$(sudo docker ps --filter "ancestor=mariadb" --format "{{.Names}}" 2>/dev/null || true)
    ALL_MYSQL="$MYSQL_CONTAINERS $(sudo docker ps --filter "ancestor=mysql" --format "{{.Names}}" 2>/dev/null || true)"

    for m in $ALL_MYSQL; do
        if [ -n "$m" ]; then
            echo "    -> Menemukan container MySQL/MariaDB: $m"
            M_DUMP="$BACKUP_DIR/docker_${m}_${TS}.sql.gz"
            MYSQL_PASS=$(sudo docker inspect "$m" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^MYSQL_ROOT_PASSWORD=' | cut -d= -f2 || echo "")
            if [ -n "$MYSQL_PASS" ]; then
                if sudo docker exec "$m" mysqldump --all-databases -u root -p"$MYSQL_PASS" 2>/dev/null | gzip > "$M_DUMP"; then
                    M_SIZE=$(du -h "$M_DUMP" | awk '{print $1}')
                    echo "       BERHASIL: $M_DUMP ($M_SIZE)"
                fi
            else
                if sudo docker exec "$m" mysqldump --all-databases -u root 2>/dev/null | gzip > "$M_DUMP"; then
                    M_SIZE=$(du -h "$M_DUMP" | awk '{print $1}')
                    echo "       BERHASIL: $M_DUMP ($M_SIZE)"
                fi
            fi
        fi
    done
else
    echo "    Docker tidak terpasang atau daemon tidak aktif."
fi
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Backup File docker-compose.yml & Konfigurasi Port
# ------------------------------------------------------------------------------
echo ""
echo "[3] MENCADANGKAN FILE DOCKER-COMPOSE & PORT MAPPING..."
COMPOSE_BACKUP_DIR="$BACKUP_DIR/compose_configs"
sudo mkdir -p "$COMPOSE_BACKUP_DIR"

COMPOSE_COUNT=0
for f in $(sudo find /home /opt /var/www /root -maxdepth 4 -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null || true); do
    if [ -f "$f" ]; then
        REL_NAME=$(echo "$f" | sed 's|^/||' | tr '/' '_')
        sudo cp -p "$f" "$COMPOSE_BACKUP_DIR/${REL_NAME}"
        COMPOSE_COUNT=$((COMPOSE_COUNT + 1))
    fi
done
echo "    Total file docker-compose yang dicadangkan: $COMPOSE_COUNT file di $COMPOSE_BACKUP_DIR/"
echo "======================================================================"
echo "RINGKASAN CADANGAN DATABASE & KONFIGURASI PORT:"
sudo ls -lh "$BACKUP_DIR"
echo "======================================================================"
echo "Database dan konfigurasi port telah berhasil dicadangkan dengan aman."
echo "Lokasi: $BACKUP_DIR"
echo "======================================================================"
