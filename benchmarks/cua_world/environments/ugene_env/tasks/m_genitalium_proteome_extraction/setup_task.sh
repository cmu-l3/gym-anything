#!/bin/bash
echo "=== Setting up M. genitalium Proteome Extraction task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/genomes 2>/dev/null || true
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/genomes
mkdir -p /home/ga/UGENE_Data/results

# 2. Download the real M. genitalium complete genome (NC_000908.2) from NCBI
GENOME_FILE="/home/ga/UGENE_Data/genomes/m_genitalium_genome.gb"
echo "Downloading M. genitalium genome from NCBI..."

# Try primary NCBI eutils endpoint
wget -q -T 30 -O "$GENOME_FILE" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NC_000908.2&rettype=gbwithparts&retmode=text"

# Validate download
if [ ! -s "$GENOME_FILE" ] || ! grep -q "LOCUS" "$GENOME_FILE"; then
    echo "WARNING: Failed to download from NCBI. Generating fallback GenBank file..."
    # Create a minimal valid GenBank file with CDS and transl_table=4 for testing if network fails
    cat > "$GENOME_FILE" << 'EOF'
LOCUS       NC_000908                500 bp    DNA     circular CON 15-JAN-2024
DEFINITION  Mycoplasma genitalium G37, complete sequence.
ACCESSION   NC_000908
VERSION     NC_000908.2
KEYWORDS    .
SOURCE      Mycoplasma genitalium G37
  ORGANISM  Mycoplasma genitalium G37
FEATURES             Location/Qualifiers
     source          1..500
                     /organism="Mycoplasma genitalium G37"
     CDS             10..150
                     /transl_table=4
                     /product="dummy protein 1"
                     /protein_id="NP_000001.1"
     CDS             200..350
                     /transl_table=4
                     /product="dummy protein 2 containing UGA"
                     /protein_id="NP_000002.1"
ORIGIN
        1 aaaaaaaaaatgccccccgg ggggaaaaaa ccccccgggg ggaaaaaacc ccccgggggg
       61 aaaaaacccc ccggggggaa aaaacccccc ggggggaaaa aaccccccgg ggggaaaaaa
      121 ccccccgggg ggaaaaaacc cccctgatga aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa
      181 aaaaaaaaaa aaaaaaaaat gccccccgga tgaaaaaacc ccccgggggg aaaaaacccc
      241 ccggggggaa aaaacccccc ggggggaaaa aaccccccgg ggggaaaaaa ccccccgggg
      301 ggaaaaaacc ccccgggggg aaaaaacccc cctgatgaaa aaaaaaaaaa aaaaaaaaaa
      361 aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa
      421 aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa
      481 aaaaaaaaaa aaaaaaaaaa
//
EOF
    # Update ground truth expectation if using fallback
    echo "476" > /tmp/target_cds_count # Will still test for ~476, but fallback is just to avoid crash
else
    echo "Successfully downloaded genome."
fi

chown -R ga:ga /home/ga/UGENE_Data

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch UGENE cleanly
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
    sleep 2
done

# Maximize and focus UGENE
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="