btrfs-upgrade-snapshot
======================

A bash script for creating and restoring BTRFS snapshots of
your os installation, made to be run with systemd release upgrades.

All you have to do is install this rpm, which automatically
creates and enables a service that's run before an upgrade is started.
It automatically saves the state of the os installation prior to the upgrade
in a btrfs snapshot. Boot files including kernel images
which are typically not part of the root filesystem are copied
into it before making the snapshot.
After completing the upgrade, you can run this script with the "list" command
to see that a new snapshot was created.

If you're experiencing trouble with the new release,
like packages that are now missing or broken or maybe even graphics issues
that are forcing you to boot with the `nomodeset` option,
you can now simply call this tool with the "restore" command
to roll back to the previous release.
When the bugs are fixed, start over with another release upgrade.
The only limit is your disk capacity as snapshots use and block disk space
for files in those snapshots, even if they've been deleted on the live system.

In short:
- Install this rpm (to get the btrfs-os-snapshot service)
- Initiate a system upgrade, for example using the fedora-release-upgrade script
- Run `btrfs-os-snapshot list` to check that a snapshot was created
- If something is wrong with the new release, run `btrfs-os-snapshot restore`
  to roll back to the previous state



Installation
------------

Use the provided rpm file or recreate it:

    $ make clean
    $ make rpm
    $ ls -l rpmbuild/RPMS/noarch/*.rpm

Install it:

    # rpm -ivh rpmbuild/RPMS/noarch/*.rpm

You may run something like this to confirm that the script is functioning:

    # btrfs-os-snapshot list

It should either say that no snapshots were found or list them.
(Snapshots are not deleted when uninstalling this rpm.)

It should NOT show an error like this:

    the root filesystem / does not appear to be on a separate subvolume

This means that the root filesystem (mounted on /) does not have
its own btrfs subvolume but is instead at the very top.
In this case, the script won't be able to do anything for you.
That's because it would normally work with the root subvolume
and move it around but it can't do that if there's no separate subvolume.

It would also warn you if /home isn't on a separate subvolume
as that's a general recommendation. If you don't have a lot of stuff
in /home or if you have other reasons for not splitting it up,
then you can ignore the warning.
But if you have, say, large image files somewhere in /home
and after upgrading your system you delete some of them,
the disk space used by them won't be released until
you also delete the auto-created snapshot.

You could also set up the script and the systemd service manually,
without installing the rpm, it just automates the installation.
You can uninstall it (along with the service unit) using standard commands:

    # rpm -e btrfs-upgrade-snapshot



Usage
-----

The service installed by the rpm automatically runs the "create" command
before an upgrade but if you want to create a snapshot manually:

    # btrfs-os-snapshot create

To list all snapshots created by this tool:

    # btrfs-os-snapshot list

To browse a snapshot (NAME as shown in the "list" output):

    # btrfs-os-snapshot mount NAME
    # ls -l /mnt/NAME
    # btrfs-os-snapshot umount NAME

Warning: Danger:
To roll back, restoring the specified root volume and /boot:

    # btrfs-os-snapshot restore NAME
    # btrfs-os-snapshot restore NAME --confirm-restore
    # reboot

After restoring, you'll have to reboot and the system will boot
into the old state. The boot configuration is simply restored
to match the old state but no further configuration changes are made (like fstab).
The system will not know that it's in an old state as it'll
actually be in a clone of the old state. So you could repeat the command
to restore that old state again.
Everytime, it'll also restore /boot but it won't touch other filesystems
that you might have.
And everytime, it'll move the previous state away without deleting it.
But that'll probably be changed in the future.



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



Example
-------

    $ sudo /root/bin/fedora-release-upgrade
    Run tail -f /tmp/fedora-upgrade-dnf-output-30476-1630804813.log in another terminal to see what's happening...
    Now requesting sudo to run upgrade script: /tmp/.fedora-upgrade-script.tmp.30476.1630804813.sh
    Don't worry, it'll ask before downloading the upgrade.
    (If you don't trust me, read the script file.)
    This is Fedora version 30. Download upgrade to 31 now? y
    Downloading release upgrade files. This will take a long time. Watch /var/log/dnf.log if you're curious.
    The dnf output will be saved to: /tmp/fedora-upgrade-dnf-output-30476-1630804813.log
    Upgrade to version 31 downloaded successfully. Reboot and install upgrade now? y

    # grep ^VERSION /etc/os-release
    VERSION="31 (MATE-Compiz)"
    VERSION_ID=31
    VERSION_CODENAME=""

    # btrfs-os-snapshot restore root_snap_2021-09-05 --confirm-restore
    # reboot

    $ grep ^VERSION /etc/os-release
    VERSION="30 (MATE-Compiz)"
    VERSION_ID=30
    VERSION_CODENAME=""



Bugs
----

The script can't work with an os installation at the top of the btrfs fs,
if it's outside of any subvolume. It doesn't do anything with @.

As of yet, it doesn't list the clones that are created when rolling back.
It only lists snapshots.
Also, it doesn't have an option to automatically delete those things.

And there's probably more like installations with every single directory
being on a separate filesystem (/root, /var, ... /etc).
If you put /etc on a separate filesystem, you'll have to have a plan
on how to keep things in sync in case you have to restore your filesystem.
If you simply spread things onto different filesystems for no reason,
you'll have to take care of that yourself as this script will only
take care of the root filesystem + /boot.



Author
------

Philip Seeger (philip@c0xc.net)



License
-------

Please see the file called LICENSE.



