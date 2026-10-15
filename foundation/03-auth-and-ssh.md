# Foundation 03: Autentikasi & SSH Hardening

Modul ini memandu migrasi dari akun default bawaan provider menjadi akun mandiri per developer berbasis SSH Key, serta panduan pengamanan SSH.

---

## 1. Masalah Akun Bawaan Provider
Saat ini login menggunakan akun pertama bawaan VPS dengan password sudo yang sama:
- **Risiko:** Jika satu orang terkena compromised atau password bocor, seluruh server rentan. Tidak bisa diaudit siapa yang melakukan perubahan di server.
- **Solusi:** Buat akun individual per developer (`dev-budi`, `dev-andi`, dll), masing-masing login menggunakan **SSH Key pribadi**.

---

## 2. Alur Pembuatan Akun Developer Baru (Step-by-Step)

Untuk setiap developer yang butuh akses:

```bash
# 1. Buat user baru (ganti 'developer1' dengan nama developer)
sudo adduser developer1

# 2. Masukkan ke grup sudo agar memiliki hak administratif
sudo usermod -aG sudo developer1

# 3. Buat folder SSH untuk user tersebut
sudo mkdir -p /home/developer1/.ssh
sudo chmod 700 /home/developer1/.ssh

# 4. Tambahkan SSH Public Key developer ke authorized_keys
# (Tempelkan public key developer yang berakhiran .pub)
sudo nano /home/developer1/.ssh/authorized_keys
sudo chmod 600 /home/developer1/.ssh/authorized_keys

# 5. Ubah kepemilikan folder ke user bersangkutan
sudo chown -R developer1:developer1 /home/developer1/.ssh
```

> [!IMPORTANT]
> **ATURAN TEST LOGIN (ANTI-LOCKOUT):**
> Jangan pernah menutup terminal utama saat ini!
> Minta developer bersangkutan mencoba login dari komputernya:
> `ssh -i ~/.ssh/id_ed25519 developer1@<IP_SERVER>`
> Jika berhasil masuk dan bisa menjalankan `sudo whoami`, akun tersebut sudah valid.

---

## 3. Hardening Konfigurasi SSH (`/etc/ssh/sshd_config`)

Setelah **semua developer** berhasil login via SSH Key:

### A. Backup Konfigurasi Asli Terlebih Dahulu
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)
```

### B. Konfigurasi yang Diubah
Edit `/etc/ssh/sshd_config`:
```ini
# Matikan login langsung sebagai root
PermitRootLogin no

# Matikan login menggunakan password biasa (hanya boleh pakai SSH Key)
PasswordAuthentication no

# Pastikan public key diaktifkan
PubkeyAuthentication yes

# Batasi percobaan login gagal
MaxAuthTries 3
```

### C. Uji Sintaks Sebelum Restart
```bash
# Cek apakah ada error penulisan:
sudo sshd -t

# Jika tidak ada output error, reload service SSH:
sudo systemctl reload sshd # atau systemctl reload ssh
```

---

## 4. Mengenai Fail2ban: Mengapa Dulu Pernah Terkunci?

### Mengapa Dulu Bisa Terkunci?
1. **IP developer belum di-whitelist:** Fail2ban punya parameter `ignoreip`. Jika IP rumah/kantor developer belum dimasukkan, begitu developer salah ketik password 3–5 kali, IP-nya langsung diblokir total oleh firewall.
2. **Koneksi terputus-putus:** Sesi SSH yang drop tiba-tiba kadang dihitung oleh Fail2ban sebagai percobaan login gagal.

### Rekomendasi Saat Ini:
> [!TIP]
> **Tidak perlu terburu-buru memasang Fail2ban sekarang.**
> Jika Anda sudah mematikan `PasswordAuthentication` (wajib SSH Key) dan mengaktifkan Firewall UFW:
> - Penyerang **tidak bisa menebak password** karena jalur password sudah ditutup 100%.
> - Risiko terkunci menjadi **nol**.
> - Anda mendapatkan keamanan maksimal tanpa drama server terkunci secara mendadak.
