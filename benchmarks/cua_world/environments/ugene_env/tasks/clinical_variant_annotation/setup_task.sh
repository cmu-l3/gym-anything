#!/bin/bash
echo "=== Setting up clinical_variant_annotation task ==="

# Step 1: CLEAN
rm -rf /home/ga/UGENE_Data/clinical/results 2>/dev/null || true
rm -f /tmp/clinical_variant_annotation_* 2>/dev/null || true

# Step 2: Create directories
mkdir -p /home/ga/UGENE_Data/clinical/results
mkdir -p /home/ga/UGENE_Data/clinical

# Step 3: Copy the real BRCA1 reference GenBank from bundled assets
# Source: NM_007294.4 from NCBI (7088bp, real BRCA1 mRNA transcript variant 1)
cp /workspace/assets/BRCA1_NM_007294.gb /home/ga/UGENE_Data/clinical/BRCA1_reference.gb

# Step 4: Create the patient BRCA1 GenBank file WITH deliberate errors
# Based on real NM_007294.4 sequence with programmatic error injection
# Errors injected:
#   1. Gene qualifier says "BRCA2" instead of "BRCA1" (annotation error)
#   2. CDS start shifted 15bp upstream (boundary error)
#   3. Missense variant (C>T) injected near position 1205
#   4. 3bp deletion injected near position 1858
python3 << 'PYEOF'
import re, json

# Read the real BRCA1 GenBank file
with open("/home/ga/UGENE_Data/clinical/BRCA1_reference.gb") as f:
    gb_text = f.read()

# Extract the sequence from ORIGIN section
origin_match = re.search(r'ORIGIN\s+(.*?)\/\/', gb_text, re.DOTALL)
raw_seq = origin_match.group(1)
seq = re.sub(r'[\d\s\n]', '', raw_seq).upper()
seq_len = len(seq)

# Take the first 2500bp region (covers exon 10-11 area)
region = list(seq[:2500])
region_len = len(region)

# Inject C>T missense variant near position 1205
variant_pos = 1205
while variant_pos < 1215 and region[variant_pos] != 'C':
    variant_pos += 1
if variant_pos >= 1215:
    variant_pos = 1205
original_base = region[variant_pos]
region[variant_pos] = 'T'

# Inject 3bp deletion near position 1858
del_pos = 1858
deleted_bases = ''.join(region[del_pos:del_pos+3])
region = region[:del_pos] + region[del_pos+3:]

patient_seq = ''.join(region)
patient_len = len(patient_seq)

# Format sequence in GenBank ORIGIN format
origin_lines = []
for i in range(0, patient_len, 60):
    chunk = patient_seq[i:i+60].lower()
    blocks = [chunk[j:j+10] for j in range(0, len(chunk), 10)]
    line = f"{i+1:>9} " + " ".join(blocks)
    origin_lines.append(line)

origin_text = "\n".join(origin_lines)

# Write the patient GenBank file with DELIBERATE annotation errors
gb_content = f"""LOCUS       BRCA1_patient       {patient_len} bp    DNA     linear   PRI 15-FEB-2024
DEFINITION  Homo sapiens BRCA1 gene, exons 10-11 region, patient sample.
ACCESSION   PATIENT_BRCA1_001
VERSION     PATIENT_BRCA1_001.1
SOURCE      Homo sapiens (human)
  ORGANISM  Homo sapiens
            Eukaryota; Metazoa; Chordata; Craniata; Vertebrata;
            Mammalia; Primates; Haplorrhini; Catarrhini; Hominidae;
            Homo.
REFERENCE   1
  AUTHORS   Clinical Sequencing Lab
  TITLE     Patient BRCA1 Region Sequencing Report
  JOURNAL   Unpublished
FEATURES             Location/Qualifiers
     source          1..{patient_len}
                     /organism="Homo sapiens"
                     /mol_type="genomic DNA"
                     /chromosome="17"
                     /gene="BRCA2"
                     /note="Reference: NM_007294.4 BRCA1. C at position {variant_pos+1} in reference."
                     /db_xref="taxon:9606"
     CDS             1..615
                     /gene="BRCA2"
                     /note="Exon 10 coding region - boundaries need verification"
                     /codon_start=1
ORIGIN
{origin_text}
//
"""

with open("/home/ga/UGENE_Data/clinical/patient_BRCA1_region.gb", "w") as f:
    f.write(gb_content)

# Write ground truth
gt = {
    "correct_gene_name": "BRCA1",
    "wrong_gene_name": "BRCA2",
    "correct_cds_start": 16,
    "wrong_cds_start": 1,
    "missense_variant_pos": variant_pos + 1,
    "missense_variant_pos_min": variant_pos - 5,
    "missense_variant_pos_max": variant_pos + 15,
    "deletion_pos": del_pos + 1,
    "deletion_pos_min": del_pos - 10,
    "deletion_pos_max": del_pos + 15,
    "deleted_bases": deleted_bases,
    "sequence_length": patient_len,
    "reference_sequence_length": seq_len
}
with open("/tmp/clinical_variant_annotation_gt.json", "w") as f:
    json.dump(gt, f)

print(f"Created patient BRCA1 file: {patient_len}bp (from real NM_007294.4, {seq_len}bp)")
print(f"Variant pos: {variant_pos+1}, Deletion pos: {del_pos+1}")
print(f"Deleted bases: {deleted_bases}")
PYEOF

chown -R ga:ga /home/ga/UGENE_Data/clinical

# Step 5: RECORD timestamp
date +%s > /tmp/clinical_variant_annotation_start_ts

# Step 6: Record initial results state
ls /home/ga/UGENE_Data/clinical/results/ 2>/dev/null > /tmp/clinical_variant_annotation_setup_files.txt

# Step 7: Kill existing UGENE
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# Step 8: Launch UGENE
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

if [ "$STARTED" = false ]; then
    pkill -f "ugene" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"
    ELAPSED=0
    while [ $ELAPSED -lt 60 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
            STARTED=true
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
fi

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
    DISPLAY=:1 scrot /tmp/clinical_variant_annotation_start_screenshot.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="
