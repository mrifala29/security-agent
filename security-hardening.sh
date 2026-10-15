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
    echo "Mode Praktis (Sesuai Tahap):"
    echo "  [AUDIT]"
    echo "    audit                 : Jalankan audit lengkap (check_ports, check_triage, check_ssh_users)"
    echo "    check_ports           : Cek port sensitif 0.0.0.0 & analisis dampak koneksi (DIGABUNG)"
    echo "    check_triage          : Cek sisa cron job, ssh key asing, proses /tmp"
    echo "    check_ssh_users       : Cek status config SSH & privilege user"
    echo ""
    echo "  [ACTION]"
    echo "    backup                : Cadangkan config OS + Dump Database + Docker Compose (DIGABUNG)"
    echo "    harden_ports          : Terapkan UFW default deny & whitelist IP internal"
    echo "    migrate_old_ip        : Migrasi IP lama .70 ke IP baru .32 di seluruh .env (Auto-backup)"
    echo "    create_developer_user : Buat akun user developer baru & generate keypair otomatis"
    echo ""
    echo "  [EVALUASI]"
    echo "    verify (atau evaluasi): Scorecard validasi kelulusan menyeluruh (DIGABUNG)"
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
    echo "Sedang memproses di remote server '$SERVER' (estimasi 10-20 detik, mohon tunggu)..."

    # 2. Eksekusi via SSH dengan streaming file asli tanpa manipulasi variabel
    (echo "$PASS"; cat "$s_file") | sshpass -p "$PASS" ssh -o ConnectTimeout=20 -o ServerAliveInterval=10 -o IPQoS=none -o BatchMode=no -o StrictHostKeyChecking=accept-new "$SERVER" "sudo -S bash -s" > "$raw_tmp" 2>&1

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

    elif grep -q "###TRIAGE_STATE_START###" "$raw_tmp"; then
        sed '/###TRIAGE_STATE_START###/,$d' "$raw_tmp" | tee "$log_file"

        local t_body state_json
        t_body=$(sed -n '/###TRIAGE_STATE_START###/,/###TRIAGE_STATE_END###/{/###TRIAGE_STATE_/d;p;}' "$raw_tmp")
        state_json="${run_dir}/triage_state.json"
        echo "$t_body" > "$state_json"
        echo ""
        echo "State Memori : $state_json"

    elif grep -q "###SSH_USERS_STATE_START###" "$raw_tmp"; then
        sed '/###SSH_USERS_STATE_START###/,$d' "$raw_tmp" | tee "$log_file"

        local s_body state_json
        s_body=$(sed -n '/###SSH_USERS_STATE_START###/,/###SSH_USERS_STATE_END###/{/###SSH_USERS_STATE_/d;p;}' "$raw_tmp")
        state_json="${run_dir}/ssh_users_state.json"
        echo "$s_body" > "$state_json"
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
    echo "Setiap hasil disimpan rapi dalam sub-direktori ID unik di: server/${SERVER}/audit/"
    echo "======================================================================"

elif [ "$ACTION_TARGET" == "evaluasi" ] || [ "$ACTION_TARGET" == "verify" ]; then
    echo "======================================================================"
    echo "MEMULAI SCORECARD EVALUASI LENGKAP UNTUK: $SERVER"
    echo "======================================================================"
    echo ""
    execute_single_script "verify"
    echo "======================================================================"
    echo "EVALUASI SELESAI UNTUK: $SERVER"
    echo "Scorecard lengkap tersimpan di: server/${SERVER}/evaluasi/"
    echo "======================================================================"

elif [ "$ACTION_TARGET" == "create_developer_user" ]; then
    DEV_USER="${INPUT_KEY:-}"
    if [ -z "$DEV_USER" ]; then
        echo "Error: Masukkan nama pengguna developer yang ingin dibuat."
        echo ""
        echo "Format Penggunaan:"
        echo "  ./security-hardening.sh $SERVER create_developer_user <nama_user>"
        echo ""
        echo "Contoh:"
        echo "  ./security-hardening.sh $SERVER create_developer_user budi"
        exit 1
    fi

    echo "======================================================================"
    echo "MEMBUAT AKUN DEVELOPER & GENERATE KEYPAIR: $DEV_USER"
    echo "======================================================================"

    KEY_DIR="server/${SERVER}/keys/${DEV_USER}"
    mkdir -p "$KEY_DIR"
    PRIV_KEY="${KEY_DIR}/id_ed25519_${DEV_USER}"
    PUB_KEY_FILE="${KEY_DIR}/id_ed25519_${DEV_USER}.pub"

    if [ ! -f "$PRIV_KEY" ]; then
        echo "1. Men-generate SSH Keypair (ED25519) secara lokal..."
        ssh-keygen -t ed25519 -C "${DEV_USER}@${SERVER}" -f "$PRIV_KEY" -N "" -q
        chmod 600 "$PRIV_KEY"
        chmod 644 "$PUB_KEY_FILE"
        echo "   -> Private Key : $PRIV_KEY"
        echo "   -> Public Key  : $PUB_KEY_FILE"
    else
        echo "1. Menggunakan SSH Keypair yang sudah ada di lokal..."
        echo "   -> Private Key : $PRIV_KEY"
        echo "   -> Public Key  : $PUB_KEY_FILE"
    fi

    PUB_KEY_CONTENT=$(cat "$PUB_KEY_FILE")

    echo ""
    echo "2. Mendaftarkan user '$DEV_USER' dan Public Key ke server '$SERVER'..."
    sshpass -p "$PASS" ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new "$SERVER" "sudo -S bash -s '$DEV_USER' '$PUB_KEY_CONTENT'" <<EOF
$PASS
$(cat scripts/action/create_developer_user.sh)
EOF

    # Dapatkan IP server untuk petunjuk login
    SERVER_IP=$(sshpass -p "$PASS" ssh -o BatchMode=no -o StrictHostKeyChecking=accept-new "$SERVER" "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$SERVER")

    echo ""
    echo "======================================================================"
    echo "AKUN DEVELOPER BERHASIL DIBUAT DENGAN KEYPAIR!"
    echo "======================================================================"
    echo "Nama User        : $DEV_USER"
    echo "Server Target    : $SERVER ($SERVER_IP)"
    echo "Hak Akses        : Sudo / Admin"
    echo "Private Key (HP) : $PRIV_KEY"
    echo "Public Key (PUB) : $PUB_KEY_FILE"
    echo ""
    echo "Perintah Login untuk Developer:"
    echo "  ssh -i $PRIV_KEY $DEV_USER@$SERVER_IP"
    echo ""
    echo "CATATAN KEAMANAN:"
    echo "- Berikan file private key '$PRIV_KEY' secara privat kepada developer."
    echo "- Folder 'server/**/keys/' sudah otomatis di-ignore oleh Git (.gitignore)."
    echo "======================================================================"

else
    RESOLVED_KEY="$INPUT_KEY"
    if [ -z "$RESOLVED_KEY" ] && [ -d "server/${SERVER}/audit" ]; then
        LATEST_DIR=$(find "server/${SERVER}/audit" -mindepth 1 -maxdepth 1 -type d -name "check_ports_*" 2>/dev/null | sort | tail -n 1)
        if [ -n "$LATEST_DIR" ]; then
            RESOLVED_KEY=$(basename "$LATEST_DIR")
        fi
    fi

    execute_single_script "$ACTION_TARGET" "$RESOLVED_KEY"
fi
