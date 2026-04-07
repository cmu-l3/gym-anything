#!/usr/bin/env python3
"""Feed real NAB (Numenta Anomaly Benchmark) time-series data into Graphite.

This script reads REAL server metrics from the NAB dataset (actual EC2 instance
CPU utilization, disk writes, network traffic, etc.) and sends them to Carbon
via the plaintext protocol on port 2003.

The original data values are preserved exactly as recorded from real servers.
Timestamps are shifted to fit within Graphite's retention window (ending at
current time) so the data is visible in the UI.

Data sources:
- NAB realKnownCause: Real EC2 CPU utilization data
- NAB realAWSCloudwatch: Real AWS CloudWatch metrics (CPU, disk, network, ELB)
- NAB realTraffic: Real web traffic speed data
- NAB realKnownCause: Real server temperature data
"""

import csv
import os
import socket
import time
from datetime import datetime


DATA_DIR = "/opt/graphite_real_data"
CARBON_HOST = "localhost"
CARBON_PORT = 2003

# Map CSV files to Graphite metric paths
# These are REAL metrics from actual servers
FILE_TO_METRIC = {
    "ec2_cpu_utilization_1.csv": "servers.ec2_instance_1.cpu.utilization",
    "ec2_cpu_utilization_2.csv": "servers.ec2_instance_2.cpu.utilization",
    "ec2_cloudwatch_cpu.csv": "servers.ec2_instance_3.cpu.cloudwatch_utilization",
    "ec2_disk_write.csv": "servers.ec2_instance_1.disk.write_bytes",
    "ec2_disk_write_2.csv": "servers.ec2_instance_2.disk.write_bytes",
    "ec2_network_in.csv": "servers.ec2_instance_1.network.bytes_in",
    "elb_request_count.csv": "servers.load_balancer.requests.count",
    "rds_cpu_utilization.csv": "servers.rds_database.cpu.utilization",
    "traffic_speed_1.csv": "servers.web_traffic.speed_sensor_1",
    "traffic_speed_2.csv": "servers.web_traffic.speed_sensor_2",
    "machine_temperature.csv": "servers.datacenter.machine_temperature",
}


def parse_nab_csv(filepath):
    """Parse a NAB CSV file and return (timestamp_unix, value) pairs.

    NAB CSV format:
        timestamp,value
        2014-04-01 00:00:00,18.0
        2014-04-01 00:05:00,18.0

    Timestamps are shifted so the last data point is 2 minutes before now,
    preserving the original time intervals between points. The actual metric
    VALUES are real measurements from production servers, unchanged.
    """
    raw_points = []
    try:
        with open(filepath, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    ts_str = row.get("timestamp", "")
                    value = float(row.get("value", 0))
                    dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                    unix_ts = int(dt.timestamp())
                    raw_points.append((unix_ts, value))
                except (ValueError, KeyError):
                    continue
    except Exception as e:
        print(f"  Error reading {filepath}: {e}")
        return []

    if not raw_points:
        return []

    # Shift timestamps so the dataset ends 2 minutes ago
    # This preserves original intervals but places data within retention window
    now = int(time.time())
    latest_ts = max(ts for ts, _ in raw_points)
    time_shift = now - latest_ts - 120  # end 2 min before now

    shifted_points = [(ts + time_shift, value) for ts, value in raw_points]
    return shifted_points


def send_to_carbon(metric_path, data_points, sock):
    """Send data points to Carbon via plaintext protocol.

    Format: <metric_path> <value> <timestamp>\n
    Send in batches to avoid overwhelming Carbon.
    """
    batch_size = 500
    sent = 0
    for i in range(0, len(data_points), batch_size):
        batch = data_points[i:i + batch_size]
        payload = ""
        for unix_ts, value in batch:
            payload += f"{metric_path} {value} {unix_ts}\n"
        try:
            sock.sendall(payload.encode("utf-8"))
            sent += len(batch)
        except Exception as e:
            print(f"  Error sending batch: {e}")
            try:
                sock.close()
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.connect((CARBON_HOST, CARBON_PORT))
                sock.sendall(payload.encode("utf-8"))
                sent += len(batch)
            except Exception as e2:
                print(f"  Reconnect failed: {e2}")
                break
        time.sleep(0.1)
    return sent, sock


def main():
    if not os.path.isdir(DATA_DIR):
        print(f"Data directory {DATA_DIR} not found, skipping NAB data feed")
        return

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((CARBON_HOST, CARBON_PORT))
        print(f"Connected to Carbon at {CARBON_HOST}:{CARBON_PORT}")
    except Exception as e:
        print(f"Cannot connect to Carbon: {e}")
        return

    total_sent = 0
    for filename, metric_path in FILE_TO_METRIC.items():
        filepath = os.path.join(DATA_DIR, filename)
        if not os.path.isfile(filepath):
            print(f"  Skipping {filename} (not found)")
            continue

        data_points = parse_nab_csv(filepath)
        if not data_points:
            print(f"  Skipping {filename} (no valid data)")
            continue

        print(f"  Feeding {filename} -> {metric_path} ({len(data_points)} points)")
        sent, sock = send_to_carbon(metric_path, data_points, sock)
        total_sent += sent
        print(f"    Sent {sent} data points")

    sock.close()
    print(f"\nTotal data points sent to Graphite: {total_sent}")


if __name__ == "__main__":
    main()
