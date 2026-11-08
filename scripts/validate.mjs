#!/usr/bin/env node
// Validasi file klaim di pull request. Dipakai workflow validate-pr.yml.
// Keluar: exit 1 kalau ada file salah, dan mencetak ringkasan untuk komentar bot.

import { execSync } from "node:child_process";
import fs from "node:fs";

const BASE = process.argv[2]; // contoh: origin/main
const ZONE = "sang.ceo";

const changedAll = execSync(`git diff --name-only --diff-filter=ACM ${BASE}...HEAD`, {
  encoding: "utf8",
})
  .split("\n")
  .filter(Boolean);

// JSON di luar data/ adalah kesalahan penempatan yang paling sering terjadi.
// Jangan dibisukan: beri tahu pembuka PR agar tidak mengulangi kesalahan yang sama.
const misplaced = changedAll.filter((f) => f.endsWith(".json") && !f.startsWith("data/"));
const changed = changedAll.filter((f) => f.startsWith("data/") && f.endsWith(".json"));

const NAME_RE = /^([a-z0-9]([a-z0-9-]*[a-z0-9])?)(\.([a-z0-9]([a-z0-9-]*[a-z0-9])?))*$/;
const EMAIL_RE = /^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/;
const ADDR_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Nama yang sudah ada di main, untuk cek duplikat lintas file.
const existing = {
  sub: new Set(
    execSync(`git ls-tree -r --name-only ${BASE} -- data/domains`, { encoding: "utf8" })
      .split("\n")
      .filter(Boolean)
      .map((f) => f.split("/").pop().replace(`.${ZONE}.json`, "").replace(".json", ""))
  ),
  mail: new Set(
    execSync(`git ls-tree -r --name-only ${BASE} -- data/emails`, { encoding: "utf8" })
      .split("\n")
      .filter(Boolean)
      .map((f) => f.split("/").pop().replace(".json", ""))
  ),
};

const errors = [];
const previews = [];

for (const file of misplaced) {
  errors.push(
    `\`${file}\`: posisi file salah. File klaim harus di \`data/domains/<nama>.${ZONE}.json\` atau \`data/emails/<alamat>.json\`. Paling mudah: buat ulang lewat generator di https://${ZONE}/daftar`
  );
}

// Sensor utk tampilan: nama -> ja••••el; nilai record: label penyedia tetap terlihat.
function censorMiddle(s) {
  if (s.length <= 3) return s[0] + "•" + (s.length > 2 ? s[s.length - 1] : "");
  return s.slice(0, 2) + "•".repeat(s.length - 4) + s.slice(-2);
}
function maskName(name) {
  return censorMiddle(String(name).trim());
}
function maskRecord(value) {
  const v = String(value).trim();
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(v)) {
    const o = v.split(".");
    return `${o[0]}.•••.•••.${o[3]}`;
  }
  const labels = v.split(".");
  if (labels.length <= 2) return censorMiddle(v);
  return censorMiddle(labels[0]) + "." + labels.slice(1).join(".");
}

for (const file of changed) {
  const rel = file;
  let data;
  try {
    data = JSON.parse(fs.readFileSync(rel, "utf8"));
  } catch (e) {
    errors.push(`\`${rel}\`: bukan JSON valid (${e.message})`);
    continue;
  }

  if (rel.startsWith("data/domains/")) {
    const { domain, subdomain, owner, records, extra } = data;
    if (domain !== ZONE) errors.push(`\`${rel}\`: \`domain\` harus \`${ZONE}\``);
    if (!subdomain || !NAME_RE.test(subdomain))
      errors.push(`\`${rel}\`: \`subdomain\` tidak valid (huruf kecil, angka, tanda hubung)`);
    if (!owner) errors.push(`\`${rel}\`: \`owner\` (username GitHub) wajib`);
    if (!records || typeof records !== "object" || Object.keys(records).length === 0)
      errors.push(`\`${rel}\`: \`records\` wajib berisi minimal satu record`);
    if (subdomain && existing.sub.has(subdomain) && !rel.endsWith(`/${subdomain}.${ZONE}.json`))
      errors.push(`\`${rel}\`: subdomain \`${subdomain}\` sudah diklaim orang lain`);
    if (subdomain && records?.CNAME && NAME_RE.test(subdomain)) {
      if (typeof records.CNAME !== "string")
        errors.push(`\`${rel}\`: CNAME harus berupa string tunggal`);
      if (String(records.CNAME).toLowerCase().startsWith(`${subdomain}.${ZONE}`))
        errors.push(`\`${rel}\`: CNAME tidak boleh menunjuk ke namanya sendiri`);
    }
    // record tambahan untuk verifikasi penyedia hosting (Vercel, GitHub Pages, Netlify, dsb).
    // Namanya label relatif di bawah subdomain sendiri, mis. "_vercel" -> _vercel.elkaff.sang.ceo
    if (extra !== undefined) {
      if (!Array.isArray(extra) || extra.length > 10) {
        errors.push(`\`${rel}\`: \`extra\` harus berupa array maksimal 10 record`);
      } else {
        const LABEL_RE = /^_?[a-z0-9][a-z0-9-]{0,62}$/;
        extra.forEach((x, i) => {
          const at = `\`${rel}\`: \`extra[${i}]\``;
          if (!x || typeof x !== "object") return errors.push(`${at} harus objek {type,name,value}`);
          if (x.type !== "TXT")
            errors.push(`${at}: hanya \`type: "TXT"\` yang didukung untuk verifikasi`);
          if (!x.name || !LABEL_RE.test(x.name))
            errors.push(`${at}: \`name\` harus satu label huruf kecil/angka/tanda hubung, boleh diawali \`_\``);
          if (typeof x.value !== "string" || x.value.length === 0 || x.value.length > 500 || /[\r\n]/.test(x.value))
            errors.push(`${at}: \`value\` harus string 1-500 karakter tanpa baris baru`);
        });
      }
    }
    if (!errors.some((e) => e.startsWith(`\`${rel}\``))) {
      const rec = Object.entries(records || {})
        .map(([t, v]) => `${t} ${Array.isArray(v) ? v.map((x) => maskRecord(String(x))).join(", ") : maskRecord(String(v))}`)
        .join(" · ");
      previews.push(`| \`${maskName(subdomain)}.${ZONE}\` | ${maskName(owner)} | ${data.description || "-"} | ${rec} |`);
    }
  } else if (rel.startsWith("data/emails/")) {
    const { domain, address, owner, type, contact, password } = data;
    if (password)
      errors.push(`\`${rel}\`: JANGAN taruh password di file. Sandi dikirim otomatis ke email akun GitHub yang membuka PR`);
    if (domain !== ZONE) errors.push(`\`${rel}\`: \`domain\` harus \`${ZONE}\``);
    if (!address || !EMAIL_RE.test(address))
      errors.push(`\`${rel}\`: \`address\` tidak valid (huruf kecil, angka, titik, tanda hubung)`);
    if (!owner) errors.push(`\`${rel}\`: \`owner\` (username GitHub) wajib`);
    if (type && type !== "mailbox")
      errors.push(`\`${rel}\`: hanya \`type: "mailbox"\` yang didukung`);
    if (contact && !ADDR_RE.test(contact))
      errors.push(`\`${rel}\`: \`contact\` harus alamat email yang valid`);
    if (address && existing.mail.has(address) && !rel.endsWith(`/${address}.json`))
      errors.push(`\`${rel}\`: alamat \`${address}\` sudah diklaim orang lain`);
    if (!errors.some((e) => e.startsWith(`\`${rel}\``))) {
      previews.push(
        `| \`${maskName(address)}@${ZONE}\` | ${maskName(owner)} | mailbox, sandi ke ${contact ? "email contact" : "email akun GitHub"} |`
      );
    }
  }
}

if (previews.length > 0) {
  const isMail = previews[0].includes("@");
  console.log(
    isMail
      ? "### Pratinjau klaim email\n\n| Alamat | Pemilik | Jenis |\n|---|---|---|\n" +
          previews.join("\n")
      : "### Pratinjau klaim subdomain\n\n| Subdomain | Pemilik | Deskripsi | Record |\n|---|---|---|---|\n" +
          previews.join("\n")
  );
}

if (changed.length === 0 && misplaced.length === 0) {
  console.log(
    `Tidak ada file klaim dalam PR ini. Klaim diletakkan di \`data/domains/\` atau \`data/emails/\` — generator: https://${ZONE}/daftar`
  );
}

if (errors.length > 0) {
  console.error("### Perlu diperbaiki\n\n" + errors.map((e) => `- ${e}`).join("\n"));
  process.exit(1);
}
console.log("Semua file klaim lolos validasi.");
