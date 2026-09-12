#!/system/bin/sh
# FAACC embedded engine — scan & clean agresif TANPA module Magisk.
# Dijalankan app via root:  engine.sh --scan pkg... | engine.sh --clean pkg...
# Daftar pkg dipasok Java (PackageManager) dan SUDAH divalidasi regex di sana.
# Di sini tetap ada validasi ringan + is_safe_path per direktori (nol fork).
#
# Cakupan AGRESIF per package:
#   internal : /data/data, /data/user/<N>, /data/user_de/<N> x {cache,code_cache}
#   eksternal: /sdcard|/data/media/0/Android/data/<pkg>/cache
# Prinsip: tanpa pm clear, tanpa hapus data, gagal validasi = ABORT.

# Validasi ringan TANPA fork (regex berat sudah di Java).
# Tolak: kosong, slash, spasi (karakter yang bisa belokkan path).
_light_validate() {
  case "$1" in
    ""|*"/"*|*" "*) return 1 ;;
  esac
  return 0
}

# Samakan prefix storage eksternal ke kanonis /data/media/0.
# Hasil di $_NORM (tanpa fork, tanpa echo).
faacc_norm_ext() {
  _NORM="$1"
  case "$_NORM" in
    /sdcard/*) _NORM="/data/media/0/${_NORM#/sdcard/}" ;;
    /storage/emulated/0/*) _NORM="/data/media/0/${_NORM#/storage/emulated/0/}" ;;
    /storage/self/primary/*) _NORM="/data/media/0/${_NORM#/storage/self/primary/}" ;;
  esac
  case "$_NORM" in
    /mnt/user/[0-9]*/primary/*)
      _NORM=$(echo "$_NORM" | sed 's#^/mnt/user/[0-9][0-9]*/primary/#/data/media/0/#')
      ;;
  esac
}

# Inti cek path (nol fork). Pola diizinkan:
#   /data/data/<pkg>/{cache,code_cache}
#   /data/user/<N>/<pkg>/{cache,code_cache}
#   /data/user_de/<N>/<pkg>/{cache,code_cache}
#   /data/media/0/Android/data/<pkg>/cache
_faacc_path_ok() {
  _sp_pkg="$1"
  _sp_path="$2"
  [ -z "$_sp_pkg" ] || [ -z "$_sp_path" ] && return 1
  case "$_sp_path" in /*) ;; *) return 1 ;; esac
  case "$_sp_path" in *"../"*|*"/.."*|*"*"*|*" "*|*";"*|*"&"*|*"|"*) return 1 ;; esac
  faacc_norm_ext "$_sp_path"; _sp_path="$_NORM"
  case "$_sp_path" in
    "/"|"/data"|"/data/"|"/data/data"|"/data/data/"|"/data/user"|"/data/user/"| \
    "/sdcard"|"/sdcard/"|"/storage"|"/data/media"|"/data/media/"| \
    "/data/media/0"|"/data/media/0/"|"/data/media/0/Android"| \
    "/data/media/0/Android/data"|"/system"|"/vendor"|"/apex") return 1 ;;
  esac
  _ok=1
  for _kind in cache code_cache; do
    [ "$_sp_path" = "/data/data/$_sp_pkg/$_kind" ] && _ok=0
    case "$_sp_path" in
      /data/user/[0-9]*/"$_sp_pkg"/"$_kind"|/data/user_de/[0-9]*/"$_sp_pkg"/"$_kind") _ok=0 ;;
    esac
  done
  unset _kind
  [ "$_sp_path" = "/data/media/0/Android/data/$_sp_pkg/cache" ] && _ok=0
  [ "$_ok" = "0" ] && return 0
  return 1
}

# Ukuran bytes sederet direktori "$@" via SATU panggilan du (1 fork).
# Output: total bytes (angka). Klasifikasi ditulis pemanggil via faacc_du_each.
faacc_du_total() {
  [ $# -eq 0 ] && { echo 0; return 0; }
  _duo=$(du -sk "$@" 2>/dev/null)
  [ -z "$_duo" ] && { echo 0; return 1; }
  _dt=0
  while IFS= read -r _dl; do
    [ -z "$_dl" ] && continue
    read -r _dkb _dp _junk <<EOF_DL
$_dl
EOF_DL
    case "$_dkb" in ''|*[!0-9]*) continue ;; esac
    _dt=$((_dt + _dkb))
  done <<EOF_DU
$_duo
EOF_DU
  unset _duo _dl _dkb _dp _junk
  echo $((_dt * 1024))
}

# Klasifikasi jenis direktori: cetak internal|code_cache|external
faacc_kind() {
  case "$1" in
    */Android/data/*) echo "external" ;;
    */code_cache) echo "code_cache" ;;
    *) echo "internal" ;;
  esac
}

# ---------- SCAN CEPAT ----------
# Satu du per package (bukan per direktori). Nol fork selain du.
# Output per package: pkg|total|internal|code_cache|external
faacc_cmd_scan() {
  for _pkg in "$@"; do
    _light_validate "$_pkg" || continue
    # Kumpulkan kandidat milik pkg (safety + ada + tak-kosong, builtin semua)
    _SEEN=""; _pd=""
    for _root in /data/data "/data/user"/* /data/user_de/*; do
      case "$_root" in
        "/data/user/*"|"/data/user_de/*") continue ;;
      esac
      if [ "$_root" = "/data/data" ]; then
        _try_dir "$_pkg" "/data/data/$_pkg/cache"
        _try_dir "$_pkg" "/data/data/$_pkg/code_cache"
      else
        _try_dir "$_pkg" "$_root/$_pkg/cache"
        _try_dir "$_pkg" "$_root/$_pkg/code_cache"
      fi
    done
    for _eroot in /sdcard/Android/data /data/media/0/Android/data; do
      _try_dir "$_pkg" "$_eroot/$_pkg/cache"
    done
    if [ -z "$_pd" ]; then
      echo "$_pkg|0|0|0|0"
      continue
    fi
    # Satu du untuk semua dir milik pkg ini (default IFS: split newline+spasi;
    # path tervalidasi tanpa spasi, jadi aman). Parse via while+read (nol fork).
    _t=0; _ti=0; _tc=0; _te=0
    set -f
    _duo=$(du -sk $_pd 2>/dev/null)
    set +f
    while IFS= read -r _dl; do
      [ -z "$_dl" ] && continue
      read -r _dkb _dp _junk <<EOF_DL2
$_dl
EOF_DL2
      case "$_dkb" in ''|*[!0-9]*) continue ;; esac
      _b=$((_dkb * 1024))
      _t=$((_t + _b))
      case "$_dp" in
        */Android/data/*) _te=$((_te + _b)) ;;
        */code_cache) _tc=$((_tc + _b)) ;;
        *) _ti=$((_ti + _b)) ;;
      esac
    done <<EOF_DU2
$_duo
EOF_DU2
    unset _duo _dl _dkb _dp _junk _b
    echo "$_pkg|$_t|$_ti|$_tc|$_te"
  done
  unset _pkg _root _eroot _SEEN _pd _t _ti _tc _te
}

# Kandidat -> $_pd ("dir" per baris) bila lolos safety + ada + tak-kosong.
_try_dir() {
  _faacc_path_ok "$1" "$2" || return 0
  [ -d "$2" ] || return 0
  faacc_norm_ext "$2"; _nk="$_NORM"
  case "$_nk" in
    /data/user/0/*) _nk="/data/data/${_nk#/data/user/0/}" ;;
  esac
  case "$_SEEN" in
    *"$_nk"*) return 0 ;;
  esac
  _SEEN="$_SEEN
$_nk"
  for _x in "$2"/* "$2"/.[!.]* "$2"/..?*; do
    [ -e "$_x" ] || [ -L "$_x" ] || continue
    _pd="$_pd
$2"
    break
  done
  unset _nk _x
}

# ---------- CLEAN ----------
# Stub logger (engine embedded: tanpa file log, hasil via stdout).
faacc_log_info() { :; }
faacc_log_scan() { :; }
faacc_log_clean() { :; }
faacc_log_warn() { echo "WARN: $*" >&2; }
faacc_log_error() { echo "ERROR: $*" >&2; }

# Hapus ISI dir saja. Return: 0 sukses, 1 abort, 2 tak-ada, 3 gagal verify.
# Echo: bytes yang dibebaskan.
clean_one_dir() {
  _pkg="$1"
  _dir="$2"
  _light_validate "$_pkg" || return 1
  _faacc_path_ok "$_pkg" "$_dir" || return 1
  [ -e "$_dir" ] || return 2
  [ -d "$_dir" ] || return 1
  _before=$(faacc_du_total "$_dir")
  rm -rf "$_dir"/* 2>/dev/null
  for _dot in "$_dir"/.[!.]* "$_dir"/..?*; do
    case "$_dot" in
      "$_dir/."|"$_dir/..") continue ;;
    esac
    [ -e "$_dot" ] || [ -L "$_dot" ] || continue
    case "$_dot" in "$_dir"/*) rm -rf "$_dot" 2>/dev/null ;; esac
  done
  unset _dot
  [ -d "$_dir" ] || return 1
  _after=$(faacc_du_total "$_dir")
  case "$_after" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_after" -le 65536 ] || return 3
  _freed=$((_before - _after))
  [ "$_freed" -lt 0 ] && _freed=0
  echo "$_freed"
  unset _pkg _dir _before _after _freed
  return 0
}

# Clean 1 package (semua jenis). Output: pkg|freed|rc
faacc_cmd_clean() {
  for _pkg in "$@"; do
    _light_validate "$_pkg" || { echo "$_pkg|0|1"; continue; }
    _freed_total=0; _rc=0; _any=0
    _SEEN=""
    for _root in /data/data "/data/user"/* /data/user_de/*; do
      case "$_root" in
        "/data/user/*"|"/data/user_de/*") continue ;;
      esac
      if [ "$_root" = "/data/data" ]; then
        _clean_try "$_pkg" "/data/data/$_pkg/cache"
        _clean_try "$_pkg" "/data/data/$_pkg/code_cache"
      else
        _clean_try "$_pkg" "$_root/$_pkg/cache"
        _clean_try "$_pkg" "$_root/$_pkg/code_cache"
      fi
    done
    for _eroot in /sdcard/Android/data /data/media/0/Android/data; do
      _clean_try "$_pkg" "$_eroot/$_pkg/cache"
    done
    [ "$_any" = "0" ] && _rc=2
    echo "$_pkg|$_freed_total|$_rc"
  done
  unset _pkg _root _eroot _freed_total _rc _any _SEEN
}

# Coba bersihkan 1 dir kandidat (dengan dedup). Set _any=1 bila ada target.
_clean_try() {
  _faacc_path_ok "$1" "$2" || return 0
  [ -d "$2" ] || return 0
  faacc_norm_ext "$2"; _nk="$_NORM"
  case "$_nk" in
    /data/user/0/*) _nk="/data/data/${_nk#/data/user/0/}" ;;
  esac
  case "$_SEEN" in
    *"$_nk"*) unset _nk; return 0 ;;
  esac
  _SEEN="$_SEEN
$_nk"
  unset _nk
  _any=1
  _out=$(clean_one_dir "$1" "$2" 2>/dev/null)
  _st=$?
  if [ "$_st" -eq 0 ]; then
    case "$_out" in ''|*[!0-9]*) ;; *) _freed_total=$((_freed_total + _out)) ;; esac
  else
    _rc="$_st"
  fi
  unset _out _st
}

# ---------- ROUTER ----------
# Bila di-source ( testing / reuse fungsi ), jangan eksekusi driver.
case "${0##*/}" in
  engine.sh) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac
case "$1" in
  --scan) shift; faacc_cmd_scan "$@" ;;
  --clean) shift; faacc_cmd_clean "$@" ;;
  *) echo "Pakai: engine.sh --scan pkg... | engine.sh --clean pkg..." >&2; exit 1 ;;
esac
