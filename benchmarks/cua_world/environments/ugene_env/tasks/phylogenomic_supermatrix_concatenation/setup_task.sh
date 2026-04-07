#!/bin/bash
set -e
echo "=== Setting up Phylogenomic Supermatrix Concatenation task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean any existing state
rm -rf /home/ga/UGENE_Data/phylogenomics 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/phylogenomics/results

# Generate real biological data excerpts (Enterobacteriaceae housekeeping genes)
# recA sequences (~105bp highly conserved region)
cat > /home/ga/UGENE_Data/phylogenomics/recA_unaligned.fasta << 'EOF'
>Ecoli
ATGGCTATCGACGAAAACAAACAGAAAGCGTTGGCGGCAGCACTGGGCCAGATTGAGAAACAATTTGGTAAAGGCTCCATCATGCGCCTGGGTGAAGACCGTTCC
>Senterica
ATGGCTATCGACGAAAACAAACAGAAAGCGTTGGCGGCAGCACTGGGCCAGATTGAGAAACAATTTGGTAAAGGCTCCATCATGCGCCTGGGCGAAGACCGTTCC
>Ypestis
ATGGCTATTGATGAGAACAAACAAAAGGCACTGGCCGCAGCACTGGGCCAAATTGAAAAGCAATTCGGTAAAGGCTCTATCATGCGCCTGGGCGAAGACCGCTCA
>Sflexneri
ATGGCTATCGACGAAAACAAACAGAAAGCGTTGGCGGCAGCACTGGGCCAGATTGAGAAACAATTTGGTAAAGGCTCCATCATGCGCCTGGGTGAAGACCGTTCC
>Vcholerae
ATGGACGAGAACAAACAGAAAGCGCTGGCCGCAGCACTGGGTCAGATTGAGAAACAATTTGGTAAAGGCTCCATCATGCGTCTGGGTGAAGACCGTTCT
EOF

# rpoB sequences (~99bp highly conserved region)
cat > /home/ga/UGENE_Data/phylogenomics/rpoB_unaligned.fasta << 'EOF'
>Ecoli
ATGGTTACTAACCCTCTATTCGGTATCACCTCTTCCGTTACTCGTACCGAAGCCCGTCGTCTCAACCGACTCGCTCGTGCTCAATTATCTGAGTTAATC
>Senterica
ATGGTTACTAACCCTCTATTCGGTATCACCTCTTCCGTTACTCGCACCGAAGCCCGTCGTCTCAACCGACTCGCTCGTGCTCAATTATCTGAGTTAATC
>Ypestis
ATGGTTACGAACCCGCTGTTCGGTATCACCTCCAGCGTTACTCGCACGGAAGCGCGTCGTCTGAACCGCCTTGCCCGCGCCCAGTTGTCGGAGCTGATT
>Sflexneri
ATGGTTACTAACCCTCTATTCGGTATCACCTCTTCCGTTACTCGTACCGAAGCCCGTCGTCTCAACCGACTCGCTCGTGCTCAATTATCTGAGTTAATC
>Vcholerae
ATGGTTTCTAACCCGCTATTCGGTATTACTTCGTCTGTTACTCGTACCGAAGCGCGTCGTTTGAACCGTCTTGCTCGCGCTCAATTATCTGAATTAATT
EOF

# Ensure correct ownership
chown -R ga:ga /home/ga/UGENE_Data/phylogenomics

# Ensure UGENE is running and focused
if ! pgrep -f "ugene" > /dev/null; then
    echo "Starting UGENE..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
    
    # Wait for UGENE to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "ugene\|UGENE\|Unipro"; then
            break
        fi
        sleep 1
    done
fi

# Dismiss popups, maximize, and focus
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="