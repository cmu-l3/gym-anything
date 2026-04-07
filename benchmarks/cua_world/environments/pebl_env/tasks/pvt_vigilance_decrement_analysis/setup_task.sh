#!/bin/bash
echo "=== Setting up PVT Vigilance Decrement Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Generate dynamic data to prevent pre-computation/gaming
echo "Generating PVT dataset and ground truth..."
python3 << 'PYEOF'
import csv, json, random, os

# Ensure truly random generation each time
random.seed()

participants = [f"P{i:02d}" for i in range(16)]
data = []
gt = {"participants": {}, "group_means": {"rested": {}, "deprived": {}}}

rested_means = []
deprived_means = []

for p in participants:
    if p == "P00":
        # Fake participant - auto-clicker
        for cond in ["rested", "deprived"]:
            for t in range(1, 121):
                rt = random.uniform(148.0, 156.0)
                data.append({"participant_id": p, "condition": cond, "trial": t, "isi_ms": random.randint(2000, 10000), "rt_ms": round(rt, 1), "response": 1})
        continue

    gt[p] = {"rested": {}, "deprived": {}}
    for cond in ["rested", "deprived"]:
        is_deprived = (cond == "deprived")
        base_rt = random.gauss(260, 20) if not is_deprived else random.gauss(360, 30)
        slope = random.uniform(3, 10) if not is_deprived else random.uniform(20, 45)

        trials = []
        for t in range(1, 121):
            target_mean = base_rt + (t/120.0) * slope * 5.0
            lapse_chance = 0.015 if not is_deprived else (0.05 + (t/120.0)*0.1)

            if random.random() < lapse_chance:
                rt = random.uniform(500.0, 1200.0)
            else:
                rt = random.gauss(target_mean, target_mean * 0.1)

            # Enforce limits and false starts
            if rt < 100:
                rt = random.uniform(100, 150)
            if random.random() < 0.005:
                rt = random.uniform(50, 99)

            trials.append(round(rt, 1))
            data.append({
                "participant_id": p, 
                "condition": cond, 
                "trial": t, 
                "isi_ms": random.randint(2000, 10000), 
                "rt_ms": round(rt, 1), 
                "response": 1
            })

        # Compute exact Ground Truth metrics for verifier
        valid_rts = [rt for rt in trials if rt >= 100]
        lapses = sum(1 for rt in trials if rt > 500)
        
        mean_rt = sum(valid_rts) / len(valid_rts) if valid_rts else 0

        # Quintile regression
        q_means = []
        for i in range(5):
            q_trials = trials[i*24:(i+1)*24]
            q_valid = [rt for rt in q_trials if rt >= 100]
            q_means.append(sum(q_valid) / len(q_valid) if q_valid else 0)

        x = [1, 2, 3, 4, 5]
        sum_x = 15
        sum_x2 = 55
        sum_y = sum(q_means)
        sum_xy = sum(x[i] * q_means[i] for i in range(5))
        vig_slope = (5 * sum_xy - sum_x * sum_y) / (5 * sum_x2 - sum_x**2)

        gt[p][cond]["mean_rt_ms"] = mean_rt
        gt[p][cond]["lapses"] = lapses
        gt[p][cond]["vigilance_slope"] = vig_slope

        if cond == "rested":
            rested_means.append(mean_rt)
        else:
            deprived_means.append(mean_rt)

gt["group_means"]["rested"]["mean_rt_ms"] = sum(rested_means)/len(rested_means)
gt["group_means"]["deprived"]["mean_rt_ms"] = sum(deprived_means)/len(deprived_means)
gt["sleep_deprivation_effect_ms"] = gt["group_means"]["deprived"]["mean_rt_ms"] - gt["group_means"]["rested"]["mean_rt_ms"]

# Write public dataset
with open('/home/ga/pebl/data/pvt_session_data.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "condition", "trial", "isi_ms", "rt_ms", "response"])
    writer.writeheader()
    writer.writerows(data)

# Write hidden ground truth for verifier
with open('/tmp/.pvt_gt.json', 'w') as f:
    json.dump(gt, f)

PYEOF

chown ga:ga /home/ga/pebl/data/pvt_session_data.csv
chmod 600 /tmp/.pvt_gt.json  # Hide from agent

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=130x35 -- bash -c 'echo === PVT Vigilance Decrement Analysis ===; echo; echo Data file: ~/pebl/data/pvt_session_data.csv; echo Output target: ~/pebl/analysis/pvt_report.json; echo; bash' > /tmp/pvt_terminal.log 2>&1 &"

for i in {1..15}; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Setup complete ==="