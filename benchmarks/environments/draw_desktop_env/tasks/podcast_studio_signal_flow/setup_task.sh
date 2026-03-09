#!/bin/bash
set -e
echo "=== Setting up Podcast Studio Signal Flow Task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Create specs directory and files
mkdir -p /home/ga/Desktop/studio_specs

# Equipment Inventory
cat > /home/ga/Desktop/studio_specs/equipment_inventory.txt << EOF
STUDIO A - EQUIPMENT INVENTORY

INPUTS:
- 4x Shure SM7B Dynamic Microphones (Host 1-4)
- 4x Cloudlifter CL-1 Mic Activators (Inline Preamp)

PROCESSING & INTERFACE:
- 1x RodeCaster Pro II (Integrated Audio Production Studio)

OUTPUTS & MONITORING:
- 1x Behringer HA8000 V2 (8-Channel Headphone Distribution Amplifier)
- 4x Sony MDR-7506 Professional Headphones (Host 1-4)
- 2x Yamaha HS8 Powered Studio Monitors (Left/Right)

RECORDING TARGET:
- 1x Studio PC (Windows 11, Reaper DAW)
EOF

# Wiring Schedule
cat > /home/ga/Desktop/studio_specs/wiring_schedule.txt << EOF
STUDIO A - WIRING SCHEDULE / SIGNAL FLOW

1. MICROPHONE INPUT CHAINS (x4)
   [Source] Shure SM7B 
      --via XLR Cable--> 
   [Input] Cloudlifter CL-1 
      --via XLR Cable--> 
   [Dest] RodeCaster Pro II (Inputs 1-4)

2. MAIN MONITORING
   [Source] RodeCaster Pro II (Main Out L/R) 
      --via TRS 1/4" Balanced Cables--> 
   [Dest] Yamaha HS8 Monitors

3. HEADPHONE MONITORING
   [Source] RodeCaster Pro II (Monitor Out 1) 
      --via TRS 1/4" Cable--> 
   [Input] Behringer HA8000 (Main Input 1)
   
   [Source] Behringer HA8000 (Outputs 1-4) 
      --via TRS 1/4" Coiled Cables--> 
   [Dest] Sony MDR-7506 Headphones (x4)

4. DIGITAL INTERFACE
   [Source] RodeCaster Pro II (USB 1) 
      --via USB-C Cable--> 
   [Dest] Studio PC (USB Port)
EOF

chmod -R 777 /home/ga/Desktop/studio_specs

# 2. Launch draw.io
# Use the wrapper that disables updates
/usr/local/bin/drawio-launch &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -i "draw.io"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# Dismiss "Create New / Open Existing" dialog
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="