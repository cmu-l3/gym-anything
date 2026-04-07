#!/bin/bash
set -e

echo "=== Setting up custom_pwm_promoter_search task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create necessary directories
DATA_DIR="/home/ga/UGENE_Data/promoters"
RESULTS_DIR="$DATA_DIR/results"

rm -rf "$DATA_DIR" 2>/dev/null || true
mkdir -p "$RESULTS_DIR"

# 1. Create the verified promoter FASTA (10 real B. subtilis sequences, 15bp each)
cat > "$DATA_DIR/sigmaA_promoters.fasta" << 'EOF'
>promoter_1_veg
AAAGGTTATAATGAA
>promoter_2_amyE
CCTCGTTATAATGGA
>promoter_3_aprE
CAAAACTATAATATC
>promoter_4_nprE
AGTAAATATAATGCC
>promoter_5_sacB
GACTGATATAATGAA
>promoter_6_groE
TGAATATATAATAAA
>promoter_7_ptsG
GTTGTTTATAATGCA
>promoter_8_xylA
TAGGGATATAATGGT
>promoter_9_spoVG
AGCGGATATAATGGA
>promoter_10_hag
TCTAGATATAATAAC
EOF

# 2. Download real B. subtilis target sequence (first 10kb of AL009126.3)
echo "Fetching real B. subtilis target region from NCBI..."
TARGET_FASTA="$DATA_DIR/B_subtilis_target_region.fasta"

if ! wget --timeout=15 -qO "$TARGET_FASTA" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=AL009126.3&seq_start=1&seq_stop=10000&rettype=fasta&retmode=text"; then
    echo "NCBI fetch failed, using realistic fallback sequence..."
    # Fallback to a synthetic but biologically structured sequence if offline
    cat > "$TARGET_FASTA" << 'EOF'
>AL009126.3_target_region Bacillus subtilis subsp. subtilis str. 168 chromosome, partial
ATGGAAATCAAAGTTTTGCGTTCATCAGCTCGTGCAGCGCGTTCTTCACAAACAAAAGCA
GATAAAACCATAGCAATTTTCATCAAAGAACGCATTGCTAAAGCAATCGCAGAACGAGCT
ACCACTAAAACGCCAGTTAAAAAACAAACAGAAAAGCAAAGTAAAGAAAAACAAAAAGCT
TCTGAAAAGCAAAAGAAAGAAACAAAAGCTTCAGAAAAACAAAAAGCTTCAGAGAAACAA
AAAGCTTCAGAAAAACAAAAAGCTTCAGAAAAACAAAAAGCTTCAGAAAAACAAAAAGCA
ACAGAGAAACAAGCAAAAGCAAGAAAACAACAAAAGCAAGAAAAAAAGAAAAAGAAAAAG
TAGAATATAATAAAATGAAGAAGAAAAAAGAAAAAAGAAAAAGTAGAATATAATAAAATG
AAGAAGAAAAAAGAAAAAAGAAAAAGTAGAATATAATAAAATGAAGAAGAAAAAAGAAAA
GTTGTTTATAATGCACAGTCGATGGCTAAAAAAGTAGCTGAACGTGTTCAAGCTATCACT
EOF
    # Duplicate the chunk to simulate a larger sequence
    for i in {1..20}; do
        cat "$TARGET_FASTA" | grep -v "^>" >> "${TARGET_FASTA}.tmp"
    done
    echo ">AL009126.3_target_region Bacillus subtilis subsp. subtilis str. 168 chromosome, partial" > "$TARGET_FASTA"
    cat "${TARGET_FASTA}.tmp" | tr -d '\n' | fold -w 60 >> "$TARGET_FASTA"
    rm "${TARGET_FASTA}.tmp"
fi

# Set proper permissions
chown -R ga:ga "$DATA_DIR"

# 3. Kill any existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

# 4. Launch UGENE and wait for window
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected."
        break
    fi
    sleep 2
done

# Maximize and focus UGENE
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="