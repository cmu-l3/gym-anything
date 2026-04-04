#!/bin/bash
set -e
echo "=== Setting up Cloud Radar Chart Task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the data file with real-world scenarios
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/cloud_benchmark_scores.txt << 'EOF'
CLOUD PROVIDER BENCHMARK SCORES (Scale 1-10)
--------------------------------------------------
Use this data to create the Radar Chart.

METRICS (Axes):
1. Cost Efficiency
2. Global Availability
3. Compute Performance
4. Support Quality
5. Ease of Use

SCORES:
Series 1: AWS
- Cost Efficiency: 7
- Global Availability: 10
- Compute Performance: 9
- Support Quality: 8
- Ease of Use: 6

Series 2: Azure
- Cost Efficiency: 7
- Global Availability: 9
- Compute Performance: 9
- Support Quality: 7
- Ease of Use: 7

Series 3: GCP (Google Cloud)
- Cost Efficiency: 9
- Global Availability: 8
- Compute Performance: 9
- Support Quality: 6
- Ease of Use: 8
EOF
chown ga:ga /home/ga/Documents/cloud_benchmark_scores.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/cloud_radar_comparison.eddx
rm -f /home/ga/Documents/cloud_radar_comparison.png

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch EdrawMax
echo "Launching EdrawMax..."
# Kill any existing instances first
kill_edrawmax
# Launch fresh
launch_edrawmax

# 5. Wait for UI and setup window
wait_for_edrawmax 90
dismiss_edrawmax_dialogs
maximize_edrawmax

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="