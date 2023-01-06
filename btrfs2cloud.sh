#! /bin/bash

# read the parameters from the command line

config_name=$1

# fail on error
set -e

snap_path=$(snapper --machine-readable csv -c $config_name get-config | \
    grep SUBVOLUME | cut -d ',' -f 2)/.snapshots

echo "config_name: $config_name"
echo "snap_path: $snap_path"

# assert that a file with $config_name exists in /etc/snapper/configs/
if [ ! -f /etc/snapper/configs/$config_name ]; then
    echo "ERROR: /etc/snapper/configs/$config_name does not exist"
    exit 1
fi

# assert that $snap_path exists
if [ ! -d $snap_path ]; then
    echo "ERROR: $snap_path does not exist"
    exit 1
fi

conf_path="/etc/btrfs2cloud/config"

# assert that the config file exists in /etc/btrfs2cloud/
if [ ! -f "$conf_path" ]; then
    echo "ERROR: $conf_path does not exist"
    exit 1
fi

# read the variables from the config file
source $conf_path

# assert that all the variables are set
if [ -z "$CLOUD_NAME" ] || \
    [ -z "$BUCKET_NAME" ] || \
    [ -z "$RCLONE_CONFIG_PATH" ] || \
    [ -z "$SNAPPER_MESSAGE" ] || \
    [ -z "$ZSTD_COMPRESSION_LEVEL" ] || \
    [ -z "$OPENSSL_PASSWD" ]; then
    echo "ERROR: one or more variables in the config are not set"
    exit 1
fi

rclone_config="--config $RCLONE_CONFIG_PATH"

echo "delete old partial snapshot..."

rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/snapshot_new
rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/info_new.xml
rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/state_new.txt
# to delete partial uploaded files, note: will delete only if they are a day old
rclone $rclone_config cleanup $CLOUD_NAME:$BUCKET_NAME/$config_name

echo "doing snapper snapshot for config $config_name..."

# create a snapper snapshot
snap_num=$(snapper -c $config_name create -t single -d "$SNAPPER_MESSAGE" -c number -p)

snap_folder=$snap_path/$snap_num
info_file=$snap_folder/info.xml
btrfs_subvol=$snap_folder/snapshot

echo "WARNING ~ incomplete snapshot ~ WARNING" |
    rclone $rclone_config rcat $CLOUD_NAME:$BUCKET_NAME/$config_name/state_new.txt

echo "sending snapshot..."
start=$(date +%s)

btrfs send $btrfs_subvol |
    zstd -$ZSTD_COMPRESSION_LEVEL -c - |
    openssl enc -e -aes256 -pass "pass:$OPENSSL_PASSWD" -pbkdf2 |
    rclone $rclone_config rcat $CLOUD_NAME:$BUCKET_NAME/$config_name/snapshot_new

end=$(date +%s)

echo "coping info.xml..."
cat $info_file |
    rclone $rclone_config rcat $CLOUD_NAME:$BUCKET_NAME/$config_name/info_new.xml

rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/state_new.txt
echo "ok" |
    rclone $rclone_config rcat $CLOUD_NAME:$BUCKET_NAME/$config_name/state_new.txt

echo "send completed, took $((end - start))s"

echo "deleting old snapshot..."

rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/snapshot
rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/info.xml
rclone $rclone_config delete $CLOUD_NAME:$BUCKET_NAME/$config_name/state.txt

echo "renaming new snapshot..."

rclone $rclone_config moveto \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/snapshot_new \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/snapshot

rclone $rclone_config moveto \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/info_new.xml \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/info.xml

rclone $rclone_config moveto \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/state_new.txt \
    $CLOUD_NAME:$BUCKET_NAME/$config_name/state.txt

echo "all done"
