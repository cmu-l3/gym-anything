#!/bin/bash
echo "=== Setting up recombinant_cloning_design task ==="

# 1. Clean previous state
rm -rf /home/ga/UGENE_Data/cloning_design 2>/dev/null || true
mkdir -p /home/ga/UGENE_Data/cloning_design/results

# 2. Record task start time (before data generation, for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Generate data files deterministically using Python
python3 << 'PYEOF'
import random
import os
import sys

random.seed(28)

# ============================================================
# Generate pET-28a(+) expression vector (5369 bp, circular)
# ============================================================

VECTOR_LEN = 5369

# Real pET-28a(+) MCS sequence containing 7 unique restriction sites:
#   BamHI(GGATCC) EcoRI(GAATTC) SacI(GAGCTC) SalI(GTCGAC)
#   HindIII(AAGCTT) NotI(GCGGCCGC) XhoI(CTCGAG)
# 46 bp total, placed at GenBank positions 158..203
MCS_SEQ = "GGATCCGAATTCGAGCTCGTCGACAAGCTTGCGGCCGCACTCGAGT"
MCS_START = 157  # 0-based index (GenBank 1-based = 158)
MCS_END = MCS_START + len(MCS_SEQ)

# Restriction sites that must appear ONLY once (inside MCS)
PROTECTED = ["GGATCC", "GAATTC", "GAGCTC", "GTCGAC", "AAGCTT", "GCGGCCGC", "CTCGAG"]

# Generate random backbone with ~50% GC (typical for E. coli plasmid)
vec = [random.choice("ACGT") for _ in range(VECTOR_LEN)]

# Insert MCS
for i, c in enumerate(MCS_SEQ):
    vec[MCS_START + i] = c

# Remove protected restriction sites from regions outside the MCS
for iteration in range(100):
    seq_str = "".join(vec)
    changed = False
    for site in PROTECTED:
        start_pos = 0
        while True:
            idx = seq_str.find(site, start_pos)
            if idx == -1:
                break
            # Only mutate if this occurrence is outside the MCS
            if idx < MCS_START or idx >= MCS_END:
                mut = idx + len(site) // 2
                old = vec[mut]
                vec[mut] = random.choice([b for b in "ACGT" if b != old])
                seq_str = "".join(vec)
                changed = True
            start_pos = idx + 1
    if not changed:
        break

# Handle circular junction: check if a site spans the origin
for _ in range(10):
    junction = "".join(vec[-10:] + vec[:10])
    changed = False
    for site in PROTECTED:
        idx = junction.find(site)
        if idx is not None and idx != -1:
            # The site spans the origin; mutate a base in the first few positions
            mut_in_junction = idx + len(site) // 2
            if mut_in_junction >= 10:
                real_idx = mut_in_junction - 10
                old = vec[real_idx]
                vec[real_idx] = random.choice([b for b in "ACGT" if b != old])
                changed = True
            else:
                real_idx = VECTOR_LEN - 10 + mut_in_junction
                old = vec[real_idx]
                vec[real_idx] = random.choice([b for b in "ACGT" if b != old])
                changed = True
    if not changed:
        break

vector_seq = "".join(vec)

# Verify each protected site appears exactly once in the vector
for site in PROTECTED:
    count = vector_seq.count(site)
    if count != 1:
        print(f"WARNING: {site} appears {count} times in vector (expected 1)", file=sys.stderr)

# ============================================================
# Generate EPO coding sequence (582 bp, linear)
# Two MCS enzymes (HindIII, SacI) intentionally cut within EPO,
# making them incompatible for cloning. The remaining 5 MCS enzymes
# (BamHI, EcoRI, SalI, NotI, XhoI) do NOT cut in EPO.
# ============================================================

EPO_LEN = 582
epo = [random.choice("ACGT") for _ in range(EPO_LEN)]

# Ensure proper start and stop codons
epo[0:3] = list("ATG")
epo[579:582] = list("TAA")

# Insert HindIII (AAGCTT) at position 201 — makes HindIII incompatible
epo[201:207] = list("AAGCTT")

# Insert SacI (GAGCTC) at position 402 — makes SacI incompatible
epo[402:408] = list("GAGCTC")

# Protected ranges in EPO that must not be mutated
EPO_PROTECTED = [(201, 207), (402, 408)]

def in_protected(pos, ranges):
    return any(s <= pos < e for s, e in ranges)

# Remove compatible enzymes' sites from EPO
# These must NOT appear in EPO so the agent can select them
MUST_REMOVE_FROM_EPO = ["GGATCC", "GAATTC", "GTCGAC", "GCGGCCGC", "CTCGAG"]

for iteration in range(100):
    epo_str = "".join(epo)
    changed = False
    for site in MUST_REMOVE_FROM_EPO:
        start_pos = 0
        while True:
            idx = epo_str.find(site, start_pos)
            if idx == -1:
                break
            # Find a mutable position within this site occurrence
            candidates = [p for p in range(idx, idx + len(site))
                          if not in_protected(p, EPO_PROTECTED) and p < EPO_LEN]
            if candidates:
                mut = candidates[len(candidates) // 2]
                old = epo[mut]
                epo[mut] = random.choice([b for b in "ACGT" if b != old])
                epo_str = "".join(epo)
                changed = True
            start_pos = idx + 1
    if not changed:
        break

epo_seq = "".join(epo)

# Verify EPO restriction site content
assert "AAGCTT" in epo_seq, "HindIII must be in EPO"
assert "GAGCTC" in epo_seq, "SacI must be in EPO"
for site in MUST_REMOVE_FROM_EPO:
    assert site not in epo_seq, f"{site} must not be in EPO"

# ============================================================
# Write GenBank files
# ============================================================

def format_origin(seq):
    """Format DNA sequence in GenBank ORIGIN block style."""
    lines = ["ORIGIN"]
    for i in range(0, len(seq), 60):
        chunk = seq[i:i+60].lower()
        groups = [chunk[j:j+10] for j in range(0, len(chunk), 10)]
        line_num = str(i + 1).rjust(9)
        lines.append(f"{line_num} {' '.join(groups)}")
    lines.append("//")
    return "\n".join(lines)


# --- pET-28a(+) vector GenBank ---
vector_gb_lines = [
    "LOCUS       pET28a_vector           5369 bp    DNA     circular SYN 18-MAR-2026",
    "DEFINITION  pET-28a(+) expression vector for recombinant protein production.",
    "ACCESSION   pET28a_vector",
    "VERSION     pET28a_vector.1",
    "KEYWORDS    expression vector; T7 promoter; kanamycin resistance.",
    "SOURCE      synthetic construct",
    "  ORGANISM  synthetic construct",
    "            other sequences; artificial sequences.",
    "FEATURES             Location/Qualifiers",
    "     source          1..5369",
    '                     /mol_type="other DNA"',
    '                     /organism="synthetic construct"',
    "     promoter        100..120",
    '                     /label="T7_promoter"',
    '                     /note="T7 RNA polymerase promoter"',
    "     protein_bind    121..140",
    '                     /label="lac_operator"',
    '                     /note="lac operator sequence"',
    "     misc_feature    141..157",
    '                     /label="His_tag_N"',
    '                     /note="N-terminal 6xHis tag coding region"',
    "     misc_feature    158..203",
    '                     /label="MCS"',
    '                     /note="multiple cloning site: BamHI-EcoRI-SacI-SalI-HindIII-NotI-XhoI"',
    "     misc_feature    204..225",
    '                     /label="His_tag_C"',
    '                     /note="C-terminal 6xHis tag coding region"',
    "     terminator      260..310",
    '                     /label="T7_terminator"',
    '                     /note="T7 transcription terminator"',
    "     rep_origin      450..900",
    '                     /label="f1_ori"',
    '                     /note="f1 bacteriophage origin of replication"',
    "     CDS             complement(950..1760)",
    '                     /label="KanR"',
    "                     /gene=\"aph(3')-Ia\"",
    '                     /product="aminoglycoside phosphotransferase"',
    '                     /note="kanamycin resistance gene"',
    "     rep_origin      2900..3500",
    '                     /label="pBR322_ori"',
    '                     /note="pBR322 origin of replication"',
    "     CDS             complement(3600..4680)",
    '                     /label="lacI"',
    '                     /gene="lacI"',
    '                     /product="lac repressor"',
    '                     /note="lac repressor gene"',
]

vector_gb = "\n".join(vector_gb_lines) + "\n" + format_origin(vector_seq) + "\n"


# --- EPO insert GenBank ---
epo_gb_lines = [
    "LOCUS       epo_insert               582 bp    DNA     linear   PRI 18-MAR-2026",
    "DEFINITION  Homo sapiens erythropoietin (EPO) coding sequence.",
    "ACCESSION   epo_insert",
    "VERSION     epo_insert.1",
    "KEYWORDS    EPO; erythropoietin; therapeutic protein.",
    "SOURCE      Homo sapiens (human)",
    "  ORGANISM  Homo sapiens",
    "            Eukaryota; Metazoa; Chordata; Mammalia; Primates; Hominidae; Homo.",
    "FEATURES             Location/Qualifiers",
    "     source          1..582",
    '                     /mol_type="mRNA"',
    '                     /organism="Homo sapiens"',
    "     CDS             1..582",
    '                     /gene="EPO"',
    '                     /product="erythropoietin precursor"',
    '                     /protein_id="NP_000790.2"',
    '                     /note="human erythropoietin coding sequence for recombinant expression"',
]

epo_gb = "\n".join(epo_gb_lines) + "\n" + format_origin(epo_seq) + "\n"


# Write output files
OUT_DIR = "/home/ga/UGENE_Data/cloning_design"

with open(os.path.join(OUT_DIR, "pET28a_vector.gb"), "w") as f:
    f.write(vector_gb)

with open(os.path.join(OUT_DIR, "epo_insert.gb"), "w") as f:
    f.write(epo_gb)

# Print verification summary
print(f"Generated vector: {len(vector_seq)} bp (circular)")
print(f"Generated EPO insert: {len(epo_seq)} bp (linear)")
print("MCS enzyme site counts (vector / EPO):")
for name, site in [("BamHI","GGATCC"), ("EcoRI","GAATTC"), ("SacI","GAGCTC"),
                    ("SalI","GTCGAC"), ("HindIII","AAGCTT"), ("NotI","GCGGCCGC"),
                    ("XhoI","CTCGAG")]:
    vc = vector_seq.count(site)
    ec = epo_seq.count(site)
    compat = "COMPATIBLE" if ec == 0 else "INCOMPATIBLE"
    print(f"  {name:>10s}: vec={vc}  epo={ec}  [{compat}]")

PYEOF

# Check that data generation succeeded
if [ ! -s /home/ga/UGENE_Data/cloning_design/pET28a_vector.gb ] || \
   [ ! -s /home/ga/UGENE_Data/cloning_design/epo_insert.gb ]; then
    echo "ERROR: Data generation failed!"
    exit 1
fi

echo "Data files generated successfully:"
ls -la /home/ga/UGENE_Data/cloning_design/*.gb

# 4. Set ownership
chown -R ga:ga /home/ga/UGENE_Data/cloning_design

# 5. Kill existing UGENE instances
pkill -f "ugene" 2>/dev/null || true
sleep 3
pkill -9 -f "ugene" 2>/dev/null || true
sleep 2

# 6. Launch UGENE as the agent user
echo "Launching UGENE..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid /home/ga/launch_ugene.sh &"

# 7. Wait for UGENE window
TIMEOUT=90
ELAPSED=0
STARTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ugene\|UGENE\|Unipro"; then
        echo "UGENE window detected after ${ELAPSED}s"
        STARTED=true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$STARTED" = true ]; then
    sleep 5
    # Dismiss any startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize and focus the window
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ugene\|UGENE\|Unipro" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        sleep 2
    fi

    # Take initial screenshot
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
    echo "Initial screenshot captured."
else
    echo "WARNING: UGENE window not detected. Continuing anyway..."
fi

echo "=== Task setup complete ==="
