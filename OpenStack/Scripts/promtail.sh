#!/bin/bash

# Check if promtail is already installed
if command -v promtail &>/dev/null; then
    echo "Promtail is already installed."
    exit 0
fi
if command -v unzip &>/dev/null; then
    echo "Unzip is already installed."
else
    sudo apt install unzip
fi

KERNEL_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
MACHINE_TYPE=$(uname -m)
PROMTAIL_VERSION=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep tag_name | cut -d '"' -f 4)

if [ "$MACHINE_TYPE" == "x86_64" ]; then
    MACHINE_TYPE="amd64"
elif [ "$MACHINE_TYPE" == "aarch64" ]; then
    MACHINE_TYPE="arm64"
else
    echo "Unsupported machine type: $MACHINE_TYPE"
fi


# Install dependencies
sudo apt-get update
sudo apt-get install -y wget

# Download promtail binary
PROMTAIL_NAME="promtail-${KERNEL_NAME}-${MACHINE_TYPE}.zip"
wget https://github.com/grafana/loki/releases/download/${PROMTAIL_VERSION}/$PROMTAIL_NAME > /dev/null # https://github.com/grafana/loki/releases/download/v2.9.5/promtail-linux-amd64.zip
unzip $PROMTAIL_NAME
rm $PROMTAIL_NAME

PROMTAIL_NAME="promtail-${KERNEL_NAME}-${MACHINE_TYPE}"
# Move promtail binary to /usr/local/bin
sudo mv $PROMTAIL_NAME /usr/local/bin/promtail

sudo useradd --system promtail
sudo usermod -a -G adm promtail
sudo usermod -a -G root promtail
sudo usermod -a -G sudo promtail


sudo mkdir -p /etc/promtail

# Create promtail configuration file
sudo touch /etc/promtail/promtail-config.yml
sudo echo "" > /etc/promtail/promtail-config.yml 

# Create promtail logs directory
sudo mkdir -p /var/log/promtail/
sudo chown -R promtail:promtail /var/log/promtail/

# Create promtail service file
sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit] 
Description=Promtail service 
After=network.target 
 
[Service] 
Type=simple 
User=promtail
ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/promtail-config.yml
ExecStartPost=/bin/sh -c 'chown -R promtail:promtail /var/log/promtail/'
ExecStartPost=/bin/sh -c 'chmod -R 755 /var/log/promtail/'
Restart=on-failure 
RestartSec=20 

[Install] 
WantedBy=multi-user.target
EOF

# Enable and start promtail service
sudo systemctl daemon-reload
sudo systemctl enable promtail

echo "Promtail has been installed and started successfully."
