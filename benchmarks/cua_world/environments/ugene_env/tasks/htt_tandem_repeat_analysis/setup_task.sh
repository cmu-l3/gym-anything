#!/bin/bash
echo "=== Setting up htt_tandem_repeat_analysis task ==="

# Clean up any previous results to prevent gaming
mkdir -p /home/ga/UGENE_Data/huntington/results
rm -f /home/ga/UGENE_Data/huntington/results/* 2>/dev/null || true

# Download HTT mRNA GenBank
FILE_PATH="/home/ga/UGENE_Data/huntington/HTT_mRNA.gb"
echo "Downloading HTT mRNA from NCBI..."

for i in 1 2 3; do
    curl -sS "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=NM_002111.8&rettype=gb&retmode=text" > "$FILE_PATH"
    if grep -q "LOCUS" "$FILE_PATH"; then
        break
    fi
    sleep 2
done

# Fallback if download fails completely (bundled minimal GenBank snippet)
if [ ! -s "$FILE_PATH" ] || ! grep -q "LOCUS" "$FILE_PATH"; then
    echo "Download failed, using bundled fallback..."
    cat > "$FILE_PATH" << 'EOF'
LOCUS       NM_002111_FALLBACK  1000 bp    mRNA    linear   PRI 01-JAN-2024
DEFINITION  Homo sapiens huntingtin (HTT), mRNA.
ACCESSION   NM_002111
VERSION     NM_002111.8
KEYWORDS    .
SOURCE      Homo sapiens (human)
  ORGANISM  Homo sapiens
FEATURES             Location/Qualifiers
     source          1..1000
                     /organism="Homo sapiens"
                     /mol_type="mRNA"
ORIGIN
        1 gctgccggga cgggtccaag atggacggcc gctcaggttc tgcttttacc tgcggcccag
       61 agccccattc attgccccgg tgctgagcgg cgccgcgagt cggcccgagg cctccgggga
      121 ctgccgtgcc aggcgcgccc gccgcctctc gcctccgcct ctcgccccgg ccctgcccca
      181 ccgttcgggc ccttccgcga tcgccacgac gaactccgcc cccgccgccc gccgcgccgc
      241 agcgcgggcc ctggttccga atccgccgct tcgcgccggt agccggcgcg cccgcggccc
      301 gcctcctgcc gcgcagcagc agcagcagca gcagcagcag cagcagcagc agcagcagca
      361 gcagcagcag cagcagcaac agccgccacc gccgccgccg ccgccgccgc ctcctcagct
      421 tcctcagccg ccgccgcagg cacagccgct gctgcctcag ccgcagccgc ccccgccgcc
      481 gcccccgccg ccacccggcc cggctgtggc tgaggagccg ctgcaccgac caaagaaaga
      541 actttcagct accaagaaag accgtgtgaa tcattgtctg acaatatgtg aaaacatagt
      601 ggcacagtct gtcagaaatt ctccagaatt tcagaaactt ctgggcatcg ctatggaact
      661 ttttctgctg tgcagtgatg acgcagagtc agatgtcagg atggtggctg acgaatgcct
      721 caacaaagtt atcaaagctt tgatggattc taatcttcca aggttacagc tcgagctcta
      781 taaggaaatt aaaaagaatg gtggccctcg gagtgaactt gcggagctag gaacctctta
      841 tctagaacaa caggaaactt ctggaattgt ggctacctat ataccagcca atcagaagtt
      901 actagaacaa ttgatacaac aggaggcaca aggaactaca tttctacagt tacccaacac
      961 aaattctatt atggacttac agacggaatg aagacatcat
//
EOF
fi

chown -R ga:ga /home/ga/UGENE_Data/huntington

# Record timestamp for anti-gaming verification
date +%s > /tmp/htt_task_start_ts

# Kill existing UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2
pkill -9 -f "ugene" 2>/dev/null || true
sleep 1

# Launch UGENE
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# Wait for UGENE window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        break
    fi
    sleep 2
done

sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
    sleep 2
fi

DISPLAY=:1 scrot /tmp/htt_start_screenshot.png 2>/dev/null || true
echo "=== Task setup complete ==="