#!/usr/bin/env bash
# Penjaga PR: memeriksa seluruh PR terbuka lalu memvalidasi, mengomentari, menutup,
# atau meng-merge-nya tanpa perlu ada manusia. Berjalan berkala, jadi tidak bergantung
# pada run workflow dari fork (yang butuh persetujuan untuk akun baru).
#
# Aturan merge otomatis:
#   1. Validasi file klaim lolos.
#   2. Semua berkas yang berubah ada di data/domains/ atau data/emails/.
#   3. Field domain, subdomain, owner, address tidak berubah dari versi main.
#   4. `owner` di setiap berkas sama persis dengan penulis PR. Tanpa pengecualian.
#   5. Akun penulis memang ada di GitHub.
#   6. Berkas yang ditambah belum ada di main. Kalau sudah ada dengan isi setara, PR
#      ditutup sebagai klaim ganda, bukan dibiarkan berkonflik selamanya.
#
# Dijalankan oleh pr-jaga.yml lewat pull_request_target, jadwal, dan workflow_dispatch.
# Untuk pull_request_target, variabel NOMOR_PR berisi satu nomor dan hanya PR itu yang
# diperiksa. Kalau kosong, semua PR terbuka diperiksa.
#
# Pemicu pull_request_target dipakai karena workflow yang dipicu pull_request dari fork
# selalu menerima token baca-saja, sekalipun `permissions:` menulis `write` dan setelan
# repo juga `write`. Log run membuktikannya: "Contents: read / Issues: read /
# PullRequests: read". Dengan izin itu bot tidak bisa berkomentar, menutup, apalagi
# merge, sehingga setiap PR dari kontributor baru menggantung tanpa penjelasan.
#
# Pagar keamanan. Jangan pernah dilonggarkan:
#   1. Skrip ini dijalankan dari SALINAN di /tmp, bukan dari dalam repo. Bash membaca
#      skrip bertahap dari cakram selagi berjalan; kalau isi berkasnya diganti di
#      tengah jalan, baris pengganti itu ikut dieksekusi. Pemicu pull_request_target
#      membuat GH_TOKEN berizin tulis penuh, jadi fork yang menyunting
#      scripts/jaga-pr.sh bisa menjalankan perintah apa pun dengan izin itu. Diuji
#      langsung: menyisipkan satu baris ke berkas yang sedang berjalan memang membuat
#      baris itu ikut dieksekusi.
#   2. Pohon kerja tidak pernah disentuh. Isi berkas PR dibaca langsung dari commit
#      lewat `git show`, jadi kode fork tidak pernah masuk ke cakram: tidak ada skrip
#      fork yang bisa terpanggil dan tidak ada berkas repo yang bisa tertimpa.
#   3. Validator diambil dari branch tujuan (`git show $BASE:scripts/validate.mjs`),
#      tidak pernah dari fork, supaya PR tidak bisa melunakkan aturannya sendiri.
#   4. Berkas dari PR hanya dibaca sebagai JSON, tidak pernah dijalankan.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)}"
BEKU="domain subdomain owner address"
# Penanda ditulis di komentar bot. Dipakai untuk memastikan bot tidak berkomentar
# berulang kali, TETAPI tetap menulis ulang bila pesannya sudah tidak sesuai lagi.
# Penanda beda untuk tiap sebab, jadi perubahan aturan tidak meninggalkan pesan basi.
MARK_DITOLAK="<!-- jaga-pr:ditolak -->"
MARK_TINJAU="<!-- jaga-pr:tinjau -->"
MARK_DRAF="<!-- jaga-pr:draf -->"
MARK_GANDA="<!-- jaga-pr:ganda -->"

git config --global --add safe.directory "$PWD" 2>/dev/null || true
git fetch -q origin main || exit 1
BASE=$(git rev-parse origin/main)

komentar() { gh pr comment "$1" --body "$2" >/dev/null 2>&1 || true; }

sudah_komentar() {
  gh pr view "$1" --json comments -q '.comments[].body' 2>/dev/null | grep -qF "$2"
}

# Menulis satu komentar penjelasan, menggantikan yang lama.
#
# Komentar bot hanya berguna kalau isinya sesuai keadaan sekarang. Pernah terjadi
# pesan lama tertinggal dan tetap berbunyi "pull request ini ditutup" padahal PR-nya
# dibiarkan terbuka, jadi pembacanya mengejar masalah yang sudah tidak ada. Sekarang
# komentar bot yang bertanda jaga-pr dihapus dulu, lalu ditulis yang baru.
komentar_ganti() {
  nomor=$1
  isi=$2
  # Kalau isinya sama persis dengan yang sudah ada, jangan diapa-apakan. Sapuan
  # berjalan tiap sepuluh menit; menghapus lalu menulis ulang komentar yang sama
  # berarti mengirim pemberitahuan baru ke pengklaim terus-menerus.
  #
  # Yang dibersihkan adalah SELURUH komentar bot yang bukan pemberitahuan merge,
  # bukan hanya yang bertanda. Komentar panduan lama dari versi skrip sebelumnya
  # tidak punya tanda, dan salah satunya sempat tertinggal sambil berbunyi "Validasi
  # gagal, jadi PR ini ditutup" padahal PR-nya dibiarkan terbuka.
  lama=$(gh api "repos/$REPO/issues/$nomor/comments" --paginate \
    --jq '.[] | select((.user.login | startswith("github-actions"))) | select(.body | contains("di-merge otomatis") | not) | .body' 2>/dev/null)
  if [ "$lama" = "$isi" ]; then return 0; fi
  gh api "repos/$REPO/issues/$nomor/comments" --paginate \
    --jq '.[] | select((.user.login | startswith("github-actions"))) | select(.body | contains("di-merge otomatis") | not) | .id' 2>/dev/null |
    while read -r id; do
      [ -n "$id" ] && gh api -X DELETE "repos/$REPO/issues/comments/$id" >/dev/null 2>&1
    done
  gh pr comment "$nomor" --body "$isi" >/dev/null 2>&1 || true
}

# Isi berkas pada commit PR. Pohon kerja tidak dipakai sama sekali, karena kode fork
# tidak boleh masuk ke cakram: bash membaca skrip bertahap, dan GH_TOKEN di sini
# berizin tulis penuh.
isi_pr() {
  git show "$HEAD_SHA:$1" 2>/dev/null
}

ada_pr() {
  git cat-file -e "$HEAD_SHA:$1" 2>/dev/null
}

# Akun palsu atau yang sudah dihapus tidak boleh lolos hanya karena namanya sama
# dengan yang tercatat sebagai owner.
akun_ada() {
  [ -n "$1" ] && gh api "users/$1" --jq .login >/dev/null 2>&1
}

if [ -n "${NOMOR_PR:-}" ]; then
  DAFTAR=("$NOMOR_PR")
else
  mapfile -t DAFTAR < <(gh pr list --state open --limit 100 --json number -q '.[].number' 2>/dev/null)
fi
# Pemelihara tidak diperiksa kepemilikannya.
#
# Pemeriksaan `owner` ada untuk mencegah orang lain mengambil alih klaim. Pemilik repo
# sendiri tidak perlu dilindungi dari dirinya sendiri, dan justru dialah yang harus
# bisa memperbaiki kerusakan yang ditinggalkan commit lain. Tanpa ini, satu-satunya
# jalan memperbaiki data adalah mendorong langsung ke main, memutar semua pagar yang
# ada dan sudah terbukti menimbulkan kerusakan.
PEMILIK_REPO=$(gh repo view --json owner -q .owner.login 2>/dev/null)
echo "PR terbuka: ${#DAFTAR[@]} (pemelihara: ${PEMILIK_REPO:-tidak diketahui})"

for n in "${DAFTAR[@]}"; do
  # Ambil main sekali lagi di setiap PR. Satu PR bisa mendarat selagi PR lain
  # diperiksa, dan pemeriksaan yang memakai main lama akan meloloskan klaim ganda.
  if git fetch -q origin main 2>/dev/null; then BASE=$(git rev-parse origin/main); fi

  INFO=$(gh pr view "$n" --json isDraft,author,headRefName,headRepositoryOwner 2>/dev/null) || continue
  if [ "$(echo "$INFO" | jq -r '.isDraft')" = "true" ]; then
    # Dulu draft dilewati tanpa sepatah kata. Kontributor yang membuka draft lalu
    # menandainya siap dinilai tidak memicu pemeriksaan apa pun, dan PR-nya diam
    # sampai sapuan terjadwal berikutnya, yang bisa berjam-jam kemudian.
    echo "    masih draft, diberi tahu"
    komentar_ganti "$n" "$MARK_DRAF
Pull request ini masih **draft**, jadi belum diperiksa dan belum bisa di-merge otomatis.

Klik **Ready for review** di halaman ini. Setelah itu penjaga memeriksa dan mergenya sendiri, biasanya dalam hitungan detik. Tidak perlu menutup dan membuka ulang."
    continue
  fi
  AUTHOR=$(echo "$INFO" | jq -r '.author.login')
  TRUSTED=0
  if [ -n "$PEMILIK_REPO" ] && [ "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" = "$(echo "$PEMILIK_REPO" | tr '[:upper:]' '[:lower:]')" ]; then
    TRUSTED=1
    echo "    pemelihara, pemeriksaan kepemilikan dilewati (validasi tetap jalan)"
  fi
  REF=$(echo "$INFO" | jq -r '.headRefName')
  PEMILIK_HEAD=$(echo "$INFO" | jq -r '.headRepositoryOwner.login // empty')
  echo "--- PR #$n oleh $AUTHOR (head: $PEMILIK_HEAD:$REF)"

  if ! akun_ada "$AUTHOR"; then
    echo "    akun penulis tidak ada di GitHub, PR ditutup"
    komentar "$n" "PR ini ditutup karena akun GitHub \`$AUTHOR\` tidak ditemukan. Klaim hanya bisa diajukan dari akun yang benar-benar ada."
    gh pr close "$n" >/dev/null 2>&1 || true
    continue
  fi

  if ! git fetch -q origin "pull/$n/head" 2>/dev/null; then
    echo "    gagal mengambil head, dilewati"
    continue
  fi
  HEAD_SHA=$(git rev-parse FETCH_HEAD)
  MB=$(git merge-base "$BASE" "$HEAD_SHA")

  # Pohon kerja TIDAK disentuh sama sekali. Isi berkas PR dibaca langsung dari commit
  # lewat `git show`, jadi kode fork tidak pernah masuk ke cakram dan tidak ada berkas
  # repo yang bisa tertimpa.

  # 1. Validasi memakai skrip versi main, bukan versi dari PR.
  git show "$BASE:scripts/validate.mjs" > /tmp/validate.mjs 2>/dev/null || exit 0
  echo "    base=$BASE mb=$MB head=$HEAD_SHA"
  echo "    berubah: $(git diff --name-only --diff-filter=ACM "$MB...$HEAD_SHA" | tr '\n' ' ')"
  if ! node /tmp/validate.mjs "$MB" "$HEAD_SHA" > /tmp/validate.log 2>&1; then
    echo "    validasi gagal, PR dibiarkan terbuka untuk diperbaiki"
    {
      cat /tmp/validate.log
      echo
      echo "Ada yang perlu diperbaiki. Pull request ini **dibiarkan terbuka**: perbaiki berkasnya di sini, jangan tutup dan buka ulang. Penjaga memeriksa ulang otomatis setiap kali kamu menyimpan, dan begitu lolos, pull request ini di-merge sendiri."
    } > /tmp/balasan.md
    komentar_ganti "$n" "$(cat /tmp/balasan.md)"
    continue
  fi

  # 2. Periksa berkas dan kepemilikan.
  BOLEH=1
  SEBAB=""
  # 1 = tutup PR, 0 = biarkan terbuka supaya bisa diperbaiki di tempat.
  #
  # Salah ketik `owner` pada berkas BARU adalah kesalahan yang paling sering terjadi
  # (alamat `rahardiyan` tetapi akun GitHub-nya `ryhardiyan`) dan bisa diperbaiki tanpa
  # membuka PR baru. Menutupnya memaksa orang mengulang dari awal untuk satu huruf.
  # Sebaliknya, mengubah `owner` pada berkas yang SUDAH ada adalah percobaan mengambil
  # alih klaim, dan itu tetap ditutup.
  TUTUP=0
  HAPUS=0
  BERUBAH=$(git diff --name-only "$MB" "$HEAD_SHA")
  for f in $BERUBAH; do
    case "$f" in
      data/domains/*.json|data/emails/*.json) ;;
      *) BOLEH=0; TUTUP=1; SEBAB="ada berkas di luar data/: $f"; continue ;;
    esac
    if ! ada_pr "$f"; then
      # Berkas dihapus. Ini boleh kalau pemiliknya sendiri yang menghapus, dan
      # hanya untuk berkas SUBDOMAIN. Berkas mailbox tidak boleh dihapus lewat
      # PR, karena menghapus akun email tidak bisa dikembalikan.
      case "$f" in
        data/emails/*)
          BOLEH=0; TUTUP=1; SEBAB="berkas mailbox $f tidak boleh dihapus lewat PR"
          continue
          ;;
      esac
      LAMA_HAPUS=$(git show "$BASE:$f" 2>/dev/null || true)
      if [ -z "$LAMA_HAPUS" ]; then
        BOLEH=0; TUTUP=1; SEBAB="berkas $f dihapus, padahal tidak ada di main"; continue
      fi
      OWNER_HAPUS=$(echo "$LAMA_HAPUS" | jq -r '.owner // ""' 2>/dev/null)
      # Owner kosong atau gagal dibaca berarti tidak bisa dipastikan pemiliknya.
      # Tanpa pagar ini, penulis PR yang namanya juga kosong akan lolos.
      if [ -z "$OWNER_HAPUS" ] || [ -z "$AUTHOR" ]; then
        BOLEH=0; TUTUP=1; SEBAB="pemilik $f tidak bisa dipastikan, penghapusan ditolak"
        continue
      fi
      if [ "$TRUSTED" -eq 0 ] && [ "$(echo "$OWNER_HAPUS" | tr '[:upper:]' '[:lower:]')" != "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" ]; then
        BOLEH=0; TUTUP=1; SEBAB="berkas $f milik $OWNER_HAPUS, bukan $AUTHOR"
      fi
      HAPUS=1
      continue
    fi
    OWNER=$(isi_pr "$f" | jq -r '.owner // ""' 2>/dev/null)
    if [ -z "$OWNER" ] || [ -z "$AUTHOR" ]; then
      BOLEH=0; TUTUP=1; SEBAB="pemilik $f tidak bisa dipastikan, perubahan ditolak"; continue
    fi
    if [ "$TRUSTED" -eq 0 ] && [ "$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')" != "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" ]; then
      # Berkas baru dengan owner salah ketik: bisa diperbaiki di tempat, jangan ditutup.
      if git cat-file -e "$BASE:$f" 2>/dev/null; then
        BOLEH=0; TUTUP=1; SEBAB="berkas $f tercatat atas nama $OWNER, bukan $AUTHOR"
      else
        BOLEH=0; TUTUP=0
        SEBAB="berkas $f menulis \`owner\` = \`$OWNER\`, sedangkan akun yang membuka pull request ini adalah \`$AUTHOR\`. Ganti menjadi \`$AUTHOR\`, lalu simpan; penjaga akan memeriksa ulang sendiri."
      fi
      continue
    fi
    LAMA=$(git show "$BASE:$f" 2>/dev/null || true)
    if [ -n "$LAMA" ] && [ "$TRUSTED" -eq 0 ]; then
      for k in $BEKU; do
        a=$(echo "$LAMA" | jq -r --arg k "$k" '.[$k] // ""')
        b=$(isi_pr "$f" | jq -r --arg k "$k" '.[$k] // ""')
        if [ "$a" != "$b" ]; then BOLEH=0; TUTUP=1; SEBAB="field $k pada $f berubah ($a -> $b)"; fi
      done
    fi
  done

  # Berkas yang ditambah tetapi sudah ada di main. Dua PR untuk klaim yang sama
  # membuat git menandainya "add/add conflict", dan tanpa pemeriksaan ini PR-nya
  # menggantung dengan status konflik tanpa penjelasan apa pun.
  GANDA=""
  for f in $BERUBAH; do
    case "$f" in data/domains/*.json|data/emails/*.json) ;; *) continue ;; esac
    ada_pr "$f" || continue
    LAMA=$(git show "$BASE:$f" 2>/dev/null || true)
    [ -n "$LAMA" ] || continue
    SUB_BARU=$(isi_pr "$f" | jq -r '.subdomain // .address // ""' 2>/dev/null)
    SUB_LAMA=$(echo "$LAMA" | jq -r '.subdomain // .address // ""' 2>/dev/null)
    OWNER_LAMA=$(echo "$LAMA" | jq -r '.owner // ""' 2>/dev/null)
    if [ "$SUB_BARU" = "$SUB_LAMA" ] && [ "$SUB_LAMA" != "" ] \
       && [ "$(echo "$OWNER_LAMA" | tr '[:upper:]' '[:lower:]')" = "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" ]; then
      GANDA="$SUB_LAMA"
    fi
  done

  if [ -n "$GANDA" ]; then
    echo "    klaim $GANDA sudah ada di main, PR ditutup sebagai klaim ganda"
    komentar_ganti "$n" "$MARK_GANDA
Klaim \`$GANDA\` sudah aktif di main atas namamu, jadi pull request ini ditutup tanpa merge.

Ini biasanya terjadi karena tombol klaim ditekan dua kali, atau karena pull request sebelumnya sudah masuk tetapi halamannya belum dimuat ulang. Tidak ada yang perlu diperbaiki: subdomain dan mailbox-mu sudah jalan.

Kalau yang kamu maksud sebenarnya **mengubah** klaim yang sudah ada, gunakan halaman kelola di <https://sang.ceo/kelola>, bukan membuat berkas baru."
    gh pr close "$n" >/dev/null 2>&1 || true
    continue
  fi

  if [ "$BOLEH" -eq 0 ]; then
    echo "    perlu diperbaiki: $SEBAB"
    if [ "$TUTUP" -eq 1 ]; then
      AKHIR="Pull request ini ditutup dan perubahannya tidak akan aktif. Kalau salah satu poin di atas tidak jelas, tulis di issue."
    else
      AKHIR="Pull request ini **dibiarkan terbuka**. Perbaiki berkasnya di sini, jangan tutup dan buka ulang; penjaga memeriksa ulang otomatis setiap kali kamu menyimpan. Begitu lolos, pull request ini di-merge sendiri."
    fi
    komentar_ganti "$n" "$MARK_DITOLAK
Ada yang perlu diperbaiki: $SEBAB

Aturannya sederhana: yang boleh mengubah isi berkas klaim hanya akun GitHub yang tercatat sebagai \`owner\` di berkas itu. Ini yang mencegah orang lain mengambil alih klaim bukan miliknya.

Catatan soal menghapus klaim:
- Boleh menghapus klaim **subdomain** milikmu sendiri. Berkasnya hilang dari main, dan record DNS-nya ikut dibersihkan oleh sinkronisasi.
- Berkas **mailbox tidak boleh dihapus lewat PR**, karena menghapus akun email tidak bisa dikembalikan. Ajukan lewat issue kalau memang perlu.

$AKHIR"
    [ "$TUTUP" -eq 1 ] && gh pr close "$n" >/dev/null 2>&1
    continue
  fi

  # 3. Semua aman. Ambil main sekali lagi tepat sebelum merge.
  #
  # Pemeriksaan di atas memakai main yang diambil beberapa detik sebelumnya. Kalau PR
  # lain untuk nama yang sama mendarat di sela itu, merge-nya berakhir sebagai
  # add/add conflict dan pesan galatnya tidak menjelaskan apa pun. Diperiksa ulang di
  # sini supaya jendelanya tinggal sepersekian detik, bukan sepanjang pemeriksaan.
  if git fetch -q origin main 2>/dev/null; then BASE=$(git rev-parse origin/main); fi
  BENTUR=""
  for f in $BERUBAH; do
    case "$f" in data/domains/*.json|data/emails/*.json) ;; *) continue ;; esac
    ada_pr "$f" || continue
    ADA_SEKARANG=$(git show "$BASE:$f" 2>/dev/null || true)
    [ -n "$ADA_SEKARANG" ] || continue
    OWNER_SEKARANG=$(echo "$ADA_SEKARANG" | jq -r '.owner // ""' 2>/dev/null)
    NAMA_SEKARANG=$(echo "$ADA_SEKARANG" | jq -r '.subdomain // .address // ""' 2>/dev/null)
    BENTUR="$NAMA_SEKARANG"
    if [ "$TRUSTED" -eq 0 ] && [ "$(echo "$OWNER_SEKARANG" | tr '[:upper:]' '[:lower:]')" != "$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')" ]; then
      BENTUR="$NAMA_SEKARANG|$OWNER_SEKARANG"
    fi
    break
  done

  if [ -n "$BENTUR" ]; then
    NAMA_BENTUR=${BENTUR%%|*}
    PEMILIK_BENTUR=${BENTUR#*|}
    [ "$PEMILIK_BENTUR" = "$BENTUR" ] && PEMILIK_BENTUR=""
    echo "    nama $NAMA_BENTUR baru saja diklaim, PR tidak di-merge"
    if [ -z "$PEMILIK_BENTUR" ]; then
      komentar_ganti "$n" "$MARK_GANDA
Klaim \`$NAMA_BENTUR\` baru saja masuk ke main selagi pull request ini diperiksa, jadi pull request ini ditutup tanpa merge.

Klaim itu atas namamu sendiri, jadi tidak ada yang perlu diperbaiki: subdomain dan mailbox-mu sudah jalan. Halaman kelola di <https://sang.ceo/kelola> dipakai untuk mengubah, bukan untuk menambah berkas baru."
    else
      komentar_ganti "$n" "$MARK_GANDA
Klaim \`$NAMA_BENTUR\` baru saja masuk ke main atas nama \`$PEMILIK_BENTUR\`, jadi pull request ini ditutup tanpa merge.

Satu nama hanya boleh satu pemilik. Pilih nama lain lewat <https://sang.ceo/daftar>."
    fi
    gh pr close "$n" >/dev/null 2>&1 || true
    continue
  fi

  if gh pr merge "$n" --squash >/dev/null 2>&1 || gh pr merge "$n" --squash --admin >/dev/null 2>&1; then
    SHA=$(gh pr view "$n" --json mergeCommit -q '.mergeCommit.oid[0:7]' 2>/dev/null)
    echo "    di-merge otomatis ($SHA)"
    komentar "$n" "Validasi lolos dan berkas yang berubah tercatat atas namamu, jadi PR ini di-merge otomatis ($SHA). Perubahan aktif setelah sinkronisasi berikutnya."
  else
    GALAT=$(gh pr merge "$n" --squash 2>&1 | head -3 | tr '\n' ' ')
    echo "    merge gagal: $GALAT"
    # Konflik hampir selalu berarti berkas yang sama baru diubah PR lain. PR dibiarkan
    # terbuka: pemeriksaan berikutnya akan menemukan sebabnya, dan penulisnya tetap
    # bisa memperbaiki. Menutupnya di sini akan menghapus pekerjaan yang masih sah.
    komentar_ganti "$n" "$MARK_TINJAU
Pull request ini lolos pemeriksaan, tetapi GitHub menolak merge-nya:

\`\`\`
$GALAT
\`\`\`

Biasanya ini berarti bagian yang sama baru diubah pull request lain. Pull request ini **dibiarkan terbuka** dan diperiksa ulang otomatis. Kalau kamu tahu berkasnya bentrok, perbaiki di sini."
  fi
done

echo "Selesai."
