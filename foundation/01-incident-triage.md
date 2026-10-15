# Foundation 01: Cek Indikasi Penyusup (Incident Triage)

Tujuan dokumen ini adalah memastikan tidak ada sisa pintu belakang (*backdoor*), tugas terjadwal berbahaya (*cron job*), atau akun siluman yang ditinggalkan oleh penyerang.

---

## 1. Titik Pemeriksaan Wajib

### A. Cron Jobs & Scheduled Tasks (Sarang Favorit Backdoor)
Penyerang sering menaruh script otomatis untuk konek kembali ke server mereka.
- **File & Direktori yang dicek:**
  - `/etc/crontab`
  - `/etc/cron.*` (hourly, daily, weekly, monthly, cron.d)
  - `/var/spool/cron/crontabs/*` (crontab milik tiap user termasuk root)
- **Tanda bahaya:** Perintah yang memanggil URL eksternal via `curl`/`wget` lalu di-pipe ke `bash`/`sh`, atau koneksi langsung ke IP publik.

### B. Akun & Kunci SSH Tersembunyi
- **File yang dicek:**
  - `/etc/passwd` (cari user dengan UID 0 selain root, atau user tanpa password).
  - `~/.ssh/authorized_keys` di semua user home dan `/root/.ssh/authorized_keys`.
- **Tanda bahaya:** Kunci SSH yang tidak dikenali oleh tim developer.

### C. Koneksi Keluar Mencurigakan (Active Outbound Connections)
- **Perintah audit:**
  ```bash
  ss -antp | grep ESTAB
  ```
- **Tanda bahaya:** Koneksi yang mengarah ke port asing di luar negeri atau IP publik mencurigakan dari proses yang tidak dikenal.

### D. File Eksekusi di Direktori Temp
- **Direktori:** `/tmp`, `/var/tmp`, `/dev/shm`
- **Tanda bahaya:** File binary tersembunyi (diawali titik `.`), script `.sh` asing, atau proses yang sedang running dari folder ini.

---

## 2. Prinsip Tindakan Jika Menemukan Kejanggalan
- **JANGAN langsung hapus sembarangan:** Catat dan salin (backup) file atau baris crontab yang mencurigakan ke folder log untuk bukti analisis.
- **Hentikan proses:** Matikan proses aktifnya (`kill -9 <PID>`) sebelum membersihkan filenya.
