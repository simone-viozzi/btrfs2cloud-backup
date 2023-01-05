# btrfs2cloud-backup

A simple script to backup a btrfs sub-volume to any cloud supported by rclone.

## Features

- Use [snapper](https://github.com/openSUSE/snapper) to take a read-only snapshot
- Use a single pipe to upload the volume to the cloud, no need to save it to a file before uploading
- Compress the volume with zstd
- Encrypt it with openssl
- Send it to your favorite cloud using [rclone](https://rclone.org/)
- through a file, allow to know if a backup was completed or not.

## Structure

- `install.sh`: simple script to simplify the setup, it will detect all the snapper configs and, for each one create a service and timer.
- `remove.sh`: `rm -i` of all the files created by the install script
- `btrfs2cloud.sh`: The main script of this project. After some checks, it will create a snapper snapshot, than upload it. At the end it will write `ok` into `state.txt` so you can be sure that the backup was successful.
- `btrfs2cloud.service` and `btrfs2cloud.timer`: templates of the unit files, during the install script they will be copied, renamed and replaced the template with the name of the config they refer to.
- `config`: config file that need to be edited.
