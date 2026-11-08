# Cara klaim

Satu klaim = satu file JSON = satu pull request. Jangan menaruh password atau data
pribadi di file mana pun: repo ini publik.

## Subdomain

Buat `data/domains/<nama>.sang.ceo.json`:

```json
{
  "domain": "sang.ceo",
  "subdomain": "nama",
  "owner": "username-github-mu",
  "records": { "CNAME": "cname.vercel-dns.com" }
}
```

- `subdomain`: huruf kecil, angka, tanda hubung. Boleh bertingkat (`app.nama`).
- `records`: minimal satu record. Tipe yang didukung: CNAME, A, AAAA, TXT, MX, NS, SRV, CAA, PTR.
- Untuk A/AAAA, isi IP. Untuk record lain, isi target FQDN.
- Tidak ada record A/AAAA ke IP privat atau loopback.

### Record verifikasi tambahan

Kalau platform hosting minta TXT verifikasi (Vercel, GitHub Pages, Netlify), tambahkan
field `extra` di file yang **sudah kamu klaim** — bukan klaim subdomain baru:

```json
{
  "domain": "sang.ceo",
  "subdomain": "nama",
  "owner": "username-github-mu",
  "records": { "CNAME": "cname.vercel-dns.com" },
  "extra": [
    { "type": "TXT", "name": "_vercel", "value": "vc-domain-verify=nama.sang.ceo,abc123" }
  ]
}
```

- `name` satu label di bawah subdomainmu: `_vercel` menjadi `_vercel.nama.sang.ceo`.
- Hanya `type: "TXT"`, maksimal 10 record, nilai maksimal 500 karakter.
- Perubahan pada file yang sudah ada juga lewat PR (bukan push langsung).

#### Vercel: dua tempat yang berbeda, jangan sampai tertukar

Vercel meminta TXT di salah satu dari dua tempat, tergantung keadaan domainnya.
Lihat kalimat yang muncul di dashboard Vercel, lalu pilih yang sesuai:

1. **Domain ditambahkan di proyek milikmu sendiri.** Vercel menampilkan tabel Name dan
   Value tanpa peringatan apa pun. Nama yang diminta adalah `_vercel`, dan recordnya
   diletakkan di bawah subdomainmu.

   ```json
   "extra": [
     { "type": "TXT", "name": "_vercel", "value": "vc-domain-verify=nama.sang.ceo,abc123" }
   ]
   ```
   Hasilnya: `TXT _vercel.nama.sang.ceo`.

2. **Vercel menulis "This domain is linked to another Vercel account"** dan menyebut
   recordnya di `_vercel.sang.ceo` (tanpa nama subdomainmu). Recordnya harus di level
   zona, jadi tambahkan `"at": "apex"`.

   ```json
   "extra": [
     { "type": "TXT", "name": "_vercel", "at": "apex", "value": "vc-domain-verify=nama.sang.ceo,abc123" }
   ]
   ```
   Hasilnya: `TXT _vercel.sang.ceo`.

Pilih satu tempat saja, sesuai yang tertulis di dashboard Vercel. Kalau ternyata salah tempat,
**ganti** entri itu (tambahkan atau hapus `"at": "apex"`), jangan menambah entri kedua dengan
nilai yang sama. Dua record berbeda tempat untuk nilai yang sama hanya membuat DNS penuh dan
membingungkan saat diperiksa.

Batas pengaman: TXT di level zona hanya boleh bernama `_vercel` dan nilainya wajib
berformat `vc-domain-verify=<domain>,<kode>`. Nilai yang memverifikasi zona `sang.ceo`
itu sendiri ditolak, supaya tidak ada yang bisa mengambil alih kepemilikan zona.

## Mailbox

Buat `data/emails/<alamat>.json`:

```json
{
  "domain": "sang.ceo",
  "address": "nama",
  "type": "mailbox",
  "owner": "username-github-mu"
}
```

Setelah PR merge, akun dibuat otomatis dan sandi awal dikirim berurutan ke:
**email terverifikasi dari login via situs** → field `contact` (bila diisi) →
**email publik akun GitHub** → **email author commit**. Alamat
`@users.noreply.github.com` tidak bisa menerima surel, jadi tidak dipakai.

Kalau email GitHub-mu privat, tambahkan field `contact` berisi email penerima sandi:

```json
{
  "domain": "sang.ceo",
  "address": "nama",
  "type": "mailbox",
  "owner": "username-github-mu",
  "contact": "kamu@email-ku.com"
}
```

Perhatian: file di repo ini publik, jadi `contact` juga terbaca siapa pun. Tulis
email yang tidak keberatan dipublikasi, atau login dulu di sang.ceo pakai GitHub
agar sandi dikirim ke email terverifikasi tanpa perlu menuliskannya di file.
Jatah mailbox gratis terbatas 3 akun untuk seluruh zona.

## Aturan singkat

1. Satu subdomain / alamat per orang per keperluan. Tidak ada penimbunan.
2. Jangan klaim nama milik orang lain atau merek dagang pihak lain.
3. Konten ilegal (phishing, malware, penipuan) dihapus tanpa pemberitahuan.
4. Bot menutup otomatis PR yang filenya salah format.
