#!/bin/bash
# Setup for mousetracking_spatial_attraction_analysis task
# Generates synthetic but highly realistic continuous spatial time-series data
# with appropriate noise, bowing, and an injected artifact (p99).

set -e
echo "=== Setting up mousetracking_spatial_attraction_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate the mouse-tracking dataset and the hidden ground truth
python3 << 'PYEOF'
import csv, json, math, random

# Set seed for reproducibility within this specific task setup
random.seed(42)

participants = [f"p{i:02d}" for i in range(1, 21)]
trials_per_participant = 20
data = []
gt_participants = {}

for p in participants:
    comp_mds = []
    unrel_mds = []
    
    for t in range(1, trials_per_participant + 1):
        cond = "Competitor" if t <= 10 else "Unrelated"
        target_side = random.choice(["left", "right"])
        target_x = 200 if target_side == "left" else 800
        target_y = 100
        start_x, start_y = 500, 900
        
        steps = random.randint(40, 70)
        points = []
        
        # Base bowing magnitude (Competitor has stronger pull to opposite side)
        bowing = random.uniform(80, 250) if cond == "Competitor" else random.uniform(10, 60)
        
        # Determine direction of the bow
        if target_side == "left":
            bowing = -bowing # Pull rightwards towards distractor
        else:
            bowing = bowing  # Pull leftwards towards distractor

        for i in range(steps):
            t_ratio = i / (steps - 1)
            # Linear interpolation
            x = start_x + (target_x - start_x) * t_ratio
            y = start_y + (target_y - start_y) * t_ratio
            
            # Add parabolic bowing
            bow = bowing * 4 * t_ratio * (1 - t_ratio)
            x += bow
            
            # Add human motor noise
            x += random.gauss(0, 3)
            y += random.gauss(0, 3)
            
            points.append((x, y))
            data.append({
                "participant_id": p,
                "trial": t,
                "condition": cond,
                "timepoint": i,
                "time_ms": i * 16, # approx 60Hz
                "x_pos": round(x, 2),
                "y_pos": round(y, 2)
            })
            
        # Ground Truth MD Calculation
        X0, Y0 = points[0]
        Xn, Yn = points[-1]
        A = Y0 - Yn
        B = Xn - X0
        C = (X0 * Yn) - (Xn * Y0)
        
        max_d = 0
        den = math.hypot(A, B)
        if den > 0:
            for x, y in points:
                d = abs(A * x + B * y + C) / den
                if d > max_d:
                    max_d = d
                    
        if cond == "Competitor":
            comp_mds.append(max_d)
        else:
            unrel_mds.append(max_d)
            
    m_comp = sum(comp_mds) / len(comp_mds)
    m_unrel = sum(unrel_mds) / len(unrel_mds)
    
    gt_participants[p] = {
        "mean_md_competitor": round(m_comp, 3),
        "mean_md_unrelated": round(m_unrel, 3),
        "attraction_effect": round(m_comp - m_unrel, 3)
    }

# Inject p99 (Automated Artifact - Perfectly Straight Lines)
for t in range(1, 21):
    cond = "Competitor" if t <= 10 else "Unrelated"
    target_x = random.choice([200, 800])
    target_y = 100
    start_x, start_y = 500, 900
    steps = 20
    for i in range(steps):
        t_ratio = i / (steps - 1)
        x = start_x + (target_x - start_x) * t_ratio
        y = start_y + (target_y - start_y) * t_ratio
        
        data.append({
            "participant_id": "p99",
            "trial": t,
            "condition": cond,
            "timepoint": i,
            "time_ms": i * 16,
            "x_pos": round(x, 2),
            "y_pos": round(y, 2)
        })

# Group mean calculation
group_mean = sum(v["attraction_effect"] for v in gt_participants.values()) / len(gt_participants)

gt_data = {
    "participants": gt_participants,
    "group_mean_attraction_effect": round(group_mean, 3)
}

# Write agent data
with open("/home/ga/pebl/data/mousetracking_data.csv", "w") as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial", "condition", "timepoint", "time_ms", "x_pos", "y_pos"])
    writer.writeheader()
    writer.writerows(data)

# Write hidden ground truth
with open("/opt/pebl/.hidden_mousetracking_gt.json", "w") as f:
    json.dump(gt_data, f)

PYEOF

chown ga:ga /home/ga/pebl/data/mousetracking_data.csv
chmod 400 /opt/pebl/.hidden_mousetracking_gt.json # Hide from ga user

date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Mouse-Tracking Spatial Attraction Analysis ===; echo; echo Data file: ~/pebl/data/mousetracking_data.csv; echo Output target: ~/pebl/analysis/mousetracking_report.json; echo; bash' > /tmp/terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== mousetracking_spatial_attraction_analysis setup complete ==="