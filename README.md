# btrfs2cloud-backup

A simple script to backup a btrfs sub-volume to any cloud supported by rclone.

## description

This script allow to backup a btrfs sub-volume to any cloud supported by rclone. Is meant for a disaster-recovery situation and do not support incremental snapshots.
The snapshot themselves are managed by snapper, this way you can set up a clean-up service and they wont pile up.
The snapshots are compressed and encrypted while they are uploaded.
The script can handle if the service get interrupted, it will retry when possible and clean up partially uploaded files before uploading the new snapshot.

## Features

- Use [snapper](https://github.com/openSUSE/snapper) to take a read-only snapshot.
- Use a single pipe to upload the volume to the cloud, no need to save it to a file before uploading.
- Compress the volume with zstd.
- Encrypt it with openssl.
- Send it to your favorite cloud using [rclone](https://rclone.org/).
- Use a flock to avoid that 2 timers fire at the same time.
- Use systemd-inhibit to inhibit poweroff / reboot while a snapshot is being uploaded.
- Through a file and naming, allow to know if a backup was completed or not.
- It does not delete the old last uploaded snapshot until the new one is fully updated.
- Handle the eventuality that the service get stopped while running, `persistent=true` in the timer, and clean up on partially uploaded files at the start of the back-up script.

## Structure

- `install.sh`: simple script to simplify the setup, it will detect all the snapper configs and, for each one create a service and timer.
- `remove.sh`: `rm -i` of all the files created by the install script
- `btrfs2cloud.sh`: The main script of this project. After some checks, it will create a snapper snapshot, than upload it. At the end it will write `ok` into `state.txt` so you can be sure that the backup was successful.
- `btrfs2cloud.service` and `btrfs2cloud.timer`: templates of the unit files, during the install script they will be copied, renamed and replaced the template with the name of the config they refer to.
- `config`: config file that need to be edited.

## How to restore a snapshot

1. confirm that the snapshot is valid, download and open `state.txt`.
1. rename the sub-volume you want to restore: `mv @home @home.old`
1. reverse the pipe:

    ```bash
    rclone --config /home/user/.config/rclone/rclone.conf cat b2:backup/home/snapshot |
        openssl enc -d -aes256 -pass "pass:password" -pbkdf2 |
        zstd -d -c - | 
        btrfs receive .
    ```

1. Rename the sub-volume into it's original name: `mv snapshot @home`
1. Fix fstab in case the subvolid changed
