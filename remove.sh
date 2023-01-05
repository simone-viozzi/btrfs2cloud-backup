#! /bin/bash

set -e

for unit in $(systemctl list-unit-files \
            --plain --no-legend --no-pager --type timer \
            "btrfs2cloud-*" | cut -f 1 -d " "); do
    echo "removing $unit..."
    systemctl disable $unit
    rm -i /etc/systemd/system/$unit
    # replace timer with service
    unit=${unit/timer/service}
    rm -i /etc/systemd/system/$unit
done

rm -i /usr/local/bin/btrfs2cloud.sh
rm -i /etc/btrfs2cloud/config
rmdir /etc/btrfs2cloud

