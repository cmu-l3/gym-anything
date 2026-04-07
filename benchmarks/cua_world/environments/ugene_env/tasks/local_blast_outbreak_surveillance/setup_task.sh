#!/bin/bash
echo "=== Setting up Local BLAST Outbreak Surveillance task ==="

# 1. Install required system packages for local BLAST
echo "Installing ncbi-blast+..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ncbi-blast+

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Clean and prepare directories
OUTBREAK_DIR="/home/ga/UGENE_Data/outbreak"
rm -rf "$OUTBREAK_DIR" 2>/dev/null || true
mkdir -p "$OUTBREAK_DIR/blast_db"
mkdir -p "$OUTBREAK_DIR/results"

# 4. Generate Data (Fallback to local generation if network fails to ensure reliability)
echo "Generating sequence data..."

# mcr-1 Reference Sequence Snippet (Real conserved region of mcr-1)
MCR1_SEQ="ATGATGCAGCATACTTCTGTGTGGTACCGACGCTCGGTCAGTCCGTTTGTTCTTGTGGCGAGTGGCTGCGGATCCTTCACTGATTTCCGCAAGGTAGCGTTTGCCTCCGTATCTACCATTGGAACAATTCCGACTCGCCAATAGCTTGATTCCATTGATAACCGAATATATCGTGCA"

cat > "$OUTBREAK_DIR/mcr_1_reference.fasta" << EOF
>mcr_1_reference_gene
$MCR1_SEQ
EOF

# Plasmid Contigs for Swabs
# Swab A gets the mcr-1 sequence embedded in it
cat > "$OUTBREAK_DIR/environmental_swabs.fasta" << EOF
>Hospital_Swab_A_Isolate
CGATCGACTGACTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
TAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
$MCR1_SEQ
CGATCGACTGACTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
TAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
>Hospital_Swab_B_Isolate
ATGCGTACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
>Hospital_Swab_C_Isolate
TTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
EOF

chown -R ga:ga "$OUTBREAK_DIR"

# 5. Launch UGENE
echo "Launching UGENE..."
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 6. Wait for UGENE window
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
        sleep 1
    fi
    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
else
    echo "WARNING: UGENE failed to launch."
fi

echo "=== Setup complete ==="