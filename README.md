Universal Quota & Folder Manager (UQFM)  
Author: MichaelCode-tech  
Version: 3.1

A compact, interactive bash utility to enable and manage disk quotas (ext*, XFS, Btrfs), folder permissions and per-user tmpfs (RAM) quotas. Intended for system administrators who want a single menu-driven tool to configure per-user/group quotas, XFS project quotas, Btrfs qgroups, and to apply safe folder permission patterns (including sticky/setgid behavior).

Quick highlights
- Interactive menu for common quota tasks (enable, set, show, remove).
- XFS project support (manages /etc/projects + /etc/projid and xfs_quota).
- Btrfs qgroup support (subvolumes + qgroup limits).
- ext* user/group quotas via setquota/quotacheck/quoton.
- Per-user tmpfs mounts for RAM-limited temporary directories.
- “Smart” folder permissions presets: private, shared, group-shared, setgid, sticky, etc.
- Best-effort package installer for major distros (apt, dnf, pacman, apk).
- Designed to be safe: backups and non-destructive defaults where possible.

Requirements
- Root privileges (script will exit if not run as root).
- bash (script uses bash features).
- Recommended tools (script can attempt installation): quota (setquota/repquota/quotacheck), xfsprogs (xfs_quota), btrfs-progs (btrfs).
- Tested on major Linux distros; FreeBSD support is minimal.

Security & safety summary
- Run only on systems you control; test on non-production first.
- The script may modify:
  - /etc/fstab (backed up to /etc/fstab.bak when modified)
  - /etc/projects and /etc/projid (appended for XFS)
  - aquota.user / aquota.group files on target mounts
- Back up critical data and configuration before changing quotas.
- Btrfs qgroups and XFS project quotas can affect applications—plan and test limits carefully.

Installation
1. Clone the repo (example):
   ```
   git clone https://github.com/MichaelCode-tech/Universal-Quota-Manager-UQM-.git
   cd Universal-Quota-Manager-UQM
   ```
2. Make the script executable:
   ```
   chmod +x universal-quota-manager.sh
   ```
3. Run it as root:
   ```
   sudo ./universal-quota-manager.sh
   ```

Primary features & menu overview
- Install tools — attempts to install quota, xfsprogs, btrfs-progs with host package manager.
- Enable quota on mount — detects filesystem type and enables appropriate quota mechanism:
  - ext*: remounts with usrquota,grpquota; creates quota files; runs quotacheck + quotaon.
  - XFS: remounts with pquota and prepares xfs_quota usage.
  - Btrfs: runs btrfs quota enable.
- Set user/group quota — setquota (soft/hard KB, inode defaults).
- XFS folder quota — add project mapping to /etc/projects & /etc/projid, set project limits with xfs_quota.
- Btrfs qgroup — create subvolume (optional) and apply qgroup limits.
- User RAM quota — per-user tmpfs mount with optional /etc/fstab persistence.
- Smart folder permissions — presets:
  - Private (700)
  - Shared (777)
  - Group-only (770)
  - Group shared + inherited group (setgid, 2775)
  - Sticky (1777, prevents deletion of others’ files)
  - Read-only for others (755)
  - Custom numeric mode
- Show quotas — repquota/xfs_quota/btrfs qgroup show combined output.

Examples
- Enable quotas on /home:
  - Start script → choose "Enable quota on mount" → enter /home.
- Create an XFS project quota:
  - Start script → XFS folder quota → project ID 1775 → folder /srv/projects/projectA → set soft/hard KB.
- Create a per-user tmpfs of 1G:
  - Start script → User RAM quota → username → 1G.
- Make /data shared for a group devs with inherited group:
  - Start script → Smart folder permissions → choose Group shared + inherit → enter group devs → folder path /data.

Implementation details (concise)
- Uses findmnt to discover mounts and filesystem types.
- Ext*: safe editing/remounting with quota options; creates aquota files and runs quotacheck/quoton.
- XFS: appends /etc/projects and /etc/projid mappings and calls xfs_quota to apply and report limits; uses chattr +P/xfs_io where needed.
- Btrfs: can create subvolumes and uses btrfs qgroup limit; requires qgroup planning.
- Tmpfs: mounts per-user tmpfs under /var/tmp/user_tmpfs/<user> and can add fstab entries for persistence.

Files touched / created
- /etc/fstab (backed up when modified)
- /etc/projects and /etc/projid (for XFS)
- aquota.user, aquota.group on target mounts
- /var/tmp/user_tmpfs/<user> (tmpfs mounts)

Limitations & caveats
- Non-interactive CLI/subcommand mode is not implemented; functions can be adapted for automation.
- Complex enterprise workflows (recursive Btrfs qgroup strategies, cross-subvolume inheritance) are beyond this helper’s scope.
- Behavior depends on distribution tools and kernel support (e.g., pquota for XFS).
- XFS project IDs and Btrfs qgroup IDs must be planned to avoid conflicts—script does not centrally track IDs.

Troubleshooting (common issues)
- quotacheck fails: run on unmounted filesystem if possible or during low I/O; ensure quota tools are installed.
- setquota not found: install your distro’s quota package.
- xfs_quota errors: ensure xfsprogs is installed and fs was mounted with project/pquota support.
- btrfs qgroup errors: enable qgroups first with btrfs quota enable <mount> and ensure subvolume path is inside the mount.

Best practices
- Use separate subvolumes or mountpoints for quota-managed datasets when possible.
- Reserve a clear range for XFS project IDs (e.g., 1000–1999) and document usage.
- For Btrfs, map qgroups to logical allocations and avoid ad-hoc numbering.
- Monitor quota reports regularly (repquota, xfs_quota report -h, btrfs qgroup show).

Changelog (selected)
- v3.1 — Improved UX, tmpfs per-user, smart folder permissions, consolidated menu.
- v2.0 — XFS project and Btrfs qgroup helpers, per-user tmpfs, backups for /etc/*.
- v1.0 — Initial interactive release (quotas for ext*, XFS, Btrfs).

License
- MIT License — include LICENSE file in repository.

Contributing
- Open issues or submit PRs with test details (distro + kernel + tool versions).
- Suggested enhancements: non-interactive flags, dry-run mode, central ID registry, unit/integration tests.

Contact
Author: MichaelCode-tech

---
