#!/bin/bash
echo "=== Setting up 16s_sanger_contig_assembly task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/UGENE_Data/16s_assembly/results
chown -R ga:ga /home/ga/UGENE_Data/16s_assembly

# Generate real E. coli 16S biological sequence data
# We embed the script to guarantee internet-free biological accuracy.
# Read 1 (Fwd): bp 1-750, Read 2 (Rev-Comp): bp 650-1400, Read 3 (Fwd): bp 1300-1541
python3 << 'PYEOF'
import os

# Standard E. coli K-12 16S rRNA sequence (1541 bp)
seq = (
    "AAATTGAAGAGTTTGATCATGGCTCAGATTGAACGCTGGCGGCAGGCCTAACACATGCAAGTCGAACGGTAACAGGAAGCAGCTTGCTGCTTTG"
    "CTGACGAGTGGCGGACGGGTGAGTAATGTCTGGGAAACTGCCTGATGGAGGGGGATAACTACTGGAAACGGTAGCTAATACCGCATAACGTCGC"
    "AAGACCAAAGAGGGGGACCTTCGGGCCTCTTGCCATCGGATGTGCCCAGATGGGATTAGCTAGTAGGTGGGGTAACGGCTCACCTAGGCGACGA"
    "TCCCTAGCTGGTCTGAGAGGATGACCAGCCACACTGGAACTGAGACACGGTCCAGACTCCTACGGGAGGCAGCAGTGGGGAATATTGCACAATG"
    "GGCGCAAGCCTGATGCAGCCATGCCGCGTGTATGAAGAAGGCCTTCGGGTTGTAAAGTACTTTCAGCGGGGAGGAAGGGAGTAAAGTTAATACC"
    "TTTGCTCATTGACGTTACCCGCAGAAGAAGCACCGGCTAACTCCGTGCCAGCAGCCGCGGTAATACGGAGGGTGCAAGCGTTAATCGGAATTAC"
    "TGGGCGTAAAGCGCACGCAGGCGGTTTGTTAAGTCAGATGTGAAATCCCCGGGCTCAACCTGGGAACTGCATCTGATACTGGCAAGCTTGAGTC"
    "TCGTAGAGGGGGGTAGAATTCCAGGTGTAGCGGTGAAATGCGTAGAGATCTGGAGGAATACCGGTGGCGAAGGCGGCCCCCTGGACGAAGACTG"
    "ACGCTCAGGTGCGAAAGCGTGGGGAGCAAACAGGATTAGATACCCTGGTAGTCCACGCCGTAAACGATGTCGACTTGGAGGTTGTGCCCTTGAG"
    "GCGTGGCTTCCGGATAACGCGTTAAGTCGACCGCCTGGGGAGTACGGCCGCAAGGTTAAAACTCAAATGAATTGACGGGGGCCCGCACAAGCGG"
    "TGGAGCATGTGGTTTAATTCGATGCAACGCGAAGAACCTTACCTGGTCTTGACATCCACGGAAGTTTTCAGAGATGAGAATGTGCCTTCGGGAA"
    "CCGTGAGACAGGTGCTGCATGGCTGTCGTCAGCTCGTGTTGTGAAATGTTGGGTTAAGTCCCGCAACGAGCGCAACCCTTATCCTTTGTTGCCA"
    "GCGGTCCGGCCGGGAACTCAAAGGAGACTGCCAGTGATAAACTGGAGGAAGGTGGGGATGACGTCAAGTCATCATGGCCCTTACGACCAGGGCT"
    "ACACACGTGCTACAATGGCGCATACAAAGAGAAGCGACCTCGCGAGAGCAAGCGGACCTCATAAAGTGCGTCGTAGTCCGGATTGGAGTCTGCA"
    "ACTCGACTCCATGAAGTCGGAATCGCTAGTAATCGTGGATCAGAATGCCACGGTGAATACGTTCCCGGGCCTTGTACACACCGCCCGTCACACC"
    "ATGGGAGTGGGTTGCAAAAGAAGTAGGTAGCTTAACCTTCGGGAGGGCGCTTACCACTTTGTGATTCATGACTGGGGTGAAGTCGTAACAAGGT"
    "AACCGTAGGGGAACCTGCGGTTGGATCACCTCCTTA"
)

# Create overlapping fragments
read1 = seq[0:750]
read2_fwd = seq[650:1400]
# Reverse complement Read 2
comp = {'A':'T', 'C':'G', 'G':'C', 'T':'A'}
read2_rev = "".join(comp[b] for b in reversed(read2_fwd))
read3 = seq[1300:]

file_path = "/home/ga/UGENE_Data/16s_assembly/ecoli_16s_reads.fasta"
with open(file_path, "w") as f:
    f.write(">Read_1_Forward\n" + read1 + "\n")
    f.write(">Read_2_Reverse\n" + read2_rev + "\n")
    f.write(">Read_3_Forward\n" + read3 + "\n")

os.chown(file_path, 1000, 1000) # Give 'ga' ownership
PYEOF

echo "Input FASTA generated."

# Ensure UGENE is launched cleanly
pkill -f "ugene" 2>/dev/null || true
sleep 2

echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 1
done

sleep 4

# Maximize and focus the window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Dismiss any startup dialogs (like Tip of the Day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="