#!/bin/bash
# Setup for vocal_stroop_acoustic_rt_analysis task
# Generates synthetic .wav files and condition logs with precise programmatic VOTs

set -e
echo "=== Setting up vocal_stroop_acoustic_rt_analysis task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Create required directories
mkdir -p /home/ga/pebl/data/audio
mkdir -p /home/ga/pebl/analysis
mkdir -p /var/lib/app/ground_truth

# Generate dynamic audio files and log
python3 << 'PYEOF'
import os, csv, json, random, math, wave, struct

SR = 44100
participants = ['p01', 'p02', 'p03', 'p04', 'p05', 'p06']
conditions = ['congruent', 'incongruent']
trials_per_p = 40

log_data = []
gt_data = {}

def write_wav(fpath, samples, sr=44100):
    with wave.open(fpath, 'w') as obj:
        obj.setnchannels(1)
        obj.setsampwidth(2)
        obj.setframerate(sr)
        data = struct.pack('<' + ('h'*len(samples)), *samples)
        obj.writeframesraw(data)

for p in participants:
    os.makedirs(f'/home/ga/pebl/data/audio/{p}', exist_ok=True)
    gt_data[p] = {'congruent': [], 'incongruent': []}
    
    for t in range(1, trials_per_p + 1):
        cond = conditions[t % 2]
        fname = f'trial_{t:02d}.wav'
        fpath = f'/home/ga/pebl/data/audio/{p}/{fname}'
        rel_path = f'{p}/{fname}'
        
        if p == 'p06':
            # Broken mic: continuous static noise without speech
            samples = [int(random.uniform(-1000, 1000)) for _ in range(int(SR * 2.0))]
            write_wav(fpath, samples, SR)
            log_data.append({'participant': p, 'trial': t, 'condition': cond, 'correct_word': 'red', 'audio_file': rel_path})
            continue
            
        # Random dynamic RT to prevent hardcoding
        base_rt = random.uniform(400, 600) if cond == 'congruent' else random.uniform(600, 800)
        noise_len = int((base_rt / 1000.0) * SR)
        speech_len = int(1.0 * SR)
        
        samples = []
        # Pre-onset noise
        for _ in range(noise_len):
            samples.append(int(random.uniform(-1000, 1000)))
            
        # Post-onset speech + noise
        for i in range(speech_len):
            val = 10000 * math.sin(2 * math.pi * 300 * (i / SR)) + random.uniform(-1000, 1000)
            samples.append(int(max(-32768, min(32767, val))))
            
        write_wav(fpath, samples, SR)
        
        # Determine exact algorithmic VOT to save as Ground Truth
        baseline = samples[:int(SR * 0.1)]
        abs_base = [abs(x) for x in baseline]
        mean_base = sum(abs_base) / len(abs_base)
        var_base = sum((x - mean_base)**2 for x in abs_base) / len(abs_base)
        sd_base = math.sqrt(var_base)
        thresh = mean_base + 5 * sd_base
        
        vot_ms = -1
        for i, x in enumerate(samples):
            if abs(x) > thresh:
                vot_ms = round((i / SR) * 1000.0, 1)
                break
                
        gt_data[p][cond].append(vot_ms)
        word = random.choice(['red', 'blue', 'green', 'yellow'])
        log_data.append({'participant': p, 'trial': t, 'condition': cond, 'correct_word': word, 'audio_file': rel_path})

# Save Log
with open('/home/ga/pebl/data/vocal_stroop_log.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['participant', 'trial', 'condition', 'correct_word', 'audio_file'])
    writer.writeheader()
    writer.writerows(log_data)

# Compute GT Means
gt_means = {}
for p in ['p01', 'p02', 'p03', 'p04', 'p05']:
    c_mean = sum(gt_data[p]['congruent']) / len(gt_data[p]['congruent'])
    i_mean = sum(gt_data[p]['incongruent']) / len(gt_data[p]['incongruent'])
    gt_means[p] = {
        'congruent': round(c_mean, 1),
        'incongruent': round(i_mean, 1)
    }

# Save GT out of agent's direct view
with open('/var/lib/app/ground_truth/vocal_rts.json', 'w') as f:
    json.dump(gt_means, f)
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/pebl
chmod -R 755 /home/ga/pebl
chmod 600 /var/lib/app/ground_truth/vocal_rts.json

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get ga user's DBUS session address
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open a terminal for the agent
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid gnome-terminal --geometry=120x35 -- bash -c 'echo === Vocal Stroop Acoustic RT Analysis ===; echo; echo Condition Log: ~/pebl/data/vocal_stroop_log.csv; echo Audio Files: ~/pebl/data/audio/; echo Output target: ~/pebl/analysis/vocal_rt_report.json; echo; bash' > /tmp/terminal.log 2>&1 &"

for i in $(seq 1 15); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Terminal" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        sleep 1
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot for evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== vocal_stroop_acoustic_rt_analysis setup complete ==="