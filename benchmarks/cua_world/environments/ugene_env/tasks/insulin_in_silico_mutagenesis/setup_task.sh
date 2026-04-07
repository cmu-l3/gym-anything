#!/bin/bash
echo "=== Setting up insulin_in_silico_mutagenesis task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/results 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/results
mkdir -p /home/ga/UGENE_Data/

# 2. Create the exact wild-type human insulin GenBank file (NM_000207.3)
# We generate it here to ensure 100% reproducibility and exact sequence coordinates
cat > /home/ga/UGENE_Data/human_insulin_gene.gb << 'EOF'
LOCUS       NM_000207                469 bp    mRNA    linear   PRI 15-FEB-2024
DEFINITION  Homo sapiens insulin (INS), transcript variant 1, mRNA.
ACCESSION   NM_000207
VERSION     NM_000207.3
SOURCE      Homo sapiens (human)
  ORGANISM  Homo sapiens
FEATURES             Location/Qualifiers
     source          1..469
                     /organism="Homo sapiens"
                     /mol_type="mRNA"
                     /db_xref="taxon:9606"
     gene            1..469
                     /gene="INS"
     CDS             60..392
                     /gene="INS"
                     /product="preproinsulin"
                     /translation="MALWMRLLPLLALLALWGPDPAAAFVNQHLCGSHLVEALYLVCG
                     ERGFFYTPKTRREAEDLQVGQVELGGGPGAGSLQPLALEGSLQKRGIVEQCCTSICSL
                     YQLENYCN"
ORIGIN
        1 agccctccag gacaggctgc atcagaagag gccatcaagc agatcactgt ccttctgcca
       61 tggccctgtg gatgcgcctc ctgcccctgc tggcgctgct ggccctctgg ggacctgacc
      121 cagccgcagc ctttgtgaac caacacctgt gcggctcaca cctggtggaa gctctctacc
      181 tagtgtgcgg ggaacgaggc ttcttctaca cacccaagac ccgccgggag gcagaggacc
      241 tgcaggtggg gcaggtggag ctgggcgggg gccctggtgc aggcagcctg cagcccttgg
      301 ccctggaggg gtccctgcag aagcgtggca ttgtggaaca atgctgtacc agcatctgct
      361 ccctctacca gctggagaac tactgcaact agacgcagcc tgcaggcagc cccacacccg
      421 ccgcctcctg caccgagaga gatggaataa agcccttgaa ccagcaaaa
//
EOF

chown -R ga:ga /home/ga/UGENE_Data

# 3. Record initial timestamps (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Manage UGENE instances
echo "Stopping any existing UGENE instances..."
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true

echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE to appear
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
fi

# 5. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="