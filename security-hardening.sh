#!/usr/bin/env bash
# ==============================================================================
# Security Hardening CLI: security-hardening.sh
# ==============================================================================
# Menjalankan seluruh siklus keamanan (Audit, Action, Evaluasi) ke server via SSH.
#
# Penggunaan:
#   1. Jalankan audit full (semua cek audit):
#      ./security-hardening.sh <server_alias> audit
#
#   2. Jalankan skrip spesifik:
#      ./security-hardening.sh <server_alias> <script_name>
#
# Contoh:
#   ./security-hardening.sh server-dev audit
#   ./security-hardening.sh server-dev check_ports
#   ./security-hardening.sh server-dev backup_configs
#   ./security-hardening.sh server-dev harden_ports
#   ./security-hardening.sh server-dev verify_ports
# ==============================================================================

set -euo pipefail

# 1. Pastikan file .env ada
if [ ! -f .env ]; then
    echo "Error: File .env tidak ditemukan di $(pwd)."
    exit 1
fi

source .env

# 2. Cek argumen
SERVER="${1:-}"
ACTION_TARGET="${2:-}"

if [ -z "$SERVER" ]; then
    echo "======================================================================"
    echo "SECURITY HARDENING CLI"
    echo "======================================================================"
    echo "Cara pakai:"
    echo "  ./security-hardening.sh <server_alias> <perintah_atau_skrip>"
    echo ""
    echo "Mode Otomatis:"
    echo "  audit            : Jalankan AUDIT FULL (semua cek: ports, triage, ssh)"
    echo ""
    echo "Mode Per Skrip:"
    echo "  [AUDIT]"
    echo "    check_ports           : Cek port publik 0.0.0.0 & IP aktif"
    echo "    check_triage          : Cek sisa cron job, ssh key asing, proses /tmp"
    echo "    check_ssh_users       : Cek status config SSH & daftar akun"
    echo ""
    echo "  [ACTION]"
    echo "    backup_configs        : Buat backup konfigurasi sensitif di server"
    echo "    harden_ports          : Terapkan UFW default deny & whitelist IP internal"
    echo "    create_developer_user : Buat akun user developer baru dengan SSH key"
    echo ""
    echo "  [EVALUASI]"
    echo "    verify_ports          : Validasi apakah port berhasil diamankan"
    echo "======================================================================"
    exit 1
fi

# 3. Cari password dari .env
VAR_NAME="SSH_$(echo "$SERVER" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
PASS="${!VAR_NAME:-}"

if [ -z "$PASS" ]; then
    echo "Error: Variabel password '$VAR_NAME' tidak ditemukan di .env untuk host '$SERVER'."
    exit 1
fi

# ==============================================================================
# FUNGSI EKSEKUTOR SKRIP
# ==============================================================================
execute_single_script() {
    local s_name="$1"
    local s_file=""
    local stage=""

    for s in audit action evaluasi; do
        if [ -f "scripts/${s}/${s_name}.sh" ]; then
            s_file="scripts/${s}/${s_name}.sh"
            stage="$s"
            break
        elif [ -f "scripts/${s}/${s_name}" ]; then
            s_file="scripts/${s}/${s_name}"
            stage="$s"
            break
        fi
    done

    if [ -z "$s_file" ]; then
        echo "Error: Skrip '$s_name' tidak ditemukan di scripts/{audit,action,evaluasi}."
        exit 1
    fi

    local out_dir="server/${SERVER}/${stage}"
    mkdir -p "$out_dir"

    local ts
    ts=$(date +"%Y%m%d_%H%M%S")
    local raw_tmp
    raw_tmp=$(mktemp)
    local log_file="${out_dir}/${s_name}_${ts}.log"

    echo "======================================================================"
    echo "Menjalankan [$stage] '$s_file' ke '$SERVER' ..."
    echo "Log: $log_file"
    echo "======================================================================"

    sshpass -p "$PASS" ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new "$SERVER" "sudo -S bash -s" <<EOF > "$raw_tmp" 2>&1
$PASS
$(cat "$s_file")
EOF

    # Bersihkan prompt sudo baris pertama
    sed -i '' '1{/^\[sudo\] password for /d;}' "$raw_tmp" 2>/dev/null || true

    # Pisahkan laporan untuk konsol vs state data JSON (jika ada marker)
    if grep -q "###PORT_STATE_META###" "$raw_tmp"; then
        sed '/###PORT_STATE_META###/,$d' "$raw_tmp" | tee "$log_file"

        local meta crit_ports int_whitelist state_json
        meta=$(grep -A 1 "###PORT_STATE_META###" "$raw_tmp" | tail -n 1)
        crit_ports=$(grep -A 1 "###CRIT_PORTS_JSON###" "$raw_tmp" | tail -n 1)
        int_whitelist=$(grep -A 1 "###INTERNAL_WHITELIST_JSON###" "$raw_tmp" | tail -n 1)

        state_json="${out_dir}/ports_state.json"
        cat <<JSON_EOF > "$state_json"
{
  "server": "$SERVER",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "meta": $meta,
  "sensitive_ports": $crit_ports,
  "internal_whitelist_needed": $int_whitelist
}
JSON_EOF
        cp "$state_json" "${out_dir}/ports_state_${ts}.json"
        echo ""
        echo "State memori tersimpan di: $state_json"
    else
        cat "$raw_tmp" | tee "$log_file"
    fi

    rm -f "$raw_tmp"
    echo ""
    echo "Selesai: $s_name"
}

# ==============================================================================
# ALUR EKSEKUSI
# ==============================================================================
if [ "$ACTION_TARGET" == "audit" ]; then
    echo "======================================================================"
    echo "MEMULAI FULL AUDIT UNTUK: $SERVER"
    echo "Target: check_ports -> check_triage -> check_ssh_users"
    echo "======================================================================"
    echo ""
    
    echo "[1/3] Menjalankan Pemeriksaan Port & Firewall..."
    execute_single_script "check_ports"
    echo ""

    echo "[2/3] Menjalankan Pemeriksaan Sisa Penyusup (Triage)..."
    execute_single_script "check_triage"
    echo ""

    echo "[3/3] Menjalankan Pemeriksaan Konfigurasi SSH & User..."
    execute_single_script "check_ssh_users"
    echo ""

    echo "======================================================================"
    echo "FULL AUDIT SELESAI UNTUK: $SERVER"
    echo "Semua log tersimpan di: server/${SERVER}/audit/"
    echo "State memori ports tersimpan di: server/${SERVER}/audit/ports_state.json"
    echo "======================================================================"
else
    execute_single_script "$ACTION_TARGET"
fi
