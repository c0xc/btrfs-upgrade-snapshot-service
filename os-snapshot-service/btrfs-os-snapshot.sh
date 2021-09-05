#!/bin/bash

# Set nullglob (don't handle '${snap_name}.*')
shopt -s nullglob

# Check if run as root
if [ "$EUID" -ne 0 ]; then
    echo "btrfs snapshot script must be run as root" >&2
    exit 1
fi

# Check for BTRFS root volume
if ! [ `stat --format=%i /` -eq 256 ]; then
    # / does not appear to be a BTRFS volume, nothing to do
    echo "(/ does not appear to be a BTRFS volume, skipping snapshot step)" >&2
    exit
fi

# Arguments and options
run_snap=0
run_check=0
run_list=0
run_mount=0
run_umount=0
run_restore=0
confirm_restore=
keep_boot_backup=
discard_mount=0
arg=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--debug)
            IS_DEBUG=1
            ;;
        --keep-boot-backup)
            keep_boot_backup=1
            ;;
        --discard-boot-backup)
            keep_boot_backup=0
            ;;
        --confirm-restore)
            confirm_restore=y
            ;;
        --discard-mount)
            discard_mount=1
            ;;
        check)
            ;;
        list)
            ;;
        mount)
            ;;
        umount)
            ;;
        restore)
            ;;
        --) break ;;
        -*)
            echo "Option not recognized: $1" >&2
            exit 1
            ;;
        *)
            ;;
    esac
    if ! [[ ${1::1} = "-" ]]; then
        arg+=($1)
    fi
    shift
done
if [[ -z "${arg[0]}" || "${arg[0]}" = "create" ]]; then
    run_snap=1
elif [[ "${arg[0]}" = "check" ]]; then
    run_check=1
elif [[ "${arg[0]}" = "list" ]]; then
    run_list=1
elif [[ "${arg[0]}" = "mount" ]]; then
    run_mount=1
elif [[ "${arg[0]}" = "umount" ]]; then
    run_umount=1
elif [[ "${arg[0]}" = "restore" ]]; then
    run_restore=1
else
    echo "Command not recognized: ${arg[0]}" >&2
    exit 1
fi

# root root root
# In a default installation of Fedora, the root filesystem is put on a btrfs subvolume "root",
# it's mounted with subvol=root. This allows us to create a read-only snapshot of "root"
# in the snapshot root and revert to an old snapshot by cloning it into the btrfs root as "root".
# Furthermore, /home should be on a separate subvolume or partition
# because otherwise user data would be part of the snapshot and would be lost/inaccessible
# when restoring an old snapshot.
# The btrfs root is simply the root of the btrfs filesystem (subvol=/).
# The snapshot root is the location where the snapshots are created.
# It should probably be /.snapshot directly under the btrfs root.
# Since /boot is most certainly not part of / (because of Grub),
# a backup copy of /boot will be saved as tar file in /var/tmp/backup.
# TODO check if /var is a separate filesystem

# Determine name of root subvolume
# Extract "subvol=/root" mount option
mount_line0=$(mount -v | grep ' on / ')
mount_line1=$(mount -v | grep ' on / ' | grep btrfs)
if [[ $? -ne 0 ]]; then
    echo "btrfs root mount (/) not found!" >&2
    echo "found: $mount_line0" >&2
    exit 1
fi
rx_subvol=',subvol=(.+)[,)]'
rx_azname='^[/][a-z0-9_-]+$'
if [[ "$mount_line1" =~ $rx_subvol ]]; then
    root_subvol="${BASH_REMATCH[1]}"
else
    echo "root subvolume not found in mount options! / must be on a separate subvolume (default: root)" >&2
    exit 1
fi
if [[ -z "$root_subvol" || "$root_subvol" = "/" ]]; then
    echo "the root filesystem / does not appear to be on a separate subvolume (default: root)!" >&2
    exit 1
fi
if ! [[ "$root_subvol" =~ $rx_azname ]]; then
    echo "invalid subvolume name for /: $root_subvol" >&2
    exit 1
fi
# $root_subvol == root (or similar)

# Root device like /dev/sda2 (if sda1 is /boot and sda3 /home or whatever)
root_device=$(echo "$mount_line0" | cut -f1 -d' ') || exit 1

# Path used as root mountpoint for / (top level, above root)
mount_base=/tmp/.tmp_mnt_root_btrfs
if [[ -d /run/ ]]; then
    mount_base=/run/.tmp_mnt_root_btrfs
fi
root_mount="$mount_base/root"

# Create mountpoint for / (top level, above root)
if ! [[ -d "$mount_base" ]]; then
    mkdir -m 700 "$mount_base" || exit 1
else
    if [[ -e "$root_mount" ]]; then
        # Temporary mountpoint from previous(?) run found
        if (( discard_mount )); then
            umount "$root_mount"
            rmdir "$root_mount"
        else
            date=$(date -r "$mount_base")
            echo "working directory / mountpoint found, script currently running - or aborted (created $date)" >&2
            echo "use --discard-mount to reset only if the script isn't running anymore" >&2
            exit 1
        fi
    fi
fi
mkdir -m 0 "$root_mount" || exit 1

# Mount helper
function mount_root {
    mount -o subvol=/ "$root_device" "$root_mount"
    if [[ $? -ne 0 ]]; then
        echo "failed to mount $root_device (subvol=/) on $root_mount" >&2
        exit 1
    fi
}
mount_root

# Prepare unmount of /
function unmount_root {
    umount "$root_mount"
    rmdir "$root_mount"
}
function finish {
    # cleanup routine
    if [[ -n "$FINISH_DELAY" ]]; then
        sleep "$FINISH_DELAY"
    fi
    unmount_root
}
#trap finish EXIT INT
trap finish EXIT

# Check if /home is a (separate) BTRFS volume
# This is HIGHLY RECOMMENDED because otherwise,
# each os snapshot will also contain user files, possibly large images etc.
# These would continue to use disk space even when the user removes those files
# as long as the snapshot (we're about to create) still exists.
# TODO provide help (script/function/call) to migrate /home to a BTRFS volume?
if ! [ `stat --format=%i /home` -eq 256 ]; then
    echo "WARNING: /home does not appear to be a BTRFS volume! NOT RECOMMENDED!" >&2
    echo "WARNING: The os snapshot will contain user files from /home. Use btrfs sub... later to delete this os snapshot if it holds too much space..." >&2
fi

# Check for BTRFS control program (required)
# BTRFS=${BTRFS:-/sbin/btrfs}
# Debian has it in a different place: /bin/btrfs
BTRFS=/usr/sbin/btrfs
if ! [ -x "$BTRFS" ]; then
    [ -x "/sbin/btrfs" ] && BTRFS=/sbin/btrfs
fi
if ! [ -x "$BTRFS" ]; then
    [ -x "/bin/btrfs" ] && BTRFS=/bin/btrfs
fi
if ! [ -x "$BTRFS" ]; then
    echo "btrfs binary not found, unable to create os snapshot" >&2
    exit 1
fi

# Are we root?
if ((EUID)); then echo
    echo "snapshot script must be run as root" >&2
    exit 1
fi

# Snapshot name, base
current_date=$(date +%F) || exit 1
rx_snap_name='^root_snap_([0-9]{4}-[0-9]{2}-[0-9]{2})([_.-][0-9]+)?$'
btrfs_root=$root_mount
snap_root="$btrfs_root/.snapshot"
snap_name="root_snap_$current_date"

# Get list of existing snapshots (created by this script / matching the name pattern)
if ! [[ -x "$snap_root" ]]; then
    echo "failed to read snapshot root: $snap_root" >&2
    exit 1
fi

# Find existing snapshots
declare -A snap_map_date
declare -A snap_map_id
declare -a old_snaps
old_snaps=()
while IFS= read -r -d ''; do
    line="$REPLY"
    name="${line##*/}"
    # Filter contents of snapshot root by snapshot name (must contain date)
    if ! [[ "$name" =~ $rx_snap_name ]]; then
        # "root" or other top level subvolume (could even be a directory)
        continue
    fi
    # Make sure it contains a "root" subdirectory (sub-snapshot)
    if ! ls "$snap_root/$name/root" >/dev/null; then
        # "root" sub element not found (the actual snapshot)
        echo "snapshot root not found within snapshot container: $name" >&2
        continue
    fi
    # Add element to list of snapshots
    old_snaps+=("$name")
    btrfs_date=$($BTRFS subvolume show "$snap_root/$name" | grep Creation) || exit $?
    btrfs_date=$(echo "${btrfs_date#*:}" | sed -e 's/^[[:space:]]*//')
    snap_map_date["$name"]=$btrfs_date
    btrfs_id=$($BTRFS subvolume show "$snap_root/$name" | grep 'Subvolume ID') || exit $?
    btrfs_id=$(echo "${btrfs_id#*:}" | sed -e 's/^[[:space:]]*//')
    snap_map_id["$name"]=$btrfs_id

done < <(find "$snap_root" -mindepth 1 -maxdepth 1 -type d -print0)

# SNAP
if ((run_snap)); then

    # Create backup directory for /boot
    # This backup directory should be stored on the root volume
    # that we're about to make a snapshot of [assuming /var isn't a separate volume]
    # so that the backup copy of /boot is part of the os snapshot.
    backup_root=/var/tmp/backup
    mp_var=$(df /var/tmp/ | tail -n1 | cut -f1 -d' ')
    mp_root=$(df / | tail -n1 | cut -f1 -d' ')
    if [[ -n "$mp_var" && "$mp_var" != "$mp_root" ]]; then
        # Default backup directory appears to be on a different filesystem
        # Use / instead
        backup_root=/
        if [[ -z "$keep_boot_backup" ]]; then
            keep_boot_backup=0
        fi
    fi
    if [[ -z "$keep_boot_backup" ]]; then
        keep_boot_backup=1
    fi
    if ! [ -d "$backup_root" ]; then
        if ! mkdir "$backup_root"; then
            echo "failed to create backup dir: $backup_root" >&2
            exit 1
        fi
    fi

    # Create backup tarball of /boot on root filesystem
    boot_backup_file="$backup_root/boot.tar.gz"
    echo "creating backup of /boot in $boot_backup_file"
    (cd / && tar czf "$boot_backup_file" boot)
    if [ $? -ne 0 ]; then
        echo "failed to create backup of /boot in $backup_root" >&2
        exit 1
    fi

    ###

    # Check for, create snapshot root (e.g., /.snapshot)
    if ! [ -e "$snap_root" ]; then
        $BTRFS subvolume create "$snap_root"
        if [ $? -ne 0 ]; then
            echo "failed to create snapshot root: $snap_root" >&2
            exit 1
        fi
    fi
    # Double-check snapshot root
    if ! [ `stat --format=%i $snap_root` -eq 256 ]; then
        echo "snapshot root $snap_root does not appear to be a separate subvolume" >&2
        exit 1
    fi

    # Create container snapshot volume within snapshot root (e.g., /.snapshot/2021-07-31.2)
    snap_vol="$snap_root/$snap_name"
    if [ -d "$snap_vol" ]; then
        for ((i=2;; i++)); do
            if ! [ -d "$snap_vol.$i" ]; then
                # append counter/number as suffix
                snap_vol="$snap_vol.$i"
                break
            fi
        done
    fi
    $BTRFS subvolume create "$snap_vol"
    if [ $? -ne 0 ]; then
        echo "failed to create snapshot volume: $snap_vol" >&2
        exit 1
    fi

    # Create os snapshot within new container snapshot volume
    snap_src=/
    echo "OS BACKUP - creating snapshot of $snap_src in $snap_vol..."
    $BTRFS subvolume snapshot -r $snap_src "$snap_vol/root"
    if [ $? -ne 0 ]; then
        echo "failed to create $snap_src snapshot in $snap_vol" >&2
        exit 1
    fi
    echo "os snapshot created on $(date)" >>"$snap_vol/INFO"

    # Clean up /boot backup file on live filesystem
    if ! (( $keep_boot_backup )); then
        rm -fv "$boot_backup_file"
    fi

# LIST
elif ((run_list)); then

    if [[ "${#old_snaps[@]}" -eq 0 ]]; then
        echo "(snapshot root empty: $snap_root)"
        echo "no snapshots found"
        exit
    fi
    for snap in "${old_snaps[@]}"; do
        date_f=${snap_map_date["$snap"]}
        echo "* $snap"
        echo "  $date_f"
    done

# MOUNT
elif ((run_mount)); then

    snap=${arg[1]}
    if [[ -z "$snap" ]]; then
        echo "snapshot name not specified" >&2
        exit 1
    fi
    if [[ -z "${snap_map_date["$snap"]}" ]]; then
        echo "specified snapshot not found: $snap" >&2
        exit 1
    fi

    mountpoint="/mnt/$snap"
    if [[ -d "$mountpoint" ]]; then
        echo "mountpoint already exists: $mountpoint" >&2
        exit 1
    fi
    mkdir -m 0 "$mountpoint"

    subvol_id=${snap_map_id["$snap"]}
    echo "mounting '$snap' on: $mountpoint"
    mount -t btrfs -o subvolid="$subvol_id" "$root_device" "$mountpoint"

# UMOUNT
elif ((run_umount)); then

    snap=${arg[1]}
    if [[ -z "$snap" ]]; then
        echo "snapshot name not specified" >&2
        exit 1
    fi

    mountpoint="/mnt/$snap"
    if ! [[ -d "$mountpoint" ]]; then
        echo "snapshot not mounted in: $mountpoint" >&2
        exit 1
    fi

    umount "$mountpoint"
    rmdir "$mountpoint"

# RESTORE
elif ((run_restore)); then

    if [[ -z "$confirm_restore" ]]; then
        echo "please --confirm-restore - note that this will overwrite /boot and reset root" >&2
        exit 1
    fi

    snap=${arg[1]}
    if [[ -z "$snap" ]]; then
        echo "snapshot name not specified" >&2
        exit 1
    fi
    if [[ -z "${snap_map_date["$snap"]}" ]]; then
        echo "specified snapshot not found: $snap" >&2
        exit 1
    fi

    # Find /boot backup
    boot_backup_file=
    if [[ -f "$snap_root/$snap/root/var/tmp/backup/boot.tar.gz" ]]; then
        boot_backup_file="$snap_root/$snap/root/var/tmp/backup/boot.tar.gz"
    elif [[ -f "$snap_root/$snap/root/boot.tar.gz" ]]; then
        boot_backup_file="$snap_root/$snap/root/boot.tar.gz"
    else
        echo "boot backup tarball not found in snapshot: $snap" >&2
        exit 1
    fi

    # Determine new name and path for currently active "root" subvolume
    renamed_root="$btrfs_root/root_rw_$current_date"
    if [ -d "$renamed_root" ]; then
        for ((i=2;; i++)); do
            if ! [ -d "$renamed_root.$i" ]; then
                # append counter/number as suffix
                renamed_root="$renamed_root.$i"
                break
            fi
        done
    fi

    # Rename current "root" subvolume
    echo "Saving currently active 'root' subvolume as: ${renamed_root##*/}"
    if [[ -e "$renamed_root" ]]; then
        echo "new name for current 'root' already exists (error or race condition?)" >&2
        exit 1
    fi
    mv -vi "$btrfs_root/root" "$renamed_root" || exit $?

    # Clone selected snapshot -> new "root"
    snap_id=${snap_map_id["$snap"]}
    snap_src=$snap_root/$snap/root
    snap_dst=$btrfs_root/root
    if [[ -e "$snap_dst" ]]; then
        echo "previously renamed 'root' subvolume already exists (error or race condition?)" >&2
        exit 1
    fi
    echo "Cloning snapshot '$snap' ($snap_id) to be used as new root subvolume..."
    $BTRFS subvolume snapshot "$snap_src" "$snap_dst" || exit $?

    # Extracting /boot backup into /boot
    # This would reset the boot configuration and overwrite boot images etc.
    echo "restoring /boot..."
    (cd / && tar xf "$boot_backup_file" boot) || exit $?

    # Done, this should be it
    # We're not setting the default subvolid because the active one is identified by its name "root"
    echo "DONE! Reboot now for the change to take effect."
    echo "# reboot"

fi


