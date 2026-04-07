#!/bin/bash
echo "=== Setting up HBB Intron Extraction Task ==="

# 1. Clean previous run state
rm -rf /home/ga/UGENE_Data/thalassemia_diagnostics 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/thalassemia_diagnostics/results

# 2. Generate the real HBB biological data and exact Ground Truth metrics
# Using Python with a heredoc to prevent bash expansion issues
python3 << 'PYEOF'
import json

# Real Human HBB genomic region (partial sequence covering all exons/introns)
hbb_seq = (
    "ACATTTGCTTCTGACACAACTGTGTTCACTAGCAACCTCAAACAGACACCATGGTGCATCTGACTCCTGAGGAGAAGT"
    "CTGCCGTTACTGCCCTGTGGGGCAAGGTGAACGTGGATGAAGTTGGTGGTGAGGCCCTGGGCAGGTTGGTATCAAGGT"
    "TACAAGACAGGTTTAAGGAGACCAATAGAAACTGGGCATGTGGAGACAGAGAAGACTCTTGGGTTTCTGATAGGCACT"
    "GACTCTCTCTGCCTATTGGTCTATTTTCCCACCCTTAGGCTGCTGGTGGTCTACCCTTGGACCCAGAGGTTCTTTGAG"
    "TCCTTTGGGGATCTGTCCACTCCTGATGCTGTTATGGGCAACCCTAAGGTGAAGGCTCATGGCAAGAAAGTGCTCGGT"
    "GCCTTTAGTGATGGCCTGGCTCACCTGGACAACCTCAAGGGCACCTTTGCCACACTGAGTGAGCTGCACTGTGACAAG"
    "CTGCACGTGGATCCTGAGAACTTCAGGGTGAGTCTATGGGACCCTTGATGTTTTCTTTCCCCTTCTTTTCTATGGTTA"
    "AGTTCATGTCATAGGAAGGGGATAAGTAACAGGGTACAGTTTAGAATGGGAAACAGACGAATGATTGCATCAGTGTGG"
    "AAGTCTCAGGATCGTTTTAGTTTCTTTTATTTGCTGTTCATAACAATTGTTTTCTTTTGTTTAATTCTTGCTTTCTTT"
    "TTTTTTCTTCTCCGCAATTTTTACTATTATACTTAATGCCTTAACATTGTGTATAACAAAAGGAAATATCTCTGAGAT"
    "ACATTAAGTAACTTAAAAAAAAACTTTACACAGTCTGCCTAGTACATTACTATTTGGAATATATGTGTGCTTATTTGC"
    "ATATTCATAATCTCCCTACTTTATTTTCTTTTATTTTTAATTGATACATAATCATTATACATATTTATGGGTTAAAGT"
    "GTAATGTTTTAATATGTGTACACATATTGACCAAATCAGGGTAATTTTGCATTTGTAATTTTAAAAAATGCTTTCTTC"
    "TTTTAATATACTTTTTTGTTTATCTTATTTCTAATACTTTCCCTAATCTCTTTCTTTCAGGGCAATAATGATACAATG"
    "TATCATGCCTCTTTGCACCATTCTAAAGAATAACAGTGATAATTTCTGGGTTAAGGCAATAGCAATATTTCTGCATAT"
    "AAATATTTCTGCATATAAATTGTAACTGATGTAAGAGGTTTCATATTGCTAATAGCAGCTACAATCCAGCTACCATTC"
    "TGCTTTTATTTTATGGTTGGGATAAGGCTGGATTATTCTGAGTCCAAGCTAGGCCCTTTTGCTAATCATGTTCATACC"
    "TCTTATCTTCCTCCCACAGCTCCTGGGCAACGTGCTGGTCTGTGTGCTGGCCCATCACTTTGGCAAAGAATTCACCCC"
    "ACCAGTGCAGGCTGCCTATCAGAAAGTGGTGGCTGGTGTGGCTAATGCCCTGGCCCACAAGTATCACTAAGCTCGCTT"
    "TCTTGCTGTCCAATTTCTATTAAAGGTTCCTTTGTTCCCTAAGTCCAACTACTAAACTGGGGGATATTATGAAGGGCC"
    "TTGAGCATCTGGATTCTGCCTAATAAAAAACATTTATTTTCATTGCAA"
)

# Coordinates based on the sequence
# Exon 1: 51..142
# Exon 2: 273..495
# Exon 3: 1346..1474
e1_s, e1_e = 51, 142
e2_s, e2_e = 273, 495
e3_s, e3_e = 1346, 1474

# Calculate Introns (1-based inclusive, perfectly bridging exons)
i1_s, i1_e = e1_e + 1, e2_s - 1
i2_s, i2_e = e2_e + 1, e3_s - 1

i1_seq = hbb_seq[i1_s-1 : i1_e]
i2_seq = hbb_seq[i2_s-1 : i2_e]

def get_gc_percent(s):
    if not s: return 0.0
    return (s.count('G') + s.count('C')) / len(s) * 100

# Write the exact ground truth for the verifier
gt = {
    "i1_start": i1_s,
    "i1_end": i1_e,
    "i2_start": i2_s,
    "i2_end": i2_e,
    "i1_len": i1_e - i1_s + 1,
    "i2_len": i2_e - i2_s + 1,
    "i1_seq": i1_seq,
    "i2_seq": i2_seq,
    "i1_gc": get_gc_percent(i1_seq),
    "i2_gc": get_gc_percent(i2_seq)
}

with open('/tmp/hbb_intron_gt.json', 'w') as f:
    json.dump(gt, f)

# Format the sequence to standard GenBank ORIGIN
def format_origin(seq):
    lines = []
    for i in range(0, len(seq), 60):
        chunk = seq[i:i+60].lower()
        blocks = [chunk[j:j+10] for j in range(0, len(chunk), 10)]
        lines.append(f"{i+1:9} " + " ".join(blocks))
    return "\n".join(lines)

gb_file = f"""LOCUS       HBB_genomic             {len(hbb_seq)} bp    DNA     linear   PRI 01-JAN-2024
DEFINITION  Homo sapiens hemoglobin subunit beta (HBB) gene.
ACCESSION   HBB_DIAGNOSTIC_001
VERSION     HBB_DIAGNOSTIC_001.1
SOURCE      Homo sapiens (human)
  ORGANISM  Homo sapiens
FEATURES             Location/Qualifiers
     source          1..{len(hbb_seq)}
                     /organism="Homo sapiens"
                     /mol_type="genomic DNA"
                     /chromosome="11"
     gene            1..{len(hbb_seq)}
                     /gene="HBB"
     mRNA            join({e1_s}..{e1_e},{e2_s}..{e2_e},{e3_s}..{e3_e})
                     /gene="HBB"
                     /product="hemoglobin subunit beta"
     CDS             join({e1_s}..{e1_e},{e2_s}..{e2_e},{e3_s}..{e3_e})
                     /gene="HBB"
                     /product="hemoglobin subunit beta"
     exon            {e1_s}..{e1_e}
                     /gene="HBB"
                     /number=1
     exon            {e2_s}..{e2_e}
                     /gene="HBB"
                     /number=2
     exon            {e3_s}..{e3_e}
                     /gene="HBB"
                     /number=3
ORIGIN
{format_origin(hbb_seq)}
//
"""

with open('/home/ga/UGENE_Data/thalassemia_diagnostics/hbb_genomic.gb', 'w') as f:
    f.write(gb_file)
PYEOF

# Set permissions
chown -R ga:ga /home/ga/UGENE_Data/thalassemia_diagnostics

# 3. Record task start time (Anti-gaming check)
date +%s > /tmp/task_start_time

# 4. Clear existing instances and launch UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE UI window
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
    sleep 4
    # Maximize and Focus
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    fi
    # Esc away any potential tips/dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Capture initial state proof
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
else
    echo "WARNING: UGENE window did not start correctly."
fi

echo "=== Task setup complete ==="