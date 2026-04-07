#!/bin/bash
echo "=== Setting up spidroin_codon_usage_profiling task ==="

# Clean old state
rm -rf /home/ga/UGENE_Data/spidroin/results 2>/dev/null || true
rm -f /tmp/spidroin_* 2>/dev/null || true

mkdir -p /home/ga/UGENE_Data/spidroin/results

echo "Downloading MaSp1 GenBank sequence from NCBI..."
wget -q -O /home/ga/UGENE_Data/spidroin/masp1_sequence.gb "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nucleotide&id=M62820.1&rettype=gb&retmode=text" || true

if [ ! -s "/home/ga/UGENE_Data/spidroin/masp1_sequence.gb" ] || ! grep -q "LOCUS" "/home/ga/UGENE_Data/spidroin/masp1_sequence.gb"; then
    echo "Download failed, using fallback sequence..."
    cat > /home/ga/UGENE_Data/spidroin/masp1_sequence.gb << 'EOF'
LOCUS       M62820                  1122 bp    mRNA    linear   INV 02-APR-1994
DEFINITION  Nephila clavipes major ampullate spidroin 1 (MaSp1) mRNA, partial
            cds.
ACCESSION   M62820
VERSION     M62820.1
KEYWORDS    MaSp1; dragline silk; major ampullate spidroin 1; silk protein;
            spidroin.
SOURCE      Nephila clavipes (golden silk spider)
  ORGANISM  Nephila clavipes
            Eukaryota; Metazoa; Ecdysozoa; Arthropoda; Chelicerata; Arachnida;
            Araneae; Araneomorphae; Entelegynae; Araneoidea; Araneidae;
            Nephila.
FEATURES             Location/Qualifiers
     source          1..1122
                     /organism="Nephila clavipes"
                     /mol_type="mRNA"
                     /db_xref="taxon:6915"
                     /clone="pSpidroin 1"
                     /tissue_type="major ampullate silk gland"
     gene            <1..>1122
                     /gene="MaSp1"
     CDS             <1..>1122
                     /gene="MaSp1"
                     /codon_start=1
                     /product="major ampullate spidroin 1"
                     /protein_id="AAA29367.1"
                     /translation="GQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAG
                     QGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAG
                     GAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAA
                     AAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGA
                     AAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQG
                     AGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGRG
                     GQGAGAAAAAAGGAGQGGYGGLGSQGAGRGGQGAGAAAAAAGGAGQGGYGGLGSQGA
                     GRGGQGAGAAAAAAGGAGQGGYGGLGSQGAGR"
ORIGIN      
        1 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
       61 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
      121 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
      181 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
      241 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
      301 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
      361 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
      421 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
      481 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
      541 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
      601 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
      661 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
      721 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
      781 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
      841 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
      901 ggccaaggag caggtgcagc agcagcagca gcaggaggag ccggtcaagg aggatatgga
      961 ggacttggaa gtcaaggagc aggacgagga ggccaaggag caggtgcagc agcagcagca
     1021 gcaggaggag ccggtcaagg aggatatgga ggacttggaa gtcaaggagc aggacgagga
     1081 ggccaaggag caggtgcagc agcagcagca gcaggaggag cc
//
EOF
fi

chown -R ga:ga /home/ga/UGENE_Data/spidroin

echo "Computing ground truth..."
python3 << 'PYEOF'
import sys, re, json

with open("/home/ga/UGENE_Data/spidroin/masp1_sequence.gb") as f:
    text = f.read()

origin_match = re.search(r'ORIGIN\s+(.*?)(?://)', text, re.DOTALL)
if not origin_match:
    sys.exit(1)
    
seq = re.sub(r'[\d\s\n]', '', origin_match.group(1)).upper()

cds_match = re.search(r'CDS\s+(?:<)?(\d+)\.\.(?:>)?(\d+)', text)
if cds_match:
    start = int(cds_match.group(1)) - 1
    end = int(cds_match.group(2))
    seq = seq[start:end]

codon_table = {
    'ATA':'I', 'ATC':'I', 'ATT':'I', 'ATG':'M',
    'ACA':'T', 'ACC':'T', 'ACG':'T', 'ACT':'T',
    'AAC':'N', 'AAT':'N', 'AAA':'K', 'AAG':'K',
    'AGC':'S', 'AGT':'S', 'AGA':'R', 'AGG':'R',
    'CTA':'L', 'CTC':'L', 'CTG':'L', 'CTT':'L',
    'CCA':'P', 'CCC':'P', 'CCG':'P', 'CCT':'P',
    'CAC':'H', 'CAT':'H', 'CAA':'Q', 'CAG':'Q',
    'CGA':'R', 'CGC':'R', 'CGG':'R', 'CGT':'R',
    'GTA':'V', 'GTC':'V', 'GTG':'V', 'GTT':'V',
    'GCA':'A', 'GCC':'A', 'GCG':'A', 'GCT':'A',
    'GAC':'D', 'GAT':'D', 'GAA':'E', 'GAG':'E',
    'GGA':'G', 'GGC':'G', 'GGG':'G', 'GGT':'G',
    'TCA':'S', 'TCC':'S', 'TCG':'S', 'TCT':'S',
    'TTC':'F', 'TTT':'F', 'TTA':'L', 'TTG':'L',
    'TAC':'Y', 'TAT':'Y', 'TAA':'_', 'TAG':'_',
    'TGC':'C', 'TGT':'C', 'TGA':'_', 'TGG':'W',
}

prot = []
codons = []
for i in range(0, len(seq)-2, 3):
    c = seq[i:i+3]
    codons.append(c)
    prot.append(codon_table.get(c, 'X'))

aa_counts = {}
for aa in prot:
    aa_counts[aa] = aa_counts.get(aa, 0) + 1

most_abundant_aa = max(aa_counts, key=aa_counts.get)

gly_codons = {}
ala_codons = {}

for c, aa in zip(codons, prot):
    if aa == 'G':
        gly_codons[c] = gly_codons.get(c, 0) + 1
    elif aa == 'A':
        ala_codons[c] = ala_codons.get(c, 0) + 1

top_gly = max(gly_codons, key=gly_codons.get) if gly_codons else ""
top_ala = max(ala_codons, key=ala_codons.get) if ala_codons else ""

gt = {
    "protein_length": len(prot),
    "most_abundant_aa": "Glycine" if most_abundant_aa == 'G' else most_abundant_aa,
    "top_gly_codon": top_gly,
    "top_ala_codon": top_ala,
    "gly_ala_fraction": (aa_counts.get('G',0) + aa_counts.get('A',0)) / max(1, len(prot))
}

with open("/tmp/spidroin_gt.json", "w") as f:
    json.dump(gt, f)
PYEOF

date +%s > /tmp/task_start_time.txt

# Start UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

TIMEOUT=90
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
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="