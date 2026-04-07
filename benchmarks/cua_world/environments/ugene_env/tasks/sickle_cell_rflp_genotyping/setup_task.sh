#!/bin/bash
echo "=== Setting up sickle_cell_rflp_genotyping task ==="

# Clean previous state and create directories
rm -rf /home/ga/UGENE_Data/rflp_genotyping 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/rflp_genotyping/results

# Generate synthetic yet accurate DNA sequences modeling the sickle cell mutation
# Wild-type has two DdeI (CTNAG) sites. Mutant has only one.
python3 << 'PYEOF'
import random
import re

random.seed(42)

def check(seq):
    return len(re.findall(r'CT[ACTG]AG', seq))

while True:
    part1 = "".join(random.choice("ACGT") for _ in range(99))
    part2 = "".join(random.choice("ACGT") for _ in range(92))
    part3 = "".join(random.choice("ACGT") for _ in range(199))
    
    # DdeI cuts after the first C. Sites are positioned exactly to yield fragments of length 100, 97, 203
    wt = part1 + "CTCAG" + part2 + "CTGAG" + part3
    
    # In the mutant, the second site is mutated (A>T transversion like sickle cell) so it no longer cuts
    mut = part1 + "CTCAG" + part2 + "CTGTG" + part3
    
    if check(wt) == 2 and check(mut) == 1:
        with open("/home/ga/UGENE_Data/rflp_genotyping/hbb_wildtype_amplicon.fasta", "w") as f:
            f.write(">hbb_wildtype_amplicon\n" + wt + "\n")
        with open("/home/ga/UGENE_Data/rflp_genotyping/hbb_mutant_amplicon.fasta", "w") as f:
            f.write(">hbb_mutant_amplicon\n" + mut + "\n")
        break
PYEOF

chown -R ga:ga /home/ga/UGENE_Data/rflp_genotyping

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        break
    fi
    sleep 2
done

sleep 5

# Dismiss any startup tips or dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize UGENE window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="