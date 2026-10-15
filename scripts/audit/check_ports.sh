#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/audit/check_ports.sh
# Tahap : AUDIT (100% Read-Only)
# Fungsi: Memeriksa port publik (0.0.0.0), status firewall, dan koneksi aktif.
# Output:
#   1. Laporan teks bersih ke konsol terminal
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
    ss -antp state established -H 2>/dev/null > "$TMP_ESTAB" || ss -antp state established 2>/dev/null | tail -n +2 > "$TMP_ESTAB"
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

# ==============================================================================
# PROSES LISTENING PORTS & CETAK TABEL
# ==============================================================================
awk -v ufw_stat="$UFW_STATUS" '
BEGIN {
    total_public = 0
    total_local = 0
    total_internal = 0
    total_ports = 0
    crit_count = 0
    other_pub_count = 0
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
    if (ip == "" || ip == "*") ip = "0.0.0.0"

    if (port !~ /^[0-9]+$/) next
    total_ports++

    # Scope Filter
    if (ip ~ /^(127\.|::1|\[::1\])/) {
        total_local++
    } else if (ip ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/) {
        total_internal++
    } else {
        total_public++
        is_critical = 0
        if (port ~ /^(3306|5432|5433|5434|5435|5436|5437|6379|27017|27018|9200|9042|5672)$/ || proc_clean ~ /(postgres|mysql|mariadb|redis|mongo|ferretdb)/) {
            is_critical = 1
        }

        line = sprintf("%-7s %-6s %-15s %-32s", port, proto, ip, proc_clean)
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
    print "RINGKASAN STATUS PORT & FIREWALL"
    print "======================================================================"
    printf "Status Firewall (UFW)          : %s\n", ufw_stat
    printf "Total Port Terbuka ke Publik   : %d port (Akses 0.0.0.0 / *)\n", total_public
    printf "  - Port Sensitif / Database   : %d port (Perlu ditutup/diadjust)\n", crit_count
    printf "  - Port Lainnya (Web/Docker)  : %d port\n", other_pub_count
    printf "Total Port Internal & Localhost: %d port (Aman)\n", (total_internal + total_local)
    print "======================================================================"
    print ""

    if (crit_count > 0) {
        print "[1] PORT SENSITIF / DATABASE YANG TERBUKA KE PUBLIK (0.0.0.0 / *)"
        print "    (Port di bawah ini bisa diakses langsung dari seluruh internet)"
        print "----------------------------------------------------------------------"
        printf "%-7s %-6s %-15s %-32s\n", "PORT", "PROTO", "BIND IP", "PROSES / SERVICE"
        print "----------------------------------------------------------------------"
        for (i = 1; i <= crit_count; i++) {
            print crit_list[i]
        }
        print "----------------------------------------------------------------------"
        print ""
    }

    if (other_pub_count > 0) {
        print "[2] PORT LAINNYA YANG TERBUKA KE PUBLIK (0.0.0.0 / *)"
        print "----------------------------------------------------------------------"
        printf "%-7s %-6s %-15s %-32s\n", "PORT", "PROTO", "BIND IP", "PROSES / SERVICE"
        print "----------------------------------------------------------------------"
        for (i = 1; i <= other_pub_count; i++) {
            print other_pub_list[i]
        }
        print "----------------------------------------------------------------------"
        print ""
    }

    # Output State Port untuk JSON
    printf "###PORT_STATE_META###\n"
    printf "{\"total_public\":%d,\"crit_count\":%d,\"other_count\":%d,\"internal_count\":%d,\"local_count\":%d,\"firewall\":\"%s\"}\n", total_public, crit_count, other_pub_count, total_internal, total_local, ufw_stat
    printf "###CRIT_PORTS_JSON###\n["
    for (i = 1; i <= crit_count; i++) {
        printf "%s%s", crit_json[i], (i == crit_count ? "" : ",")
    }
    printf "]\n"
}
' "$TMP_LISTEN"

# ==============================================================================
# PROSES KONEKSI AKTIF DARI IP PUBLIK & INTERNAL
# ==============================================================================
awk '
BEGIN {
    total_estab = 0
    total_local = 0
    total_internal = 0
    total_public_conn = 0
    pub_ip_count = 0
    int_conn_count = 0
}
{
    local_part = $3
    remote_part = $4
    proc_info = $5

    proc_name = "-"
    if (match(proc_info, /"([^"]+)"/, m)) {
        proc_name = m[1]
    }

    split(local_part, lparts, ":")
    lport = lparts[length(lparts)]

    split(remote_part, rparts, ":")
    rport = rparts[length(rparts)]
    sub(":" rport "$", "", remote_part)
    rip = remote_part
    gsub(/\[|\]/, "", rip)
    sub(/^::ffff:/, "", rip)

    if (rip == "" || lport !~ /^[0-9]+$/) next
    total_estab++

    if (rip ~ /^127\./ || rip == "::1") {
        total_local++
    } else if (rip ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/) {
        total_internal++
        ikey = sprintf("%s|%s", rip, lport)
        if (int_counts[ikey] == 0) {
            int_conn_count++
            int_keys[int_conn_count] = ikey
        }
        int_counts[ikey]++
    } else {
        total_public_conn++
        key = sprintf("%-18s | %s", rip, proc_name)
        if (public_counts[key] == 0) {
            pub_ip_count++
            pub_keys[pub_ip_count] = key
        }
        public_counts[key]++
    }
}
END {
    print "[3] KONEKSI AKTIF DARI IP PUBLIK (INTERNET LUAR)"
    print "----------------------------------------------------------------------"
    if (total_public_conn > 0) {
        printf "%-18s   %-20s   %s\n", "IP SUMBER", "PROSES / SERVICE", "JUMLAH KONEKSI"
        print "----------------------------------------------------------------------"
        for (i = 1; i <= pub_ip_count; i++) {
            k = pub_keys[i]
            split(k, kparts, " \\| ")
            ip_src = kparts[1]
            p_svc = kparts[2]
            printf "%-18s   %-20s   %d koneksi\n", ip_src, p_svc, public_counts[k]
        }
    } else {
        print "Tidak ada koneksi dari IP publik luar saat ini."
    }
    print "----------------------------------------------------------------------"
    printf "Catatan: Koneksi internal lainnya: %d koneksi VPC/Subnet, %d koneksi Localhost.\n", total_internal, total_local
    print "======================================================================"

    # Output State Koneksi Internal (karena ini yang perlu di-whitelist di Action!)
    printf "###INTERNAL_WHITELIST_JSON###\n["
    for (i = 1; i <= int_conn_count; i++) {
        k = int_keys[i]
        split(k, parts, "|")
        printf "{\"ip\":\"%s\",\"target_port\":%s,\"connections\":%d}%s", parts[1], parts[2], int_counts[k], (i == int_conn_count ? "" : ",")
    }
    printf "]\n"
}
' "$TMP_ESTAB"
