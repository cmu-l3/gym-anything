#!/bin/bash
echo "=== Setting up egfp_lc3b_fusion_construction task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/fusion_design 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/fusion_design/results

# 2. Fetch GenBank records from NCBI (Real data fetching)
echo "Downloading pEGFP-C1 (U55763.1)..."
wget -q -O /home/ga/UGENE_Data/fusion_design/pEGFP-C1.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=U55763.1&rettype=gb&retmode=text"

echo "Downloading MAP1LC3B (NM_022818.5)..."
wget -q -O /home/ga/UGENE_Data/fusion_design/MAP1LC3B.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_022818.5&rettype=gb&retmode=text"

chown -R ga:ga /home/ga/UGENE_Data/fusion_design

# 3. Generate Ground Truth exactly from the downloaded data 
# (Ensures verification matches the specific NCBI version retrieved)
python3 << 'PYEOF'
import re
import json

def parse_cds(gb_file):
    try:
        with open(gb_file, 'r') as f:
            content = f.read()
        
        # Get sequence
        origin_match = re.search(r'ORIGIN\s+(.*?)(?:\/\/$|\Z)', content, re.DOTALL)
        if not origin_match: return None
        seq = re.sub(r'[\d\s\n]', '', origin_match.group(1)).upper()
        
        # Get CDS coords (regex matches typical CDS joins/spans)
        cds_match = re.search(r'CDS\s+(?:join\()?(\d+)\.\.(\d+)', content)
        if not cds_match: return None
        start = int(cds_match.group(1)) - 1
        end = int(cds_match.group(2))
        return seq[start:end]
    except Exception as e:
        return None

egfp_cds = parse_cds("/home/ga/UGENE_Data/fusion_design/pEGFP-C1.gb")
lc3b_cds = parse_cds("/home/ga/UGENE_Data/fusion_design/MAP1LC3B.gb")

if egfp_cds and lc3b_cds:
    # EGFP minus the 3bp stop codon
    egfp_edited = egfp_cds[:-3]
    fusion_dna = egfp_edited + lc3b_cds
    
    gt = {
        "egfp_cds_len": len(egfp_cds),
        "lc3b_cds_len": len(lc3b_cds),
        "fusion_dna_len": len(fusion_dna),
        "fusion_protein_len": len(fusion_dna) // 3,
        "fusion_dna_seq": fusion_dna
    }
    
    with open("/tmp/fusion_design_gt.json", "w") as f:
        json.dump(gt, f)
PYEOF

# 4. Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Launch and Setup UGENE UI
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

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
    # Dismiss startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    # Maximize window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="