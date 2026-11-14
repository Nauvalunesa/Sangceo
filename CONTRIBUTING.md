# Cara klaim

Satu klaim = satu file JSON = satu pull request. Jangan menaruh password atau data
pribadi di file mana pun: repo ini publik.


## Siapa yang boleh mengubah sebuah klaim

Isi berkas klaim hanya boleh diubah oleh akun GitHub yang tercatat sebagai `owner` di berkas
itu. Bukan "kira-kira sama", tapi harus sama persis dengan login akun yang mengirim pull
request.

Kalau kamu memakai dua akun dan mengirim PR dari akun yang bukan `owner`, PR itu ditolak
otomatis dan ditutup, dengan alasan yang dituliskan di kolom komentar. Solusinya salah satu
dari ini:

- kirim ulang PR-nya dari akun yang sama dengan `owner`, atau
- kalau `owner` di berkas itu salah catat, tulis di issue supaya pemelihara membetulkannya

Aturan ini yang menjaga supaya tidak ada orang yang bisa mengubah atau menghapus klaim milik
orang lain hanya dengan mengirim pull request.

### Batas subdomain per akun

Satu akun GitHub boleh memegang **paling banyak 3 subdomain**. Batas ini ditegakkan
di dua tempat dengan angka yang sama: `scripts/validate.mjs` untuk pull request
manual, dan `/kelola` untuk jalur web. Kalau ingin menambah yang keempat,
lepaskan salah satu dulu lewat <https://sang.ceo/kelola>, baru klaim yang baru.

Turunan seperti `api.nama-mu.sang.ceo` dan wildcard `*.nama-mu.sang.ceo` tidak
dihitung terpisah, karena itu bagian dari subdomain yang sama.

## Tipe record yang didukung

`A`, `AAAA`, `CNAME`, `TXT`, `SRV`, `CAA`.

Daftar ini **sama persis** untuk dua jalur: web di <https://sang.ceo/kelola> dan pull request
manual di GitHub. Tidak ada tipe yang hanya bisa satu jalur. Jadi apa pun yang bisa kamu ubah
lewat web, bisa juga kamu ubah lewat PR, dan sebaliknya.

Dua tipe sengaja tidak dipakai, dengan alasan masing-masing:

- `MX` mengarahkan surat masuk. Salah isi berarti surat pemilik klaim bisa jatuh ke pihak lain.
- `NS` bisa mengambil alih seluruh zona.

Tipe di luar daftar akan **ditolak** validator. Bukan karena aturan sewenang-wenang: generator
DNS yang dipakai server hanya memetakan tipe-tipe itu, sehingga tipe lain akan lolos review lalu
diabaikan diam-diam dan recordnya tidak pernah aktif.

Ingin tipe lain, misalnya `PTR` atau `DNAME`? Tulis di issue supaya generatornya ditambah lebih
dulu. Jangan kirim PR dengan tipe yang belum dipetakan.

Satu tipe boleh punya beberapa nilai, misalnya dua record `A` untuk dua server. Cukup
jadikan nilainya array:

```json
{ "records": { "A": ["103.190.0.15", "103.190.0.16"] } }
```

`CNAME` tidak bisa seperti itu. CNAME harus satu-satunya record pada namanya, jadi mencampur
CNAME dengan tipe lain ditolak.

## Mengganti tipe record (CNAME ke A, atau sebaliknya)

Type record ditentukan oleh field `records` di berkasmu. Satu nama DNS hanya boleh punya
satu CNAME atau satu A, tidak boleh dua-duanya sekaligus. Jadi kalau kamu berpindah dari
Vercel ke server sendiri:

```json
{
  "domain": "sang.ceo",
  "subdomain": "namamu",
  "owner": "username-github-mu",
  "records": { "A": "103.190.0.15" },
  "proxy": false
}
```

Cukup ganti isi `records` dari CNAME menjadi A. Record CNAME yang lama akan dihapus otomatis
oleh sinkronisasi, jadi kamu tidak perlu menunggu tindakan pemelihara. Kalau setelah
sinkronisasi record A belum muncul, tulis di issue, jangan menambah entri kedua.

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

Sandi mailbox itu satu-satunya hal yang dikirim ke luar repo, dan alamat penerimanya diambil
dalam urutan: field `contact` (kalau ada) lalu email akun GitHub pengklaim. Kalau alamat itu
tidak bisa dipastikan, pengirimannya dibatalkan dan kamu perlu menambahkan `contact` supaya
sandi dikirim ulang. Jadi jangan biarkan kolom ini kosong kalau email GitHub-mu privat.

Perhatian: file di repo ini publik, jadi `contact` juga terbaca siapa pun. Tulis
email yang tidak keberatan dipublikasi, atau login dulu di sang.ceo pakai GitHub
agar sandi dikirim ke email terverifikasi tanpa perlu menuliskannya di file.
Jatah mailbox gratis terbatas 3 akun untuk seluruh zona.

## Beberapa hal yang paling sering membuat PR ditolak

Semuanya bisa diperbaiki langsung di pull request yang sama. Tidak perlu menutup lalu
membuka yang baru: penjaga memeriksa ulang otomatis setiap kali kamu menyimpan.

1. **Nama berkas harus sama dengan isinya.** `data/domains/budi.sang.ceo.json` harus
   berisi `"subdomain": "budi"`, dan `data/emails/budi.json` harus berisi
   `"address": "budi"`. Kalau berbeda, berkasnya tidak dianggap milik siapa pun.
2. **`owner` harus akun GitHub yang membuka pull request.** Menulis nama panggilan di
   situ adalah kesalahan yang paling sering terjadi, dan akibatnya PR ditolak.
3. **Nama yang dipakai sistem tidak bisa diklaim.** `www`, `mail`, `webmail`,
   `autoconfig`, `autodiscover`, `mx1`, `admin`, `abuse`, dan sejenisnya. Halaman
   generator sudah menolaknya lebih dulu, jadi cukup ikuti yang tersedia di sana.
4. **Satu nama hanya boleh satu berkas.** Klaim ganda otomatis ditutup sebagai klaim
   ganda, dan yang kedua tidak akan pernah merge.

## Aturan singkat

1. Satu subdomain / alamat per orang per keperluan. Tidak ada penimbunan.
2. Jangan klaim nama milik orang lain atau merek dagang pihak lain.
3. Konten ilegal (phishing, malware, penipuan) dihapus tanpa pemberitahuan.
4. Bot menolak otomatis PR yang filenya salah format, salah nama berkas, atau memakai
   nama yang dicadangkan. PR-nya dibiarkan terbuka supaya bisa diperbaiki di tempat.
