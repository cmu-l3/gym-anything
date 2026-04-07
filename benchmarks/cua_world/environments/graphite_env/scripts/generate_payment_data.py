#!/usr/bin/env python3
"""
Generate realistic payment service metrics in Graphite plaintext format.

Creates 3 days of 5-minute interval data for three metrics:
  - apps.payment.requests_per_sec   (daily traffic pattern + flash sale spike)
  - apps.payment.error_rate         (baseline ~0.5% + incident spikes)
  - apps.payment.latency_p99_ms     (baseline 40-120ms + incident spikes)

Incidents:
  Day 2, 11:30 AM - Flash sale (30 min): RPS spikes to 2000+, errors to 6-8%, latency to 800-2000ms
  Day 3, 03:00 AM - DB blip  (15 min): errors to 3.5-4.5%, latency to 400-600ms
"""

import argparse
import math
import random
import time


def daily_pattern(hour):
    """Return a 0-1 multiplier representing typical daily web traffic."""
    if hour < 5:
        return 0.05 + 0.03 * math.sin(hour * math.pi / 10)
    elif hour < 8:
        return 0.05 + 0.35 * (hour - 5) / 3
    elif hour < 12:
        return 0.4 + 0.6 * math.sin((hour - 8) * math.pi / 8)
    elif hour < 14:
        return 0.7 + 0.3 * math.sin((hour - 12) * math.pi / 4)
    elif hour < 18:
        return 0.7 - 0.4 * (hour - 14) / 4
    elif hour < 22:
        return 0.3 - 0.15 * (hour - 18) / 4
    else:
        return 0.15 - 0.1 * (hour - 22) / 2


def generate_data(output_path, days=3, interval_sec=300):
    now = int(time.time())
    end_ts = now - 120  # 2 minutes before current time

    points_per_day = 86400 // interval_sec  # 288 for 5-min intervals
    total_points = days * points_per_day
    start_ts = end_ts - (total_points - 1) * interval_sec

    random.seed(42)  # deterministic

    lines = []

    for i in range(total_points):
        ts = start_ts + i * interval_sec

        elapsed_sec = i * interval_sec
        day = elapsed_sec // 86400
        time_in_day = elapsed_sec % 86400
        hour = time_in_day / 3600.0

        mult = daily_pattern(hour)

        # --- requests_per_sec ---
        rps_base = 50 + 1150 * mult
        rps = max(10, rps_base + random.gauss(0, rps_base * 0.08))

        # Day 2 flash sale: 11:30-12:00
        if day == 1 and 11.5 <= hour < 12.0:
            rps = random.uniform(2000, 2500)

        # --- error_rate ---
        err_base = 0.002 + 0.008 * mult
        error_rate = max(0.001, err_base + abs(random.gauss(0, err_base * 0.15)))

        if day == 1 and 11.5 <= hour < 12.0:
            error_rate = random.uniform(0.06, 0.08)
        if day == 2 and 3.0 <= hour < 3.25:
            error_rate = random.uniform(0.035, 0.045)

        # --- latency_p99_ms ---
        lat_base = 40 + 80 * mult
        latency = max(20, lat_base + abs(random.gauss(0, lat_base * 0.12)))

        if day == 1 and 11.5 <= hour < 12.0:
            latency = random.uniform(800, 2000)
        if day == 2 and 3.0 <= hour < 3.25:
            latency = random.uniform(400, 600)

        lines.append(f"apps.payment.requests_per_sec {rps:.2f} {ts}")
        lines.append(f"apps.payment.error_rate {error_rate:.6f} {ts}")
        lines.append(f"apps.payment.latency_p99_ms {latency:.1f} {ts}")

    with open(output_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f"Generated {len(lines)} lines ({total_points} timestamps x 3 metrics)")
    print(f"Time range: {total_points * interval_sec / 3600:.1f} hours")
    print(f"Output: {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate payment service telemetry data")
    parser.add_argument("--output", required=True, help="Output file path")
    parser.add_argument("--days", type=int, default=3, help="Number of days of data")
    parser.add_argument("--interval", type=int, default=300, help="Interval between points in seconds")
    args = parser.parse_args()
    generate_data(args.output, args.days, args.interval)
