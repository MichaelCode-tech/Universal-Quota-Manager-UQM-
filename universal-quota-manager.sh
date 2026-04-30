#!/usr/bin/env bash
# Universal Quota & Folder Manager (Final)
# Author: MichaelCode-tech (improved UX version)

set -euo pipefail
IFS=$'\n\t'
VERSION="3.1"

require_root(){ [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }
is_cmd(){ command -v "$1" >/dev/null 2>&1; }
pause(){ read -rp "Press Enter to continue..."; }
log(){ echo -e "$@"; }

# =============================
# INSTALL TOOLS
# =============================
install_tools(){
  if is_cmd apt-get; then
    apt-get update -y && apt-get install -y quota xfsprogs btrfs-progs
  elif is_cmd dnf; then
    dnf install -y quota xfsprogs btrfs-progs
  elif is_cmd pacman; then
    pacman -Sy --noconfirm quota xfsprogs btrfs-progs
  elif is_cmd apk; then
    apk add quota xfsprogs btrfs-progs
  else
    log "Install quota, xfsprogs, btrfs-progs manually."
  fi
}

# =============================
# MOUNT SELECTION
# =============================
select_mount(){
  findmnt -o TARGET,SOURCE,FSTYPE -rn
  read -rp "Mount point: " M
  echo "$M"
}

# =============================
# ENABLE QUOTAS
# =============================
enable_quota(){
  M=$(select_mount)
  FST=$(findmnt -n -o FSTYPE --target "$M")

  case "$FST" in
    ext*)
      mount -o remount,usrquota,grpquota "$M" || true
      quotacheck -cum "$M" || true
      quotaon "$M" || true
      ;;
    xfs)
      mount -o remount,pquota "$M" || true
      ;;
    btrfs)
      btrfs quota enable "$M" || true
      ;;
    *)
      echo "Unsupported FS"
      ;;
  esac

  log "Quota enabled on $M"
}

# =============================
# USER / GROUP QUOTAS
# =============================
set_user_quota(){
  M=$(select_mount)
  read -rp "User: " U
  read -rp "Soft KB: " S
  read -rp "Hard KB: " H
  setquota -u "$U" "$S" "$H" 0 0 "$M"
}

set_group_quota(){
  M=$(select_mount)
  read -rp "Group: " G
  read -rp "Soft KB: " S
  read -rp "Hard KB: " H
  setquota -g "$G" "$S" "$H" 0 0 "$M"
}

# =============================
# XFS FOLDER QUOTA
# =============================
xfs_project(){
  M=$(select_mount)
  read -rp "Project ID: " ID
  read -rp "Folder path: " DIR
  read -rp "Soft KB: " S
  read -rp "Hard KB: " H

  echo "$ID:$DIR" >> /etc/projects
  echo "proj$ID:$ID" >> /etc/projid

  xfs_quota -x -c "project -s $ID" "$M"
  xfs_quota -x -c "limit -p bsoft=${S}k bhard=${H}k proj$ID" "$M"

  log "XFS folder quota applied"
}

# =============================
# BTRFS FOLDER QUOTA
# =============================
btrfs_qgroup(){
  M=$(select_mount)
  read -rp "Path: " DIR
  read -rp "Qgroup (0/123): " Q
  read -rp "Limit (e.g. 5G): " L

  btrfs subvolume create "$DIR" || true
  btrfs qgroup limit "$L" "$Q" "$M"
}

# =============================
# TMPFS USER RAM LIMIT
# =============================
tmpfs_user(){
  read -rp "User: " U
  read -rp "Size (e.g. 1G): " S

  DIR="/var/tmp/user_tmpfs/$U"
  mkdir -p "$DIR"
  chown "$U":"$U" "$DIR"

  mount -t tmpfs -o size="$S" tmpfs "$DIR"
  grep -q "$DIR" /etc/fstab || echo "tmpfs $DIR tmpfs size=$S 0 0" >> /etc/fstab

  log "Tmpfs created for $U"
}

# =============================
# 🔐 SMART FOLDER PERMISSIONS
# =============================
friendly_permissions_menu(){
  read -rp "Folder path: " DIR

  echo ""
  echo "Choose how this folder should behave:"
  echo "1) Private (only owner can access)"
  echo "2) Shared (everyone can read/write)"
  echo "3) Group shared (only specific group)"
  echo "4) Group shared + files inherit group"
  echo "5) Protect files (users can't delete others' files)"
  echo "6) Read-only for others"
  echo "7) Custom (advanced mode)"
  echo ""

  read -rp "Choice: " CH

  case $CH in
    1)
      chmod 700 "$DIR"
      log "Private folder (owner only)"
      ;;
    2)
      chmod 777 "$DIR"
      log "Fully shared folder"
      ;;
    3)
      read -rp "Group name: " G
      chown :"$G" "$DIR"
      chmod 770 "$DIR"
      log "Group-only access"
      ;;
    4)
      read -rp "Group name: " G
      chown :"$G" "$DIR"
      chmod 2775 "$DIR"
      log "Group shared + inherited group (setgid)"
      ;;
    5)
      chmod 1777 "$DIR"
      log "Sticky mode enabled (like /tmp)"
      ;;
    6)
      chmod 755 "$DIR"
      log "Others can read but not write"
      ;;
    7)
      read -rp "Enter numeric mode (e.g. 1755): " MODE
      chmod "$MODE" "$DIR"
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
}

# =============================
# SHOW
# =============================
show_all(){
  M=$(select_mount)
  repquota "$M" || true
  xfs_quota -x -c 'report -h' "$M" 2>/dev/null || true
  btrfs qgroup show "$M" 2>/dev/null || true
}

# =============================
# MAIN MENU
# =============================
menu(){
  require_root

  while true; do
    clear
    echo "==== Universal Quota & Folder Manager v$VERSION ===="
    echo "1) Install tools"
    echo "2) Enable quota on mount"
    echo "3) Set user quota"
    echo "4) Set group quota"
    echo "5) XFS folder quota"
    echo "6) Btrfs folder quota"
    echo "7) User RAM quota (tmpfs)"
    echo "---- Folder Control ----"
    echo "8) Smart folder permissions (recommended)"
    echo "---- Info ----"
    echo "9) Show quotas"
    echo "10) Exit"

    read -rp "Choice: " C

    case $C in
      1) install_tools ;;
      2) enable_quota ;;
      3) set_user_quota ;;
      4) set_group_quota ;;
      5) xfs_project ;;
      6) btrfs_qgroup ;;
      7) tmpfs_user ;;
      8) friendly_permissions_menu ;;
      9) show_all ;;
      10) exit 0 ;;
      *) echo "Invalid" ;;
    esac

    pause
  done
}

menu
