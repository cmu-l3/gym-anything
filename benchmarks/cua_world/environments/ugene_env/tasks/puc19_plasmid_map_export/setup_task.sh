#!/bin/bash
echo "=== Setting up puc19_plasmid_map_export task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/UGENE_Data/plasmid/results
rm -f /home/ga/UGENE_Data/plasmid/results/* 2>/dev/null || true

# Download the real pUC19 cloning vector (M77789.2) from NCBI
echo "Downloading pUC19 GenBank file from NCBI..."
curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=M77789.2&rettype=gb&retmode=text" -o /home/ga/UGENE_Data/plasmid/pUC19.gb

# Fallback in case of NCBI API network issues
if [ ! -s "/home/ga/UGENE_Data/plasmid/pUC19.gb" ] || ! grep -q "LOCUS" "/home/ga/UGENE_Data/plasmid/pUC19.gb"; then
    echo "NCBI download failed, using alternative source..."
    curl -s "https://raw.githubusercontent.com/manulera/pSensi/master/pUC19.gb" -o /home/ga/UGENE_Data/plasmid/pUC19.gb
fi

# Fallback: generating a minimal valid mock if ALL network fails (to prevent task crash)
if [ ! -s "/home/ga/UGENE_Data/plasmid/pUC19.gb" ] || ! grep -q "LOCUS" "/home/ga/UGENE_Data/plasmid/pUC19.gb"; then
    echo "Network completely failed. Generating minimal emergency GenBank."
    cat > /home/ga/UGENE_Data/plasmid/pUC19.gb << 'EOF'
LOCUS       M77789                  2686 bp    DNA     circular SYN 18-JUL-2005
DEFINITION  Cloning vector pUC19.
ACCESSION   M77789
VERSION     M77789.2
FEATURES             Location/Qualifiers
     source          1..2686
     gene            162..1196
                     /gene="bla"
     CDS             162..1196
                     /gene="bla"
                     /product="beta-lactamase"
     rep_origin      1735..2323
                     /direction=RIGHT
ORIGIN
        1 tcgcgcgttt cggtgatgac ggtgaaaacc tctgacacat gcagctcccg gagacggtca
       61 cagcttgtct gtaagcggat gccgggagca gacaagcccg tcagggcgcg tcagcgggtg
      121 ttggcgggtg tcggggctgg cttaactatg cggcatcaga gcagattgta ctgagagtgc
      181 accatatgcg gtgtgaaata ccgcacagat gcgtaaggag aaaataccgc atcaggcgcc
      241 attcgccatt caggctgcgc aactgttggg aagggcgatc ggtgcgggcc tcttcgctat
      301 tacgccagct ggcgaaaggg ggatgtgctg caaggcgatt aagttgggta acgccagggt
      361 ttcccagtca cgacgttgta aaacgacggc cagtgaattc gagctcggta cccggggatc
      421 ctctagagtc gacctgcagg catgcaagct tggcgtaatc atggtcatag ctgtttcctg
//
EOF
fi

chown -R ga:ga /home/ga/UGENE_Data/plasmid

# Start UGENE if not running
if ! pgrep -f "ugene" > /dev/null; then
    echo "Starting UGENE..."
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
    sleep 5
fi

# Wait for UGENE window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected"
        break
    fi
    sleep 1
done

# Focus and maximize UGENE
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="