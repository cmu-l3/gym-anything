#!/bin/bash
echo "=== Setting up Cytochrome C HMMER Profile Discovery task ==="

# Clean previous state
rm -rf /home/ga/UGENE_Data/hmmer_task 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/hmmer_task/results

# Copy training data
if [ -f /opt/ugene_data/cytochrome_c_multispecies.fasta ]; then
    cp /opt/ugene_data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/hmmer_task/cytochrome_c_multispecies.fasta
elif [ -f /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta ]; then
    cp /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/hmmer_task/cytochrome_c_multispecies.fasta
else
    # Fallback
    cp /workspace/assets/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/hmmer_task/cytochrome_c_multispecies.fasta 2>/dev/null || true
fi

# Generate uncharacterized proteome (Decoys + 1 Target)
python3 << 'PYEOF'
import random
import textwrap

target = """>sp|P00056|CYTC_ARATH Cytochrome c OS=Arabidopsis thaliana
MASFDEAPPGNPKAGEKIFKTKCAQCHTVDKGAGHKQGPNLNGLFGRQSGTTPGYSYSAA
NKNMAVIWEEKTLYDYLLNPKKYIPGTKMVFPGLKKPQDRADLIAYLKEATA"""

decoys = []
aas = "ACDEFGHIKLMNPQRSTVWY"
for i in range(1, 10):
    length = random.randint(100, 250)
    seq = "".join(random.choice(aas) for _ in range(length))
    formatted_seq = "\n".join(textwrap.wrap(seq, 60))
    decoys.append(f">tr|UNKNOWN{i}|PROT_{i} Uncharacterized protein {i}\n{formatted_seq}")

# Insert the Cytochrome c target randomly (we'll just place it at index 4)
all_seqs = decoys[:4] + [target] + decoys[4:]
with open("/home/ga/UGENE_Data/hmmer_task/uncharacterized_proteome.fasta", "w") as f:
    f.write("\n".join(all_seqs) + "\n")
PYEOF

chown -R ga:ga /home/ga/UGENE_Data/hmmer_task

# Record start time for anti-gaming verification
date +%s > /tmp/hmmer_task_start_ts

# Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE
TIMEOUT=60
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup tips
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    # Initial state screenshot
    DISPLAY=:1 scrot /tmp/hmmer_task_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="