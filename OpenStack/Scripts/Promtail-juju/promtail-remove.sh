#!/bin/bash

# Stop Promtail service
sudo systemctl stop promtail

# Remove Promtail binary
sudo rm /usr/local/bin/promtail

# Remove Promtail configuration file
sudo rm /etc/promtail/promtail-config.yml

# Remove Promtail service file
sudo rm /etc/systemd/system/promtail.service

# Reload systemd daemon
sudo systemctl daemon-reload

# Delete Promtail user
sudo userdel promtail

# Delete Promtail group
sudo groupdel promtail

# Remove Promtail log directory
sudo rm -rf /var/log/promtail

# Remove Promtail data directory
sudo rm -rf /var/lib/promtail

echo "Promtail has been successfully removed."