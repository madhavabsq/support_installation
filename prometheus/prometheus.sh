sudo mkdir /home/ec2-user/prometheus

wget -P /home/ec2-user/prometheus https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz

sudo tar -vxf /home/ec2-user/prometheus/prometheus-3.5.0.linux-amd64.tar.gz -C /home/ec2-user/prometheus/

sudo mv /home/ec2-user/prometheus/prometheus-3.5.0.linux-amd64 /home/ec2-user/prometheus/prometheus-files

sudo useradd --no-create-home --shell /bin/false prometheus

sudo mkdir /var/lib/prometheus

sudo  mkdir /etc/prometheus

sudo chown -R prometheus:prometheus /var/lib/prometheus/ /etc/prometheus/

sudo mkdir /etc/prometheus/consoles /etc/prometheus/console_libraries

sudo chown -R prometheus:prometheus /etc/prometheus/*

cp /home/ec2-user/prometheus/prometheus-files/prometheus /usr/local/bin/

cp /home/ec2-user/prometheus/prometheus-files/promtool /usr/local/bin/

chown prometheus:prometheus /usr/local/bin/pro*

cat > /etc/prometheus/prometheus.yml <<EOL
# my global config
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
      #- targets: ['localhost:9093']

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  #- '/etc/alertmanager/server_status_rule.yml'

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: "prometheus"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["localhost:9090"]

  - job_name: 'monitoring_app_infra'
    static_configs:
      - targets: ['localhost:9100']

 # - job_name: 'loki_app_infra'
 #  static_configs:
 #   - targets: ['10.25.51.143:9100']

  - job_name: 'node_exporter'
    ec2_sd_configs:
      - region: 'ap-south-1'  # Replace with your AWS region
      - role_arn: 'arn:aws:iam::638845738277:role/ROLE-IIFL-FINALYZER-PROM-GRAFANA-MONITOR'
        refresh_interval: 6h
    relabel_configs:
      # Keep targets based on a specific tag value
      - source_labels: [__meta_ec2_tag_Prometheus_jmx, __meta_ec2_tag_Prometheus_mysql]
        separator: ';'
        action: keep
        regex: 'true;true|true;|;true'

      # Set a custom label for instance names
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name  # Create a custom label 'instance_name'

      # Set custom label for aws account
      - source_labels: [__meta_ec2_tag_AWS_Account]
        action: keep
        regex: 'finalyzer-360one'

      # Set a custom label for environment (e.g., production, staging)
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment  # Create a custom label 'environment'

      # Set the address for scraping (append port 9100)
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:9100'  # Set the target address for scraping

      # Set a custom label for availability zone
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone  # Create a custom label 'availability_zone'

      # Set a custom label for instance type (e.g., t2.micro)
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type  # Create a custom label 'instance_type'

  - job_name: 'jmx_exporter'
    ec2_sd_configs:
      - region: 'ap-south-1'  # Replace with your AWS region
      - role_arn: 'arn:aws:iam::638845738277:role/ROLE-IIFL-FINALYZER-PROM-GRAFANA-MONITOR'
        refresh_interval: 6h
    relabel_configs:
      # Keep targets based on a specific tag value
      - source_labels: [__meta_ec2_tag_Prometheus_jmx]
        action: keep
        regex: 'true'  # Only keep targets with the Prometheus tag set to 'true'

      # Set a custom label for instance names
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name  # Create a custom label 'instance_name'

      # Set custom label for aws account
      - source_labels: [__meta_ec2_tag_AWS_Account]
        action: keep
        regex: 'finalyzer-360one'

      # Set a custom label for environment (e.g., production, staging)
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment  # Create a custom label 'environment'

      # Set the address for scraping (append port 9100)
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:1098'  # Set the target address for scraping

      # Set a custom label for availability zone
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone  # Create a custom label 'availability_zone'

      # Set a custom label for instance type (e.g., t2.micro)
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type  # Create a custom label 'instance_type'

  - job_name: 'mysql_exporter'
    ec2_sd_configs:
      - region: 'ap-south-1'  # Replace with your AWS region
      - role_arn: 'arn:aws:iam::638845738277:role/ROLE-IIFL-FINALYZER-PROM-GRAFANA-MONITOR'
        refresh_interval: 6h
    relabel_configs:
      # Keep targets based on a specific tag value
      - source_labels: [__meta_ec2_tag_Prometheus_mysql]
        action: keep
        regex: 'true'  # Only keep targets with the Prometheus tag set to 'true'

      # Set a custom label for instance names
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name  # Create a custom label 'instance_name'

      # Set custom label for aws account
      - source_labels: [__meta_ec2_tag_AWS_Account]
        action: keep
        regex: 'finalyzer-360one'

      # Set a custom label for environment (e.g., production, staging)
      - source_labels: [__meta_ec2_tag_Environment]
        target_label: environment  # Create a custom label 'environment'

      # Set the address for scraping (append port 9100)
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: '${1}:9104'  # Set the target address for scraping

      # Set a custom label for availability zone
      - source_labels: [__meta_ec2_availability_zone]
        target_label: availability_zone  # Create a custom label 'availability_zone'

      # Set a custom label for instance type (e.g., t2.micro)
      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type  # Create a custom label 'instance_type'
EOL

chown prometheus:prometheus /etc/prometheus/prometheus.yml

cat > /etc/systemd/system/prometheus.service <<EOL
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --storage.tsdb.retention.time=30d

[Install]
WantedBy=multi-user.target
EOL

sudo chmod 755 /etc/systemd/system/prometheus.service

sudo systemctl daemon-reload

sudo systemctl enable prometheus

sudo systemctl start prometheus