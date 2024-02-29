#!/bin/bash

# Check if promtail is already installed
if command -v promtail &>/dev/null; then
    echo "Promtail is already installed."
    exit 0
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
    exit 1
fi


# Install dependencies
sudo apt-get update
sudo apt-get install -y wget

# Download promtail binary
wget https://github.com/grafana/loki/releases/download/${PROMTAIL_VERSION}/promtail-${KERNEL_NAME}-${MACHINE_TYPE}.zip
unzip promtail-linux-amd64.zip
rm promtail-linux-amd64.zip

# Move promtail binary to /usr/local/bin
sudo mv promtail-linux-amd64 /usr/local/bin/promtail

sudo useradd --system promtail
usermod -a -G adm promtail

sudo mkdir -p /etc/promtail

# Create promtail configuration file
sudo tee /etc/promtail/promtail-config.yaml > /dev/null <<EOF
server:
    http_listen_port: 9080
    grpc_listen_port: 0
    log_level: "info"

positions:
    filename: /tmp/positions.yaml

clients:
    - url: http://10.254.0.5:80/loki/api/v1/push


scrape_configs:
  - job_name: maas-logs
    static_config:
      - targets:
          - localhost
        labels:
          job: maas-logs
          __path__: /var/snap/maas/common/log/*.log.*
    pipeline_stages:
      - json:
          expressions:
            http_method: 'method'
            http_status: "status"
      - labels:
          http_method:
          http_status:
EOF

# Create promtail logs directory
sudo mkdir -p /var/log/promtail/

# Create promtail service file
sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit] 
Description=Promtail service 
After=network.target 
 
[Service] 
Type=simple 
User=root 
ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/promtail-config.yaml 
Restart=on-failure 
RestartSec=20 
StandardOutput=append:/etc/promtail/logs/promtail.log 
StandardError=append:/etc/promtail/logs/promtail.log 
 
[Install] 
WantedBy=multi-user.target
EOF

# Enable and start promtail service
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

echo "Promtail has been installed and started successfully."
