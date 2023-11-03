#! /bin/bash

config_name="$1"

# fail on error
set -e

apprise_notify() {
    curl -X POST -d '{"title":"btrfs2cloud", "body":"'"$1"'", "tag":"admin", "format":"markdown"}' \
        -H "Content-Type: application/json" \
        http://localhost:8005/notify/apprise
}

echo_array() {
    local arr=("$@")
    arr=($(echo "${arr[@]}" | tr ' ' '\n' | sort -r))
    for i in "${arr[@]}"; do
        echo -e "\t$i"
    done
}

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
    [ -z "$OPENSSL_PASSWD" ] || \
    [ -z "$SNAPSHOTS_TO_KEEP" ]; then
    echo "ERROR: one or more variables in the config are not set"
    exit 1
fi

rclone_config="--config $RCLONE_CONFIG_PATH"

apprise_notify "⚠️ starting backup - **$config_name**"

files=$(rclone $rclone_config lsf $CLOUD_NAME:$BUCKET_NAME/$config_name/)

previous_snapshots=()
# get all files that end in _snapshot
for file in $files; do
    if [[ $file =~ _snapshot$ ]]; then
        previous_snapshots+=($file)
    fi
done

if [ -z "$previous_snapshots" ]; then
    echo "no previous snapshots found"
    previous_snapshots=()
else
    echo "list of previous snapshots:"
    echo_array ${previous_snapshots[@]}
fi

curr_date=$(date +"%Y-%m-%dT%H-%M-%S%z")

echo "clean partial files..."
rclone $rclone_config cleanup $CLOUD_NAME:$BUCKET_NAME

echo "doing snapper snapshot for config ${config_name}..."
snap_num=$(snapper -c $config_name create -t single -d "$SNAPPER_MESSAGE" -c number -p)

snap_folder=$snap_path/$snap_num
btrfs_subvol=$snap_folder/snapshot

echo "WARNING ~ incomplete snapshot ~ WARNING" |
    rclone $rclone_config rcat "${CLOUD_NAME}:${BUCKET_NAME}/${config_name}/${curr_date}_state.txt"

echo "sending snapshot..."
start=$(date +%s)

btrfs send $btrfs_subvol |
    zstd -$ZSTD_COMPRESSION_LEVEL -c - |
    openssl enc -e -aes256 -pass "pass:$OPENSSL_PASSWD" -pbkdf2 |
    rclone $rclone_config rcat --retries 5 --retries-sleep 30s --b2-chunk-size 256mi \
            "${CLOUD_NAME}:${BUCKET_NAME}/${config_name}/${curr_date}_snapshot"

ends=$(date +%s)
echo "send completed, took $((ends - start))s"

rclone $rclone_config delete "$CLOUD_NAME:$BUCKET_NAME/$config_name/${curr_date}_state.txt"
echo "ok" |
    rclone $rclone_config rcat "$CLOUD_NAME:$BUCKET_NAME/$config_name/${curr_date}_state.txt"

timestamps=()
for snapshot in "${previous_snapshots[@]}"; do
    # select them only if they start with a timestamp
    if [[ $snapshot =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
        # keep only the timestamp
        timestamp=$(echo "$snapshot" | cut -d '_' -f 1)
        timestamps+=($timestamp)
    fi
done

#echo "list of timestamps:"
#echo_array ${timestamps[@]}

len_timestamps=${#timestamps[@]}
len_timestamps=$((len_timestamps + 1))
echo "len timestamps: $len_timestamps"
echo "snapshots to keep: $SNAPSHOTS_TO_KEEP"

if [ "$len_timestamps" -gt "$SNAPSHOTS_TO_KEEP" ]; then

    echo "deleting old snapshot..."
    
    n_to_delete=$((len_timestamps - SNAPSHOTS_TO_KEEP))
    
    sorted_timestamps=($(echo "${timestamps[@]}" | tr ' ' '\n' | sort))
    oldest_timestamps=("${sorted_timestamps[@]:0:$n_to_delete}")

    echo "list of timestamps to be deleted..."
    echo_array ${oldest_timestamps[@]}

    files_to_delete=()
    for timestamp in "${oldest_timestamps[@]}"; do
        files_to_delete+=($(echo "$files" | grep "$timestamp"))
    done

    #echo "deleting old snapshots..."
    #echo_array ${files_to_delete[@]}

    for file in "${files_to_delete[@]}"; do
        rclone $rclone_config delete "$CLOUD_NAME:$BUCKET_NAME/$config_name/$file"
    done

fi

files=$(rclone $rclone_config lsf $CLOUD_NAME:$BUCKET_NAME/$config_name/)

current_snapshots=$(echo "$files" | grep -E '_snapshot$')
current_snapshots=($current_snapshots)

echo "list of current snapshots:"
echo_array ${current_snapshots[@]}

echo "all done"
apprise_notify "✅ all done - **$config_name**"
