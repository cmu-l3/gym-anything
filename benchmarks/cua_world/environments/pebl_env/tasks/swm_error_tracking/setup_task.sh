#!/bin/bash
set -e

echo "=== Setting up swm_error_tracking task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task start time for anti-gaming (file must be created after this)
date +%s > /tmp/task_start_timestamp

# Create required directories
mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
mkdir -p /var/lib/pebl

# Generate realistic SWM clickstream data programmatically
# This strictly enforces the BSE/WSE logic and avoids external dependencies
python3 << 'EOF'
import csv, json, random, os
random.seed(1024)

participants = [f"sub-{i:02d}" for i in range(1, 16)]
contaminated = "sub-999"
all_data = []
gt = {"participants": {}, "group_mean_bse": 0, "group_mean_wse": 0}

total_bse, total_wse, num_valid = 0, 0, 0

for p in participants + [contaminated]:
    bse, wse = 0, 0
    # 6 trials per participant with set sizes 4, 4, 6, 6, 8, 8
    for t, sz in enumerate([4, 4, 6, 6, 8, 8]):
        trial_num = t + 1
        # Create slightly more boxes than the set size
        boxes = [f"box_{chr(65+i)}" for i in range(sz + 3)]
        tokens = random.sample(boxes, sz)
        known_tokens = set()

        for s in range(1, sz + 1):
            target = tokens[s-1]
            checked_empty = set()

            if p == contaminated:
                n_clicks = random.randint(15, 25) # Massive error injection
            else:
                n_clicks = random.randint(1, 5)   # Normal behavior

            for click_i in range(n_clicks - 1):
                if p == contaminated:
                    if checked_empty and random.random() < 0.8:
                        box = random.choice(list(checked_empty))
                        wse += 1
                    else:
                        available = [b for b in boxes if b not in tokens and b not in checked_empty]
                        if available:
                            box = random.choice(available)
                            checked_empty.add(box)
                        else:
                            box = random.choice(list(checked_empty))
                            wse += 1
                else:
                    r = random.random()
                    # BSE takes precedence logic: click a known token from a previous search
                    if r < 0.15 and known_tokens:
                        box = random.choice(list(known_tokens))
                        bse += 1
                    # WSE: click a checked empty box from the CURRENT search
                    elif r < 0.30 and checked_empty:
                        box = random.choice(list(checked_empty))
                        wse += 1
                    else:
                        available = [b for b in boxes if b != target and b not in checked_empty and b not in known_tokens]
                        if available:
                            box = random.choice(available)
                            checked_empty.add(box)
                        else:
                            break

                all_data.append({
                    "participant_id": p, "trial_num": trial_num, "set_size": sz,
                    "search_num": s, "box_id": box, "outcome": "empty"
                })

            # The search ends when the participant clicks the target token
            all_data.append({
                "participant_id": p, "trial_num": trial_num, "set_size": sz,
                "search_num": s, "box_id": target, "outcome": "token"
            })
            known_tokens.add(target)

    gt["participants"][p] = {"bse": bse, "wse": wse}
    if p != contaminated:
        total_bse += bse
        total_wse += wse
        num_valid += 1

gt["group_mean_bse"] = round(total_bse / num_valid, 2)
gt["group_mean_wse"] = round(total_wse / num_valid, 2)

final_data = []
for p in participants + [contaminated]:
    for t in range(1, 7):
        trial_data = [d for d in all_data if d["participant_id"] == p and d["trial_num"] == t]
        for i, d in enumerate(trial_data):
            d["click_num"] = i + 1
            final_data.append(d)

with open("/home/ga/pebl/data/swm_clickstream.csv", "w", newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["participant_id", "trial_num", "set_size", "search_num", "click_num", "box_id", "outcome"])
    writer.writeheader()
    writer.writerows(final_data)

# Save hidden ground truth for the verifier
with open("/var/lib/pebl/swm_gt.json", "w") as f:
    json.dump(gt, f)
EOF

# Ensure proper permissions for the agent
chown -R ga:ga /home/ga/pebl
chmod 600 /var/lib/pebl/swm_gt.json

# Get ga user's DBUS session address for UI stability
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Launch a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Spatial Working Memory Error Tracking ===; echo; echo Data file: ~/pebl/data/swm_clickstream.csv; echo Output target: ~/pebl/analysis/swm_report.json; echo; bash' > /tmp/swm_terminal.log 2>&1 &"

# Maximize terminal window
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== swm_error_tracking setup complete ==="