#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/audit/check_ports.sh
# Tahap : AUDIT (100% Read-Only)
# Fungsi: 
#   1. Memeriksa port sensitif/database yang terbuka ke publik (0.0.0.0 / *)
#   2. Menganalisis dampak koneksi aktif (Port Impact Check)
#   3. Memverifikasi apakah penutupan port akan memutus aplikasi/user
# Output:
#   1. Laporan gabungan yang bersih ke konsol terminal
#   2. Blok JSON State (untuk memori tahap Action)
# ==============================================================================

set -u

TMP_LISTEN=$(mktemp)
TMP_ESTAB=$(mktemp)
trap 'rm -f "$TMP_LISTEN" "$TMP_ESTAB"' EXIT

# 1. Ambil data listening ports
if command -v ss >/dev/null 2>&1; then
    ss -tulpn -H 2>/dev/null > "$TMP_LISTEN" || ss -tulpn 2>/dev/null | tail -n +2 > "$TMP_LISTEN"
else
    netstat -tulpn 2>/dev/null | grep -E 'LISTEN|udp' > "$TMP_LISTEN" || true
fi

# 2. Ambil data koneksi aktif (established)
if command -v ss >/dev/null 2>&1; then
    ss -ant state established -H 2>/dev/null > "$TMP_ESTAB" || ss -ant state established 2>/dev/null | tail -n +2 > "$TMP_ESTAB"
fi

# 3. Cek Status Firewall
UFW_STATUS="TIDAK TERPASANG"
if command -v ufw >/dev/null 2>&1; then
    UFW_RAW=$(sudo ufw status 2>/dev/null | head -n 1 || echo "unknown")
    if echo "$UFW_RAW" | grep -qi "active" && ! echo "$UFW_RAW" | grep -qi "inactive"; then
        UFW_STATUS="AKTIF"
    else
        UFW_STATUS="NONAKTIF (INACTIVE)"
    fi
fi

# 4. Ambil pemetaan port Docker ke nama container
TMP_DOCKER=$(mktemp)
if command -v docker >/dev/null 2>&1; then
    docker ps --format '{{.Ports}}\t{{.Names}}' 2>/dev/null > "$TMP_DOCKER" || true
fi

# ==============================================================================
# PROSES LISTENING PORTS & DETEKSI PORT SENSITIF
# ==============================================================================
CRIT_PORTS_TEMP=$(mktemp)
META_TEMP=$(mktemp)
trap 'rm -f "$TMP_LISTEN" "$TMP_ESTAB" "$CRIT_PORTS_TEMP" "$META_TEMP" "$TMP_DOCKER"' EXIT

awk -v ufw_stat="$UFW_STATUS" -v crit_file="$CRIT_PORTS_TEMP" -v meta_file="$META_TEMP" -v docker_file="$TMP_DOCKER" '
BEGIN {
    total_public = 0
    total_local = 0
    total_internal = 0
    total_ports = 0
    crit_count = 0
    other_pub_count = 0

    if (docker_file != "") {
        while ((getline dline < docker_file) > 0) {
            split(dline, dparts, "\t")
            ports_str = dparts[1]
            cname = dparts[2]
            pcount = split(ports_str, ptokens, ",")
            for (p = 1; p <= pcount; p++) {
                if (match(ptokens[p], /:([0-9]+)->/, pm)) {
                    docker_map[pm[1]] = cname
                }
            }
        }
        close(docker_file)
    }
}
{
    proto = $1
    addr_port = $5
    process = $7
    if (process == "") process = $6

    proc_clean = "-"
    if (match(process, /users:\(\("([^"]+)",pid=([0-9]+)/, m)) {
        proc_clean = m[1] " (pid:" m[2] ")"
    } else if (match(process, /"([^"]+)"/, m)) {
        proc_clean = m[1]
    }

    split(addr_port, parts, ":")
    port = parts[length(parts)]
    sub(":" port "$", "", addr_port)
    ip = addr_port

    if (proc_clean ~ /docker-proxy/ && (port in docker_map)) {
        proc_clean = "docker: " docker_map[port]
    }
    if (ip == "" || ip == "*") ip = "0.0.0.0"

    if (port !~ /^[0-9]+$/) next
    total_ports++

    # Filter Scope IP
    if (ip ~ /^(127\.|::1|\[::1\])/) {
        total_local++
    } else if (ip ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/) {
        total_internal++
    } else {
        total_public++
        is_critical = 0
        if (port ~ /^(3306|5432|5433|5434|5435|5436|5437|6379|6381|6389|6739|27017|27018|9200|9042|5672|6543|6544|15432)$/ || proc_clean ~ /(postgres|mysql|mariadb|redis|mongo|ferretdb|timescale|scylla|beam\.smp)/) {
            is_critical = 1
        }

        line = sprintf("%-7s %-6s %-15s %-38s", port, proto, ip, proc_clean)
        json_item = sprintf("{\"port\":%s,\"proto\":\"%s\",\"bind\":\"%s\",\"process\":\"%s\"}", port, proto, ip, proc_clean)

        if (is_critical == 1) {
            crit_count++
            crit_list[crit_count] = line
            crit_json[crit_count] = json_item
        } else {
            other_pub_count++
            other_pub_list[other_pub_count] = line
            other_json[other_pub_count] = json_item
        }
    }
}
END {
    print "======================================================================"
    print "AUDIT PORT SENSITIF & ANALISIS DAMPAK (PORT & IMPACT AUDIT)"
    print "======================================================================"
    printf "Status Firewall (UFW)          : %s\n", ufw_stat
    printf "Total Port Terbuka ke Publik   : %d port (Akses 0.0.0.0 / *)\n", total_public
    printf "  - Port Sensitif / Database   : %d port (Celah keamanan yang perlu ditutup)\n", crit_count
    printf "  - Port Lainnya (Web / Apps)  : %d port\n", other_pub_count
    printf "Total Port Internal & Localhost: %d port (Aman)\n", (total_internal + total_local)
    print "======================================================================"
    print ""

    if (crit_count > 0) {
        print "[1] PORT SENSITIF / DATABASE TERBUKA KE PUBLIK (0.0.0.0 / *)"
        print "    (Port di bawah ini dapat diakses langsung dari seluruh internet jika UFW nonaktif)"
        print "----------------------------------------------------------------------"
        printf "%-7s %-6s %-15s %-38s\n", "PORT", "PROTO", "BIND IP", "PROSES / SERVICE (CONTAINER)"
        print "----------------------------------------------------------------------"
        for (i = 1; i <= crit_count; i++) {
            print crit_list[i]
        }
        print "----------------------------------------------------------------------"
        printf "INFO: %d port web/microservice lainnya sengaja disembunyikan agar\n", other_pub_count
        print "      tampilan ringkas & fokus pada celah keamanan database/service."
        print "----------------------------------------------------------------------"
        print ""
    }

    # Simpan Meta & JSON ke file sementara
    printf "{\"total_public\":%d,\"crit_count\":%d,\"other_count\":%d,\"internal_count\":%d,\"local_count\":%d,\"firewall\":\"%s\"}\n", total_public, crit_count, other_pub_count, total_internal, total_local, ufw_stat > meta_file

    printf "[" > crit_file
    for (i = 1; i <= crit_count; i++) {
        printf "%s%s", crit_json[i], (i == crit_count ? "" : ",") > crit_file
    }
    printf "]\n" > crit_file
}
' "$TMP_LISTEN"

# ==============================================================================
# PROSES ANALISIS DAMPAK KONEKSI AKTIF (PORT IMPACT CHECK)
# ==============================================================================
echo "[2] ANALISIS DAMPAK KONEKSI AKTIF KE PORT SENSITIF TERSEBUT"
echo "    (Mendeteksi apakah penutupan port akan mengganggu aplikasi rekanan/user)"
echo "----------------------------------------------------------------------"

SENSITIVE_PORTS="3306|5432|5433|5434|5435|5436|5437|6379|6381|6389|6739|27017|9042|5672|6543|6544|15432"
RAW_SENS_CONNS=$(grep -E ":($SENSITIVE_PORTS)\s+" "$TMP_ESTAB" || true)

INT_WHITELIST_TEMP=$(mktemp)
trap 'rm -f "$TMP_LISTEN" "$TMP_ESTAB" "$CRIT_PORTS_TEMP" "$META_TEMP" "$INT_WHITELIST_TEMP"' EXIT

if [ -z "$RAW_SENS_CONNS" ]; then
    echo "Status: Tidak ada koneksi aktif ke port-port database/service saat ini."
    echo "Dampak: Penutupan port 100% AMAN (Nol gangguan)."
    echo "----------------------------------------------------------------------"
    echo "[]" > "$INT_WHITELIST_TEMP"
else
    awk -v int_file="$INT_WHITELIST_TEMP" '
    BEGIN {
        total_conns = 0
        safe_conns = 0
        warn_conns = 0
        pair_count = 0
    }
    {
        local_part = $3
        peer_part = $4

        split(local_part, lparts, ":")
        lport = lparts[length(lparts)]

        # Hanya ambil jika lport adalah port listening sensitif (bukan ephemeral outgoing)
        if (lport !~ /^(3306|5432|5433|5434|5435|5436|5437|6379|6381|6389|6739|27017|9042|5672|6543|6544|15432|9000|9001)$/) {
            next
        }

        rip = peer_part
        gsub(/\[|\]/, "", rip)
        sub(/^::ffff:/, "", rip)
        sub(/:[0-9]+$/, "", rip)

        if (rip == "") next
        total_conns++

        key = sprintf("%s|%s", lport, rip)
        if (counts[key] == 0) {
            pair_count++
            pairs[pair_count] = key
        }
        counts[key]++
    }
    END {
        if (pair_count == 0) {
            print "  Status : Tidak ada koneksi aktif dari luar ke port listening database."
            print "  Dampak : Penutupan port 100% AMAN (Nol gangguan)."
            print "----------------------------------------------------------------------"
            printf "[]" > int_file
            exit 0
        }

        printf "  %-7s  %-18s  %-20s  %-11s  %s\n", "PORT", "LAYANAN (SERVICE)", "REMOTE IP", "KONEKSI", "STATUS DAMPAK HARDENING"
        printf "  %-7s  %-18s  %-20s  %-11s  %s\n", "-------", "------------------", "--------------------", "-----------", "-----------------------"

        json_int_count = 0

        for (i = 1; i <= pair_count; i++) {
            k = pairs[i]
            split(k, parts, "|")
            port = parts[1]
            ip = parts[2]
            cnt = counts[k]

            # Nama Layanan
            svc = "Unknown"
            if (port ~ /^(5432|5433|5434|5435|5436|5437|15432)$/) svc = "PostgreSQL"
            else if (port ~ /^(6543|6544)$/) svc = "TimescaleDB"
            else if (port == "3306") svc = "MySQL / MariaDB"
            else if (port ~ /^(6379|6381|6389|6739)$/) svc = "Redis"
            else if (port ~ /^(5672|15672|25672)$/) svc = "RabbitMQ"
            else if (port ~ /^(27017|27018)$/) svc = "FerretDB / Mongo"
            else if (port == "9042") svc = "ScyllaDB"
            else if (port == "9000" || port == "9001") svc = "MinIO Storage"

            is_safe = 0
            # Aman jika IP berasal dari VPC (10.x, 192.168.x), Docker (172.16-31.x), atau Localhost (127.x)
            if (ip ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|127\.)/) {
                is_safe = 1
                safe_conns += cnt
                status_text = "AMAN (Masuk Whitelist VPC/Subnet)"

                json_int_count++
                json_items[json_int_count] = sprintf("{\"ip\":\"%s\",\"target_port\":%s,\"connections\":%d}", ip, port, cnt)
            } else {
                warn_conns += cnt
                status_text = "PERINGATAN (IP Publik - Akan Terputus!)"
            }

            printf "  %-7s  %-18s  %-20s  %-11s  %s\n", port, svc, ip, (cnt " sess"), status_text
        }

        print "----------------------------------------------------------------------"
        print ""
        print "[3] KESIMPULAN HASIL AUDIT PORT & DAMPAK:"
        if (warn_conns > 0) {
            printf "    KESIMPULAN: PERINGATAN! Ditemukan %d koneksi dari IP luar publik.\n", warn_conns
            print "    TINDAKAN  : Pastikan IP publik tersebut didaftarkan ke whitelist UFW"
            print "                sebelum mengaktifkan firewall, atau pindahkan ke SSH Tunnel."
        } else {
            printf "    KESIMPULAN: 100%% AMAN! Seluruh koneksi aktif (%d koneksi) berasal dari\n", total_conns
            print "                jaringan internal VPC (10.0.0.0/8 & 192.168.0.0/16)."
            print "    DAMPAK    : Menerapkan harden_ports TIDAK AKAN mengganggu aplikasi yang berjalan!"
        }
        print "======================================================================"

        # Output State Koneksi Internal untuk Memori JSON
        printf "[" > int_file
        for (i = 1; i <= json_int_count; i++) {
            printf "%s%s", json_items[i], (i == json_int_count ? "" : ",") > int_file
        }
        printf "]\n" > int_file
    }
    ' <<< "$RAW_SENS_CONNS"
fi

# ==============================================================================
# OUTPUT STATE DATA UNTUK RUNNER CLI (Ditaruh paling bawah)
# ==============================================================================
echo "###PORT_STATE_META###"
cat "$META_TEMP"
echo "###CRIT_PORTS_JSON###"
cat "$CRIT_PORTS_TEMP"
echo "###INTERNAL_WHITELIST_JSON###"
cat "$INT_WHITELIST_TEMP"
