#!/bin/bash
echo "=== Setting up GPCR Hydropathy Profiling Task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/protein_properties/results 2>/dev/null || true
rm -f /tmp/gpcr_hydropathy_profiling_* 2>/dev/null || true

# 2. Create directories
mkdir -p /home/ga/UGENE_Data/protein_properties/results
mkdir -p /home/ga/UGENE_Data/protein_properties

# 3. Create the real ADRB2 human protein sequence (UniProt P07550)
cat > /home/ga/UGENE_Data/protein_properties/adrb2_human.fasta << 'FASTA'
>sp|P07550|ADRB2_HUMAN Beta-2 adrenergic receptor OS=Homo sapiens OX=9606 GN=ADRB2 PE=1 SV=1
MGQPGNGSAFLLAPNRSHAPDHDVTQQRDEVWVVGMGIVMSLIVLAIVFGNVLVITAIAK
FERLQTVTNYFITSLACADLVMGLAVVPFGAAHILMKMWTFGNFWCEFWTSIDVLCVTAS
IETLCVIAVDRYFAITSPFKYQSLLTKNKARVIILMVWIVSGLTSFLPIQMHWYRATHQE
AINCYANETCCDFFTNQAYAIASSIVSFYVPLVIMVFVYSRVFQEAKRQLQKIDKSEGRF
HVQNLSQVEQDGRTGHGLRRSSKFCLKEHKALKTLGIIMGTFTLCWLPFFIVNIVHVIQD
NLIRKEVYILLNWIGYVNSGFNPLIYCRSPDFRIAFQELLCLRRSSLKAYGNGYSSNGNT
GEQSGYHVEQEKENKLLCEDLPGTEDFVGHQGTVPSDNIDSQGRNCSTNDSLL
FASTA

chown -R ga:ga /home/ga/UGENE_Data/protein_properties

# 4. Record task start time
date +%s > /tmp/gpcr_hydropathy_profiling_start_ts

# 5. Launch UGENE cleanly
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
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
    # Dismiss tips/welcome
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    
    # Maximize and focus
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    
    # Capture initial screenshot
    DISPLAY=:1 scrot /tmp/gpcr_hydropathy_profiling_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="