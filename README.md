btrfs-upgrade-snapshot
======================

A bash script for creating and restoring BTRFS snapshots of /,
made to be run with systemd release upgrades.



Usage
-----

    # btrfs-os-snapshot create

    # btrfs-os-snapshot list

    # btrfs-os-snapshot mount NAME
    # ls -l /mnt/NAME
    # btrfs-os-snapshot umount NAME

    # btrfs-os-snapshot restore NAME
    # btrfs-os-snapshot restore NAME --confirm-restore
    # reboot



Notes
-----

It expects that your operating system, mounted on /, resides
on a named subvolume, which is typically called "root".

When run, it first creates a tarball of /boot
and stores it in /var/tmp/backup or /,
to make it part of the snapshot that's being created next.
Then, a snapshot of the root subvolume is created under .snapshot,
which is based above that subvolume, at the top (root root).

Use the list command to view all snapshots created by this script.

Before restoring an old snapshot, `create` a current one
and also make sure you're about to restore the right one.
It will not discard the currently active root subvolume by default,
instead it'll save it with a name like `root_rw_DATE`.
It will then restore the specified snapshot by cloning it.
Finally, it'll extract the /boot backup found in that snapshot.



Author
------

Philip Seeger (philip@philip-seeger.de)



License
-------

Please see the file called LICENSE.



