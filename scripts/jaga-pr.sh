#!/usr/bin/env bash
# Penjaga PR: memeriksa seluruh PR terbuka lalu memvalidasi, mengomentari, menutup,
# atau meng-merge-nya tanpa perlu ada manusia. Berjalan berkala, jadi tidak bergantung
# pada run workflow dari fork (yang butuh persetujuan untuk akun baru).
#
# Aturan merge otomatis:
#   1. Validasi file klaim lolos.
#   2. Semua berkas yang berubah ada di data/domains/ atau data/emails/.
#   3. Field domain, subdomain, owner, address tidak berubah dari versi main.
#   4. `owner` di setiap berkas sama dengan penulis PR, atau penulisnya pemilik repo.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1

PEMILIK_REPO="${PEMILIK_REPO:-Nauvalunesa}"
BEKU="domain subdomain owner address"
MARK_MISMATCH="<!-- jaga-pr:mismatch -->"

git config --global --add safe.directory "$PWD" 2>/dev/null || true
git fetch -q origin main || exit 1
BASE=$(git rev-parse origin/main)

komentar() { gh pr comment "$1" --body "$2" >/dev/null 2>&1 || true; }

sudah_komentar() {
  gh pr view "$1" --json comments -q '.comments[].body' 2>/dev/null | grep -qF "$2"
}

mapfile -t DAFTAR < <(gh pr list --state open --limit 100 --json number -q '.[].number' 2>/dev/null)
echo "PR terbuka: ${#DAFTAR[@]}"

for n in "${DAFTAR[@]}"; do
  INFO=$(gh pr view "$n" --json isDraft,author,headRefName,headRepositoryOwner 2>/dev/null) || continue
  [ "$(echo "$INFO" | jq -r '.isDraft')" = "true" ] && continue
  AUTHOR=$(echo "$INFO" | jq -r '.author.login')
  REF=$(echo "$INFO" | jq -r '.headRefName')
  PEMILIK_HEAD=$(echo "$INFO" | jq -r '.headRepositoryOwner.login // empty')
  echo "--- PR #$n oleh $AUTHOR (head: $PEMILIK_HEAD:$REF)"

  if ! git fetch -q origin "pull/$n/head" 2>/dev/null; then
    echo "    gagal mengambil head, dilewati"
    continue
  fi
  HEAD_SHA=$(git rev-parse FETCH_HEAD)
  MB=$(git merge-base "$BASE" "$HEAD_SHA")
  git checkout -q --detach "$HEAD_SHA" 2>/dev/null || continue

  # 1. Validasi memakai skrip versi main, bukan versi dari PR.
  git show "$BASE:scripts/validate.mjs" > /tmp/validate.mjs 2>/dev/null || exit 0
  if ! node /tmp/validate.mjs "$MB" > /tmp/validate.log 2>&1; then
    echo "    validasi gagal, PR ditutup"
    {
      cat /tmp/validate.log
      echo
      echo "Validasi gagal, jadi PR ini ditutup otomatis. Perbaiki berkasnya sesuai catatan di atas, lalu buka PR baru. Perubahan tidak akan pernah aktif lewat PR ini."
    } > /tmp/balasan.md
    komentar "$n" "$(cat /tmp/balasan.md)"
    gh pr close "$n" >/dev/null 2>&1 || true
    continue
  fi

  # 2. Periksa berkas dan kepemilikan.
  BOLEH=1
  SEBAB=""
  BERUBAH=$(git diff --name-only "$MB" "$HEAD_SHA")
  for f in $BERUBAH; do
    case "$f" in
      data/domains/*.json|data/emails/*.json) ;;
      *) BOLEH=0; SEBAB="ada berkas di luar data/: $f"; continue ;;
    esac
    if [ ! -f "$f" ]; then
      BOLEH=0; SEBAB="berkas $f dihapus"; continue
    fi
    OWNER=$(jq -r '.owner // ""' "$f" 2>/dev/null)
    if [ "$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')" != "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" ] &&
       [ "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" != "$(echo "$PEMILIK_REPO" | tr '[:upper:]' '[:lower:]')" ]; then
      BOLEH=0; SEBAB="berkas $f tercatat atas nama $OWNER, bukan $AUTHOR"; continue
    fi
    LAMA=$(git show "$BASE:$f" 2>/dev/null || true)
    if [ -n "$LAMA" ]; then
      for k in $BEKU; do
        a=$(echo "$LAMA" | jq -r --arg k "$k" '.[$k] // ""')
        b=$(jq -r --arg k "$k" '.[$k] // ""' "$f")
        if [ "$a" != "$b" ]; then BOLEH=0; SEBAB="field $k pada $f berubah ($a -> $b)"; fi
      done
    fi
  done

  if [ "$BOLEH" -eq 0 ]; then
    echo "    tidak bisa otomatis: $SEBAB"
    if ! sudah_komentar "$n" "$MARK_MISMATCH"; then
      komentar "$n" "$MARK_MISMATCH
Merge otomatis belum bisa dijalankan: $SEBAB.

PR ini dibiarkan terbuka untuk ditinjau manusia. Perubahan yang bisa diterima: menambah atau mengubah **record** pada berkas yang sudah kamu klaim (field \`extra\`, \`records\`, \`description\`, \`proxy\`) tanpa mengubah \`domain\`, \`subdomain\`, \`owner\`, atau \`address\`."
    fi
    continue
  fi

  # 3. Semua aman, merge.
  if gh pr merge "$n" --squash >/dev/null 2>&1 || gh pr merge "$n" --squash --admin >/dev/null 2>&1; then
    SHA=$(gh pr view "$n" --json mergeCommit -q '.mergeCommit.oid[0:7]' 2>/dev/null)
    echo "    di-merge otomatis ($SHA)"
    komentar "$n" "Validasi lolos dan berkas yang berubah tercatat atas namamu, jadi PR ini di-merge otomatis ($SHA). Perubahan aktif setelah sinkronisasi berikutnya."
  else
    echo "    merge gagal (mungkin sudah ditangani jalur lain)"
  fi
done

git checkout -q "$BASE" 2>/dev/null || git checkout -q main 2>/dev/null || true
echo "Selesai."
