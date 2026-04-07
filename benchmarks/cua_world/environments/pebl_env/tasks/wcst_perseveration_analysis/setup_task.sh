#!/bin/bash
set -e
echo "=== Setting up WCST Perseveration Analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

mkdir -p /home/ga/pebl/data
mkdir -p /home/ga/pebl/analysis
chown -R ga:ga /home/ga/pebl

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Generate the realistic normative WCST data and the contaminated participant
echo "Generating WCST cognitive model dataset..."
python3 - << 'EOF'
import csv, random

COLORS = ['red', 'green', 'yellow', 'blue']
SHAPES = ['triangle', 'star', 'cross', 'circle']
NUMBERS = ['1', '2', '3', '4']

PILES = {
    1: {'color': 'red', 'shape': 'triangle', 'number': '1'},
    2: {'color': 'green', 'shape': 'star', 'number': '2'},
    3: {'color': 'yellow', 'shape': 'cross', 'number': '3'},
    4: {'color': 'blue', 'shape': 'circle', 'number': '4'},
}

RULE_SEQ = ['color', 'shape', 'number', 'color', 'shape', 'number']

def generate_participant(pid, p_perseverate, p_lapse):
    trials = []
    cat_comp = 0
    cons_correct = 0
    current_rule_idx = 0
    rule = RULE_SEQ[current_rule_idx]
    prev_rule = None
    agent_rule = 'color'

    for t in range(1, 129):
        if cat_comp == 6:
            break

        while True:
            c = random.choice(COLORS)
            s = random.choice(SHAPES)
            n = random.choice(NUMBERS)
            # prevent exact key card matches on all 3 dims
            if not any(PILES[p]['color']==c and PILES[p]['shape']==s and PILES[p]['number']==n for p in PILES):
                break

        stim = {'color': c, 'shape': s, 'number': n}

        if random.random() < p_lapse:
            choice = random.randint(1, 4)
        else:
            matching_piles = [p for p in PILES if PILES[p][agent_rule] == stim[agent_rule]]
            choice = matching_piles[0] if matching_piles else random.randint(1, 4)

        is_correct = (PILES[choice][rule] == stim[rule])

        trials.append({
            'participant_id': pid,
            'trial': t,
            'stimulus_color': c,
            'stimulus_shape': s,
            'stimulus_number': n,
            'response_pile': choice,
            'current_rule': rule,
            'correct': 1 if is_correct else 0
        })

        if is_correct:
            cons_correct += 1
            if cons_correct == 10:
                cat_comp += 1
                if cat_comp < 6:
                    prev_rule = rule
                    current_rule_idx += 1
                    rule = RULE_SEQ[current_rule_idx]
                cons_correct = 0
        else:
            cons_correct = 0
            if prev_rule and random.random() < p_perseverate:
                agent_rule = prev_rule
            else:
                options = ['color', 'shape', 'number']
                if agent_rule in options: options.remove(agent_rule)
                agent_rule = random.choice(options)

    return trials

all_data = []
random.seed(1024) # Fixed seed for reproducible normative ground truth

# Generate 12 valid patients
for i in range(1, 13):
    pid = f"sub-10{200+i}"
    # varying degrees of executive dysfunction (perseveration)
    p_pers = random.uniform(0.05, 0.45)
    p_lapse = random.uniform(0.01, 0.08)
    all_data.extend(generate_participant(pid, p_pers, p_lapse))

# Generate 1 contaminated (sub-99999) doing random choices
for t in range(1, 129):
    c = random.choice(COLORS)
    s = random.choice(SHAPES)
    n = random.choice(NUMBERS)
    choice = random.randint(1, 4)
    # Give them a static rule to evaluate correctness against, but they just guess
    rule = 'color'
    is_correct = (PILES[choice][rule] == c)
    all_data.append({
        'participant_id': 'sub-99999',
        'trial': t,
        'stimulus_color': c,
        'stimulus_shape': s,
        'stimulus_number': n,
        'response_pile': choice,
        'current_rule': rule,
        'correct': 1 if is_correct else 0
    })

with open('/home/ga/pebl/data/wcst_data.csv', 'w', newline='') as f:
    fields = ['participant_id', 'trial', 'stimulus_color', 'stimulus_shape', 'stimulus_number', 'response_pile', 'current_rule', 'correct']
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(all_data)
EOF

chown ga:ga /home/ga/pebl/data/wcst_data.csv
chmod 644 /home/ga/pebl/data/wcst_data.csv

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent with instructions
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === WCST Perseveration Analysis ===; echo; echo Data file: ~/pebl/data/wcst_data.csv; echo Output target: ~/pebl/analysis/wcst_report.json; echo; bash' > /tmp/wcst_terminal.log 2>&1 &"

# Maximize the terminal
for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial state screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== WCST setup complete ==="