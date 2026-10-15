#!/usr/bin/env bash
# ==============================================================================
# Security Hardening CLI: security-hardening.sh
# ==============================================================================
# Mengorganisir setiap eksekusi ke dalam sub-direktori unik:
#   server/<server>/<stage>/<script_name>_<timestamp>/
# Direktori ini menjadi "KEY" yang dapat dijadikan input memori ke step berikutnya.
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
INPUT_KEY="${3:-}"

if [ -z "$SERVER" ] || [ -z "$ACTION_TARGET" ]; then
    echo "======================================================================"
    echo "SECURITY HARDENING CLI"
    echo "======================================================================"
    echo "Cara pakai:"
    echo "  ./security-hardening.sh <server_alias> <perintah_atau_skrip> [INPUT_KEY]"
    echo ""
    echo "Contoh Perintah:"
    echo "  1. Audit Full (menjalankan semua audit & membuat folder key masing-masing):"
    echo "     ./security-hardening.sh server-dev audit"
    echo ""
    echo "  2. Audit Satuan:"
    echo "     ./security-hardening.sh server-dev check_ports"
    echo "     ./security-hardening.sh server-dev check_triage"
    echo "     ./security-hardening.sh server-dev check_ssh_users"
    echo ""
    echo "  3. Action (bisa menerima input key hasil audit sebelumnya):"
    echo "     ./security-hardening.sh server-dev backup_configs"
    echo "     ./security-hardening.sh server-dev harden_ports [KEY_AUDIT_OPTIONAL]"
    echo ""
    echo "  4. Evaluasi:"
    echo "     ./security-hardening.sh server-dev verify_ports [KEY_ACTION_OPTIONAL]"
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
# FUNGSI EKSEKUTOR SKRIP DENGAN STRUKTUR SUB-DIREKTORI KEY
# ==============================================================================
execute_single_script() {
    local s_name="$1"
    local ref_key="${2:-}"
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

    # 1. Tentukan RUN KEY dan Folder Tujuan
    local ts
    ts=$(date +"%Y%m%d_%H%M%S")
    local run_key="${s_name}_${ts}"
    local run_dir="server/${SERVER}/${stage}/${run_key}"
    mkdir -p "$run_dir"

    local raw_tmp
    raw_tmp=$(mktemp)
    local log_file="${run_dir}/${s_name}.log"

    echo "======================================================================"
    echo "Menjalankan [$stage] '$s_file' ke '$SERVER' ..."
    echo "Key Folder : $run_key"
    echo "Direktori  : $run_dir/"
    if [ -n "$ref_key" ]; then
        echo "Input Key  : $ref_key (Rujukan dari tahap sebelumnya)"
    fi
    echo "======================================================================"

    # 2. Eksekusi via SSH
    sshpass -p "$PASS" ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new "$SERVER" "sudo -S bash -s" <<EOF > "$raw_tmp" 2>&1
$PASS
$(cat "$s_file")
EOF

    # Bersihkan prompt sudo baris pertama
    sed -i '' '1{/^\[sudo\] password for /d;}' "$raw_tmp" 2>/dev/null || true

    # 3. Pisahkan output konsol dan file state JSON
    if grep -q "###PORT_STATE_META###" "$raw_tmp"; then
        sed '/###PORT_STATE_META###/,$d' "$raw_tmp" | tee "$log_file"

        local meta crit_ports int_whitelist state_json
        meta=$(grep -A 1 "###PORT_STATE_META###" "$raw_tmp" | tail -n 1)
        crit_ports=$(grep -A 1 "###CRIT_PORTS_JSON###" "$raw_tmp" | tail -n 1)
        int_whitelist=$(grep -A 1 "###INTERNAL_WHITELIST_JSON###" "$raw_tmp" | tail -n 1)

        state_json="${run_dir}/ports_state.json"
        cat <<JSON_EOF > "$state_json"
{
  "key": "$run_key",
  "server": "$SERVER",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "meta": $meta,
  "sensitive_ports": $crit_ports,
  "internal_whitelist_needed": $int_whitelist
}
JSON_EOF
        echo ""
        echo "State Memori : $state_json"
    else
        cat "$raw_tmp" | tee "$log_file"
    fi

    # 4. Catat Metadata Key jika ada input dari tahap sebelumnya
    if [ -n "$ref_key" ]; then
        cat <<META_EOF > "${run_dir}/input_ref.json"
{
  "current_key": "$run_key",
  "source_input_key": "$ref_key",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
META_EOF
    fi

    rm -f "$raw_tmp"
    echo ""
    echo "Selesai: $s_name (Key: $run_key)"
}

# ==============================================================================
# ALUR EKSEKUSI
# ==============================================================================
if [ "$ACTION_TARGET" == "audit" ]; then
    echo "======================================================================"
    echo "MEMULAI FULL AUDIT UNTUK: $SERVER"
    echo "======================================================================"
    echo ""
    
    echo "[1/3] Menjalankan check_ports..."
    execute_single_script "check_ports"
    echo ""

    echo "[2/3] Menjalankan check_triage..."
    execute_single_script "check_triage"
    echo ""

    echo "[3/3] Menjalankan check_ssh_users..."
    execute_single_script "check_ssh_users"
    echo ""

    echo "======================================================================"
    echo "FULL AUDIT SELESAI UNTUK: $SERVER"
    echo "Setiap hasil disimpan rapi dalam sub-direktori unik di: server/${SERVER}/audit/"
    echo "======================================================================"
else
    # Jika menjalankan action/evaluasi tanpa input key eksplisit, ambil ID direktori audit terbaru
    RESOLVED_KEY="$INPUT_KEY"
    if [ -z "$RESOLVED_KEY" ] && [ -d "server/${SERVER}/audit" ]; then
        LATEST_DIR=$(find "server/${SERVER}/audit" -mindepth 1 -maxdepth 1 -type d -name "check_ports_*" 2>/dev/null | sort | tail -n 1)
        if [ -n "$LATEST_DIR" ]; then
            RESOLVED_KEY=$(basename "$LATEST_DIR")
        fi
    fi

    execute_single_script "$ACTION_TARGET" "$RESOLVED_KEY"
fi
