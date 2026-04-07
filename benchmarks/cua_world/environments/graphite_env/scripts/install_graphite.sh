#!/bin/bash
set -e

echo "=== Installing Graphite Environment ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install base dependencies
apt-get install -y \
    wget \
    curl \
    jq \
    netcat-openbsd \
    firefox \
    wmctrl \
    xdotool \
    xclip \
    scrot \
    imagemagick \
    python3-pip \
    python3-requests \
    python3-psutil \
    collectd \
    x11-utils

# Install Docker for running Graphite container
echo "=== Installing Docker ==="
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Wait for Docker to be ready
echo "=== Waiting for Docker daemon ==="
DOCKER_READY=false
for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready"
        DOCKER_READY=true
        break
    fi
    sleep 2
done

if [ "$DOCKER_READY" = "false" ]; then
    echo "ERROR: Docker daemon failed to start"
    exit 1
fi

# Pull the Graphite all-in-one Docker image
echo "=== Pulling Graphite Docker image ==="
docker pull graphiteapp/graphite-statsd:latest

# Download real time-series data from Numenta Anomaly Benchmark (NAB)
# These are REAL server metrics from actual Amazon EC2 instances
echo "=== Downloading real time-series data ==="

set +e
mkdir -p /opt/graphite_real_data

# Helper: download file with retry and size validation
download_file() {
    local url="$1"
    local dest="$2"
    local min_size="${3:-100}"

    echo "Downloading: $url"
    wget --timeout=120 --tries=3 -O "$dest" "$url" 2>&1

    if [ -f "$dest" ]; then
        local size
        size=$(stat -c%s "$dest" 2>/dev/null || echo "0")
        if [ "$size" -lt "$min_size" ]; then
            echo "WARNING: Downloaded file too small ($size bytes)"
            rm -f "$dest"
            return 1
        fi
        echo "Downloaded successfully: $dest ($size bytes)"
        return 0
    fi
    echo "WARNING: Download failed for $url"
    return 1
}

# NAB Real AWS CloudWatch dataset - real EC2 CPU utilization data
download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_cpu_utilization_5f5533.csv" \
    "/opt/graphite_real_data/ec2_cpu_utilization_1.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_cpu_utilization_ac20cd.csv" \
    "/opt/graphite_real_data/ec2_cpu_utilization_2.csv" 1000

# NAB Real AWS CloudWatch data - real EC2 network and disk metrics
download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_cpu_utilization_24ae8d.csv" \
    "/opt/graphite_real_data/ec2_cloudwatch_cpu.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_disk_write_bytes_1ef3de.csv" \
    "/opt/graphite_real_data/ec2_disk_write.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_disk_write_bytes_c0d644.csv" \
    "/opt/graphite_real_data/ec2_disk_write_2.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/ec2_network_in_5abac7.csv" \
    "/opt/graphite_real_data/ec2_network_in.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/elb_request_count_8c0756.csv" \
    "/opt/graphite_real_data/elb_request_count.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realAWSCloudwatch/rds_cpu_utilization_cc0c53.csv" \
    "/opt/graphite_real_data/rds_cpu_utilization.csv" 1000

# NAB Real Traffic data - real web traffic metrics
download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realTraffic/speed_6005.csv" \
    "/opt/graphite_real_data/traffic_speed_1.csv" 1000

download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realTraffic/speed_7578.csv" \
    "/opt/graphite_real_data/traffic_speed_2.csv" 1000

# NAB Real Machine Temperature - real server temperature data
download_file \
    "https://raw.githubusercontent.com/numenta/NAB/master/data/realKnownCause/machine_temperature_system_failure.csv" \
    "/opt/graphite_real_data/machine_temperature.csv" 1000

DATA_FILE_COUNT=$(find /opt/graphite_real_data -type f -name "*.csv" | wc -l)
echo "Downloaded real data files: $DATA_FILE_COUNT"

if [ "$DATA_FILE_COUNT" -lt 3 ]; then
    echo "WARNING: Some NAB data downloads failed, will rely on collectd real-time metrics"
fi

set -e

# Set permissions
chmod -R 755 /opt/graphite_real_data

echo "=== Graphite installation complete ==="
echo "Data files:"
ls -la /opt/graphite_real_data/
