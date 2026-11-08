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
