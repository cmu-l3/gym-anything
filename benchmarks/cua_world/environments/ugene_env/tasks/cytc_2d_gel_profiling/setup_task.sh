#!/bin/bash
echo "=== Setting up cytc_2d_gel_profiling task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
chown -R ga:ga /home/ga/UGENE_Data/results
rm -f /tmp/cytc_2d_gel_profiling_* 2>/dev/null || true

# 2. Verify input data exists
if [ ! -s /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta ]; then
    echo "ERROR: Cytochrome c FASTA file not found or empty"
    # Fallback to assets if missing
    cp /workspace/assets/cytochrome_c_multispecies.fasta /home/ga/UGENE_Data/cytochrome_c_multispecies.fasta 2>/dev/null || true
fi

# 3. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Generate Ground Truth JSON dynamically using Python
# We compute theoretical MW and pI for the actual sequences present in the FASTA.
python3 << 'PYEOF'
import json

def calculate_mw(seq):
    masses = {'A': 71.0788, 'R': 156.1875, 'N': 114.1038, 'D': 115.0886,
              'C': 103.1388, 'E': 129.1155, 'Q': 128.1307, 'G': 57.0519,
              'H': 137.1411, 'I': 113.1594, 'L': 113.1594, 'K': 128.1741,
              'M': 131.1926, 'F': 147.1766, 'P': 97.1167, 'S': 87.0773,
              'T': 101.1051, 'W': 186.2132, 'Y': 163.1760, 'V': 99.1326}
    # Add water mass for intact protein
    return sum(masses.get(aa, 0) for aa in seq) + 18.01524

def calculate_pi(seq):
    # EMBOSS pKa values
    pKa = {'N_term': 8.6, 'K': 10.8, 'R': 12.5, 'H': 6.5,
           'C_term': 3.6, 'D': 3.9, 'E': 4.1, 'C': 8.5, 'Y': 10.9}

    def net_charge(pH):
        charge = 1.0 / (1.0 + 10**(pH - pKa['N_term']))
        charge += seq.count('K') / (1.0 + 10**(pH - pKa['K']))
        charge += seq.count('R') / (1.0 + 10**(pH - pKa['R']))
        charge += seq.count('H') / (1.0 + 10**(pH - pKa['H']))
        charge -= 1.0 / (1.0 + 10**(pKa['C_term'] - pH))
        charge -= seq.count('D') / (1.0 + 10**(pKa['D'] - pH))
        charge -= seq.count('E') / (1.0 + 10**(pKa['E'] - pH))
        charge -= seq.count('C') / (1.0 + 10**(pKa['C'] - pH))
        charge -= seq.count('Y') / (1.0 + 10**(pKa['Y'] - pH))
        return charge

    min_pH, max_pH = 0.0, 14.0
    for _ in range(100):
        mid_pH = (min_pH + max_pH) / 2
        if net_charge(mid_pH) > 0:
            min_pH = mid_pH
        else:
            max_pH = mid_pH
    return (min_pH + max_pH) / 2

fasta_file = "/home/ga/UGENE_Data/cytochrome_c_multispecies.fasta"
ground_truth = {}
try:
    with open(fasta_file, 'r') as f:
        lines = f.readlines()
        
    curr_acc = None
    curr_seq = []
    
    for line in lines:
        line = line.strip()
        if line.startswith(">"):
            if curr_acc:
                seq_str = "".join(curr_seq).upper()
                ground_truth[curr_acc] = {
                    "length": len(seq_str),
                    "mw": calculate_mw(seq_str),
                    "pi": calculate_pi(seq_str)
                }
            # Extract first word as accession (e.g. "tr|P99999|..." -> "P99999" or full header)
            # We'll just store the main identifier if possible, or full string without >
            header = line[1:].split()[0]
            if '|' in header:
                header = header.split('|')[1] # Get accession from UniProt format
            curr_acc = header
            curr_seq = []
        else:
            curr_seq.append(line)
            
    if curr_acc:
        seq_str = "".join(curr_seq).upper()
        ground_truth[curr_acc] = {
            "length": len(seq_str),
            "mw": calculate_mw(seq_str),
            "pi": calculate_pi(seq_str)
        }
        
    # Find overall min/max pI accessions
    min_pi_acc = min(ground_truth.keys(), key=lambda k: ground_truth[k]['pi'])
    max_pi_acc = max(ground_truth.keys(), key=lambda k: ground_truth[k]['pi'])
    
    output = {
        "sequences": ground_truth,
        "min_pi_acc": min_pi_acc,
        "max_pi_acc": max_pi_acc
    }
    
    with open("/tmp/cytc_2d_gel_profiling_gt.json", "w") as f:
        json.dump(output, f, indent=2)
except Exception as e:
    print(f"Failed to generate ground truth: {e}")
PYEOF

chown ga:ga /tmp/cytc_2d_gel_profiling_gt.json 2>/dev/null || true

# 5. Ensure UGENE is ready
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected"
        break
    fi
    sleep 2
done

# Maximize UGENE
sleep 3
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="