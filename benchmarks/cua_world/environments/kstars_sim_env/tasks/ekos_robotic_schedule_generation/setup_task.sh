#!/bin/bash
set -e
echo "=== Setting up ekos_robotic_schedule_generation task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts
rm -rf /home/ga/Documents/Ekos
rm -f /home/ga/Documents/PI_instructions.txt
rm -f /tmp/task_result.json

# 3. Create the PI Instructions document for the agent
cat > /home/ga/Documents/PI_instructions.txt << 'EOF'
ROBOTIC OBSERVATORY TARGET LIST - TONIGHT's QUEUE
=================================================
Please program the Ekos Scheduler for tonight's automated run. 
Generate the required .esq and .esl files and save them in:
  ~/Documents/Ekos/

Use exact filenames as specified below. You can build these via the
KStars/Ekos UI or by generating the XML files directly via script.

-------------------------------------------------
TARGET 1: M81 (Bode's Galaxy)
Sequence File: m81_lrgb.esq
Jobs (LRGB sequence):
  - Filter: Luminance (Slot 1), Exposure: 60s, Count: 10
  - Filter: Red       (Slot 4), Exposure: 60s, Count: 5
  - Filter: Green     (Slot 5), Exposure: 60s, Count: 5
  - Filter: Blue      (Slot 6), Exposure: 60s, Count: 5
Schedule Constraints:
  - Minimum Altitude: 30 degrees

-------------------------------------------------
TARGET 2: NGC 1499 (California Nebula)
Sequence File: ngc1499_ha.esq
Jobs (Narrowband):
  - Filter: H-Alpha (Slot 2), Exposure: 300s, Count: 15
Schedule Constraints:
  - Minimum Altitude: 20 degrees
  - Minimum Moon Distance: 40 degrees

-------------------------------------------------
TARGET 3: M42 (Orion Nebula)
Sequence File: m42_hdr.esq
Jobs (HDR):
  - Filter: Luminance (Slot 1), Exposure: 10s, Count: 5
  - Filter: Luminance (Slot 1), Exposure: 60s, Count: 5
Schedule Constraints:
  - Minimum Altitude: 25 degrees

-------------------------------------------------
MASTER SCHEDULE
Schedule File: master_schedule.esl
Instructions: Create a schedule list containing the three targets above.
Link each target job to its respective sequence file (.esq) using absolute paths.
Ensure the constraints are applied properly to each job.
EOF

chown ga:ga /home/ga/Documents/PI_instructions.txt
echo "PI Instructions written to ~/Documents/PI_instructions.txt"

# 4. Start INDI and KStars to provide the realistic environment GUI
ensure_indi_running
sleep 2
connect_all_devices

# Configure filter wheel to have standard slots so GUI looks correct
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=H-Alpha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Red" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Green" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=Blue" 2>/dev/null || true

ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="