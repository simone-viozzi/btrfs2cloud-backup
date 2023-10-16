#! /bin/bash

set -e

# check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root"
    exit 1
fi


config_folder="/etc/btrfs2cloud"

if [ ! -d "$config_folder" ]; then
    # create the config folder
    mkdir -p "$config_folder"
    # copy the config template
    cp config "$config_folder/config"
else
    echo "Warning: config folder already exists, skipping copy of config template"
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
