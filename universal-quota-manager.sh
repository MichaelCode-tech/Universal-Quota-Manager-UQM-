#!/usr/bin/env bash
# Universal Quota & Folder Manager
# Author: MichaelCode-tech

set -euo pipefail
IFS=$'\n\t'

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
# SMART FOLDER PERMISSIONS
# =============================
friendly_permissions_menu(){
  read -rp "Folder path: " DIR

  echo ""
  echo "Choose how this folder should behave:"
  echo "1) Private (only owner)"
  echo "2) Fully shared (everyone)"
  echo "3) Group only"
  echo "4) Group shared + inherit"
  echo "5) Protect files (no delete by others)"
  echo "6) Read-only for others"
  echo "7) Custom mode"
  echo ""

  read -rp "Choice: " CH

  case $CH in
    1) chmod 700 "$DIR" ;;
    2) chmod 777 "$DIR" ;;
    3)
      read -rp "Group: " G
      chown :"$G" "$DIR"
      chmod 770 "$DIR"
      ;;
    4)
      read -rp "Group: " G
      chown :"$G" "$DIR"
      chmod 2775 "$DIR"
      ;;
    5) chmod 1777 "$DIR" ;;
    6) chmod 755 "$DIR" ;;
    7)
      read -rp "Mode: " M
      chmod "$M" "$DIR"
      ;;
    *) echo "Invalid" ;;
  esac
}

# =============================
# QUOTA VIEWER
# =============================
quota_view_menu(){

  echo ""
  echo "==== Quota Viewer ===="
  echo "1) User quotas"
  echo "2) Group quotas"
  echo "3) Folder quotas (XFS/Btrfs)"
  echo "4) Partition usage"
  echo "5) RAM quotas (tmpfs)"
  echo ""

  read -rp "Choice: " QV

  case $QV in
    1) repquota -a 2>/dev/null || quota -v ;;
    2) repquota -g -a 2>/dev/null || true ;;
    3)
      M=$(select_mount)
      xfs_quota -x -c 'report -h' "$M" 2>/dev/null || true
      btrfs qgroup show -pcre "$M" 2>/dev/null || true
      ;;
    4)
      M=$(select_mount)
      df -h "$M"
      quotaon -p "$M" 2>/dev/null || true
      ;;
    5)
      BASE="/var/tmp/user_tmpfs"
      [[ ! -d "$BASE" ]] && echo "No tmpfs quotas found." && return

      for d in "$BASE"/*; do
        [[ -d "$d" ]] || continue
        echo ""
        echo "User: $(basename "$d")"
        df -h "$d" | awk 'NR==1 || NR==2'
      done
      ;;
    *) echo "Invalid" ;;
  esac
}

# =============================
# MAIN MENU
# =============================
menu(){
  require_root

  while true; do
    clear
    echo "==== Universal Quota & Folder Manager ===="
    echo "Author: MichaelCode-tech"
    echo ""
    echo "1) Install tools"
    echo "2) Enable quota on mount"
    echo "3) Set user quota"
    echo "4) Set group quota"
    echo "5) XFS folder quota"
    echo "6) Btrfs folder quota"
    echo "7) User RAM quota"
    echo "---- Folder Control ----"
    echo "8) Smart folder permissions"
    echo "---- View ----"
    echo "9) Quota viewer"
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
      9) quota_view_menu ;;
      10) exit 0 ;;
      *) echo "Invalid" ;;
    esac

    pause
  done
}

menu
