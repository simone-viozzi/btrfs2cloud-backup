#! /bin/bash

set -e

config_folder="/etc/btrfs2cloud"

if [ ! -d "$config_folder" ]; then
    # create the config folder
    mkdir -p /etc/btrfs2cloud
    # copy the config template
    cp config /etc/btrfs2cloud/config
fi

cp btrfs2cloud.sh /usr/local/bin/btrfs2cloud.sh

snapper_config_folder="/etc/snapper/configs"

find $snapper_config_folder -mindepth 1 -maxdepth 1 -printf "%f\n" | while read config; do
    echo "installing btrfs2cloud for config $config..."
    
    # copy the systemd service file and timer
    cp btrfs2cloud.service /etc/systemd/system/btrfs2cloud-$config.service
    cp btrfs2cloud.timer /etc/systemd/system/btrfs2cloud-$config.timer

    # replace the config name in the service file
    sed -i "s/CONFIG_NAME/$config/g" /etc/systemd/system/btrfs2cloud-$config.service
    sed -i "s/CONFIG_NAME/$config/g" /etc/systemd/system/btrfs2cloud-$config.timer
done

echo "enable the timer with: \"systemctl enable --now /etc/systemd/system/btrfs2cloud-*.timer\""
