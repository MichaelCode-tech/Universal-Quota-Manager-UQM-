#!/usr/bin/env bash
# universal-quota-manager.sh
# Author: MichaelCode-tech
# Universal Quota Manager: interactive menu for ext*, XFS (xfs_quota), Btrfs qgroup, and FreeBSD basics.
# MUST BE RUN AS ROOT. Test on non-production before use.

set -euo pipefail
IFS=$'\n\t'
VERSION="1.0"

QUIET=0
pause(){ read -rp "Press Enter to continue..."; }

is_cmd(){ command -v "$1" >/dev/null 2>&1; }
require_root(){ if [[ $EUID -ne 0 ]]; then echo "Run as root."; exit 1; fi }

log(){ [[ $QUIET -eq 1 ]] || echo -e "$@"; }

detect_os(){
  if [[ -f /etc/os-release ]]; then . /etc/os-release; echo "${ID:-linux}"; return; fi
  if is_cmd uname && [[ "$(uname -s)" == "FreeBSD" ]]; then echo "freebsd"; return; fi
  echo "unknown"
}

install_tools(){
  # Install quota utilities and filesystem-specific tools if missing
  if is_cmd apt-get; then
    apt-get update -y
    apt-get install -y quota xfsprogs btrfs-progs || true
  elif is_cmd dnf; then
    dnf install -y quota xfsprogs btrfs-progs || true
  elif is_cmd yum; then
    yum install -y quota xfsprogs btrfs-progs || true
  elif is_cmd pacman; then
    pacman -Sy --noconfirm quota xfsprogs btrfs-progs || true
  elif is_cmd apk; then
    apk add --no-cache quota xfsprogs btrfs-progs || true
  elif is_cmd xbps-install; then
    xbps-install -Sy quota xfsprogs btrfs-progs || true
  else
    log "Package manager not detected. Please install: quota, xfsprogs, btrfs-progs manually."
  fi
}

list_mounts(){
  findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS -rn
}

select_mount(){
  echo "Mounted filesystems:"
  list_mounts
  read -rp "Enter mount point (e.g. /, /home): " MOUNT
  MOUNT=${MOUNT:-/}
  echo "$MOUNT"
}

enable_quota_ext(){
  local m=$1
  log "Enabling user/group quotas on $m (ext) ..."
  # Remount with usrquota,grpquota
  if ! mount | grep -q " on $m .*usrquota"; then
    mount -o remount,usrquota,grpquota "$m" || {
      log "Remount failed; updating /etc/fstab and remounting."
      cp /etc/fstab /etc/fstab.bak
      sed -E -i.bak "/[[:space:]]${m}[[:space:]]/ s/(defaults|[^[:space:]]+)/\\0,usrquota,grpquota/" /etc/fstab || true
      mount -o remount "$m" || true
    }
  fi
  touch "${m}/aquota.user" "${m}/aquota.group" 2>/dev/null || true
  chmod 600 "${m}/aquota."* 2>/dev/null || true
  quotacheck -cum "$m" || quotacheck -avug || true
  quotaon -v "$m" || quotaon -av || true
  log "Quotas enabled on $m."
}

enable_quota_xfs(){
  local m=$1
  log "Enabling XFS quotas (project/user/group) on $m ..."
  mount -o remount,pquota "$m" || mount -o remount,usrquota,grpquota "$m" || true
  # XFS: ensure xfs_quota available
  if ! is_cmd xfs_quota; then log "xfs_quota not found; install xfsprogs"; return; fi
  # create marker files
  touch "${m}/aquota.user" "${m}/aquota.group" 2>/dev/null || true
  chmod 600 "${m}/aquota."* 2>/dev/null || true
  xfs_quota -x -c 'state' "$m" 2>/dev/null || true
  log "XFS quota state shown above. Use xfs_quota for project quotas."
}

enable_quota_btrfs(){
  local m=$1
  log "Enabling Btrfs quota on $m (enables qgroup tracking)..."
  if ! is_cmd btrfs; then log "btrfs tool not found; install btrfs-progs"; return; fi
  btrfs quota enable "$m" || true
  log "Btrfs qgroups enabled. Use 'btrfs qgroup' to manage."
}

disable_quota(){
  local m=$1
  log "Turning off quotas on $m ..."
  quotaoff -v "$m" || true
  if is_cmd xfs_quota; then xfs_quota -x -c 'state' "$m" 2>/dev/null || true; fi
  if is_cmd btrfs; then btrfs quota disable "$m" 2>/dev/null || true; fi
  log "Quotas disabled (best-effort)."
}

set_quota_user(){
  local m=$1; shift
  local user=$1; local soft=$2; local hard=$3; local in_soft=${4:-0}; local in_hard=${5:-0}
  setquota -u "$user" "$soft" "$hard" "$in_soft" "$in_hard" "$m"
  log "User quota set: $user on $m -> ${soft}/${hard} KB"
}

set_quota_group(){
  local m=$1; shift
  local group=$1; local soft=$2; local hard=$3; local in_soft=${4:-0}; local in_hard=${5:-0}
  setquota -g "$group" "$soft" "$hard" "$in_soft" "$in_hard" "$m"
  log "Group quota set: $group on $m -> ${soft}/${hard} KB"
}

show_quotas(){
  repquota -a 2>/dev/null || repquota "$1" 2>/dev/null || quota -v || true
}

remove_quota_entry(){
  # remove user/group quota entry (set zeros)
  local m=$1; local type=$2; local name=$3
  if [[ $type == "user" ]]; then
    setquota -u "$name" 0 0 0 0 "$m"
  else
    setquota -g "$name" 0 0 0 0 "$m"
  fi
  log "Quota entry removed (zeros applied) for $name"
}

xfs_project_add(){
  local m=$1; local proj=$2; local path=$3; local soft=$4; local hard=$5
  # Add project id and assign path
  echo "$proj:$path" >> /etc/projects 2>/dev/null || true
  echo "$proj:$proj" >> /etc/projid 2>/dev/null || true
  xfs_quota -x -c "project -s $proj" "$m" || true
  xfs_quota -x -c "limit -p bhard=$hard bsoft=$soft $proj" "$m" || true
  log "XFS project quota added: $proj -> $path soft:$soft hard:$hard"
}

btrfs_qgroup_set(){
  local m=$1; local qgroup=$2; local quota=$3
  btrfs qgroup limit "$quota" "$qgroup" "$m" || true
  log "Btrfs qgroup limit set: $qgroup -> $quota"
}

menu_install(){
  echo "Install required tools? (quota, xfsprogs, btrfs-progs)"
  read -rp "Install now? [y/N]: " ans
  [[ "$ans" =~ ^[Yy] ]] && install_tools
  pause
}

menu_enable(){
  MOUNT=$(select_mount)
  FST=$(findmnt -n -o FSTYPE --target "$MOUNT")
  echo "Filesystem type: $FST"
  case "$FST" in
    ext*|ext4|ext3|ext2) enable_quota_ext "$MOUNT" ;;
    xfs) enable_quota_xfs "$MOUNT" ;;
    btrfs) enable_quota_btrfs "$MOUNT" ;;
    *) echo "Unsupported filesystem: $FST" ;;
  esac
  pause
}

menu_disable(){
  MOUNT=$(select_mount)
  disable_quota "$MOUNT"
  pause
}

menu_set(){
  MOUNT=$(select_mount)
  echo "Set quota for: 1) User 2) Group 3) XFS Project 4) Btrfs qgroup"
  read -rp "Choice: " c
  case $c in
    1)
      read -rp "Username: " name
      read -rp "Soft KB: " soft
      read -rp "Hard KB: " hard
      read -rp "Soft inodes (0): " is; is=${is:-0}
      read -rp "Hard inodes (0): " ih; ih=${ih:-0}
      set_quota_user "$MOUNT" "$name" "$soft" "$hard" "$is" "$ih"
      ;;
    2)
      read -rp "Groupname: " name
      read -rp "Soft KB: " soft
      read -rp "Hard KB: " hard
      read -rp "Soft inodes (0): " is; is=${is:-0}
      read -rp "Hard inodes (0): " ih; ih=${ih:-0}
      set_quota_group "$MOUNT" "$name" "$soft" "$hard" "$is" "$ih"
      ;;
    3)
      read -rp "Project ID (number): " pid
      read -rp "Path (absolute): " ppath
      read -rp "Soft KB: " soft
      read -rp "Hard KB: " hard
      xfs_project_add "$MOUNT" "$pid" "$ppath" "$soft" "$hard"
      ;;
    4)
      read -rp "qgroup (e.g. 0/1234): " qg
      read -rp "Quota (e.g. 5G): " ql
      btrfs_qgroup_set "$MOUNT" "$qg" "$ql"
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
  pause
}

menu_show(){
  MOUNT=$(select_mount)
  show_quotas "$MOUNT"
  if is_cmd xfs_quota; then xfs_quota -x -c 'report -h' "$MOUNT" 2>/dev/null || true; fi
  if is_cmd btrfs; then btrfs qgroup show -pcre "$MOUNT" 2>/dev/null || true; fi
  pause
}

menu_remove(){
  MOUNT=$(select_mount)
  echo "Remove quota entry for: 1) User 2) Group"
  read -rp "Choice: " c
  case $c in
    1) read -rp "Username: " name; remove_quota_entry "$MOUNT" user "$name" ;;
    2) read -rp "Groupname: " name; remove_quota_entry "$MOUNT" group "$name" ;;
    *) echo "Invalid" ;;
  esac
  pause
}

menu_help(){
  cat <<EOF
Universal Quota Manager - v$VERSION
Author: MichaelCode-tech

Options:
  Install tools - installs quota, xfsprogs, btrfs-progs where available
  Enable/Disable quotas - automatically handles ext*, XFS, Btrfs best-effort
  Set quotas - user, group, XFS project, Btrfs qgroup
  Show quotas - repquota, xfs_quota report, btrfs qgroup show
  Remove quota - zero out a user/group quota entry
EOF
  pause
}

main_menu(){
  require_root
  while true; do
    clear
    echo "==== Universal Quota Manager (Author: MichaelCode-tech) ===="
    echo "1) Install required tools"
    echo "2) Enable quotas on mount"
    echo "3) Disable quotas on mount"
    echo "4) Set quota (user/group/XFS/Btrfs)"
    echo "5) Show quotas"
    echo "6) Remove quota entry"
    echo "7) Help"
    echo "8) Exit"
    read -rp "Choose [1-8]: " choice
    case $choice in
      1) menu_install ;;
      2) menu_enable ;;
      3) menu_disable ;;
      4) menu_set ;;
      5) menu_show ;;
      6) menu_remove ;;
      7) menu_help ;;
      8) echo "Bye."; exit 0 ;;
      *) echo "Invalid." ; pause ;;
    esac
  done
}

main_menu

