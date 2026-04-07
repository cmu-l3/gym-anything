#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Genomic QC Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/genomic_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

cd "$WORKSPACE_DIR"

# ──────────────────────────────────────────────────────────
# 1. Generate sample FASTQ data
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/sample_reads.fastq" << 'EOF'
@SEQ_ID_1_GOOD
GATCGGAAGAGCACACGTCTGAACTCCAGTCAC
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
@SEQ_ID_2_LOWERCASE
gatcggaagagcacacgtctgaactccagtcac
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
@SEQ_ID_3_LOW_QUAL_TAIL
ATGCGTACGTAGCTAGCTAGCTAGCTAGCTAGC
+
IIIIIIIIIIIIIIIIIIIIIIIIII!''*((((
@SEQ_ID_4_WITH_N
ATGNCCGTACGT
+
IIIIIIIIIIII
EOF

# ──────────────────────────────────────────────────────────
# 2. src/fastq_parser.py (BUG 1: Phred+64 instead of Phred+33)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/fastq_parser.py" << 'EOF'
def parse_qualities(qual_string):
    """
    Convert ASCII quality string to Phred scores.
    """
    # BUG: Assumes old Illumina Phred+64 encoding instead of standard Phred+33
    return [ord(char) - 64 for char in qual_string]

def read_fastq(filepath):
    """Simple FASTQ reader yielding (id, seq, qual)."""
    with open(filepath, 'r') as f:
        while True:
            header = f.readline().strip()
            if not header:
                break
            seq = f.readline().strip()
            f.readline() # '+'
            qual = f.readline().strip()
            yield header, seq, qual
EOF

# ──────────────────────────────────────────────────────────
# 3. src/sequence_utils.py (BUG 2: RevComp & BUG 3: GC Content)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/sequence_utils.py" << 'EOF'
def reverse_complement(seq):
    """
    Return the reverse complement of a DNA sequence.
    (A <-> T, C <-> G)
    """
    # BUG: Only reverses the sequence, does not complement!
    return seq[::-1]

def calculate_gc(seq):
    """
    Calculate GC content percentage of a sequence.
    """
    if not seq:
        return 0.0
        
    # BUG: Case sensitive, ignores 'g' and 'c'
    gc_count = seq.count('G') + seq.count('C')
    
    return (gc_count / len(seq)) * 100
EOF

# ──────────────────────────────────────────────────────────
# 4. src/translator.py (BUG 4: 'N' Handling truncates)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/translator.py" << 'EOF'
CODON_TABLE = {
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

def translate(seq):
    """
    Translate a DNA sequence to an amino acid sequence.
    Unknown codons containing 'N' should be translated to 'X'.
    """
    protein = []
    for i in range(0, len(seq) - 2, 3):
        codon = seq[i:i+3].upper()
        
        if 'N' in codon:
            # BUG: Stops translation when 'N' is encountered.
            # Should append 'X' to the protein and continue.
            break
            
        protein.append(CODON_TABLE.get(codon, '?'))
        
    return "".join(protein)
EOF

# ──────────────────────────────────────────────────────────
# 5. src/trimmer.py (BUG 5: 3' Quality Slicing)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/trimmer.py" << 'EOF'
def trim_low_quality(seq, qualities, threshold=20):
    """
    Trim 3' end of sequence when quality drops below threshold.
    Returns (trimmed_seq, trimmed_qualities).
    """
    for i, q in enumerate(qualities):
        if q < threshold:
            # BUG: Keeps the low quality tail instead of the high quality start!
            return seq[i:], qualities[i:]
            
    return seq, qualities
EOF

# ──────────────────────────────────────────────────────────
# 6. run_pipeline.py (Entry point)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
import sys
import json
from src.fastq_parser import read_fastq, parse_qualities
from src.sequence_utils import reverse_complement, calculate_gc
from src.translator import translate
from src.trimmer import trim_low_quality

def process_file(filepath):
    results = []
    for header, seq, qual_str in read_fastq(filepath):
        quals = parse_qualities(qual_str)
        trimmed_seq, trimmed_quals = trim_low_quality(seq, quals, threshold=20)
        
        record = {
            "id": header,
            "original_length": len(seq),
            "trimmed_length": len(trimmed_seq),
            "gc_content": round(calculate_gc(trimmed_seq), 2),
            "protein": translate(trimmed_seq),
            "rev_comp": reverse_complement(trimmed_seq)
        }
        results.append(record)
        
    return results

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python run_pipeline.py <fastq_file>")
        sys.exit(1)
        
    data = process_file(sys.argv[1])
    print(json.dumps(data, indent=2))
EOF

# ──────────────────────────────────────────────────────────
# 7. tests/test_pipeline.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import pytest
from src.fastq_parser import parse_qualities
from src.sequence_utils import reverse_complement, calculate_gc
from src.translator import translate
from src.trimmer import trim_low_quality

def test_parse_qualities():
    # Phred+33: 'I' is 73 in ASCII. 73 - 33 = 40.
    assert parse_qualities("I") == [40]
    # '!' is 33 in ASCII. 33 - 33 = 0.
    assert parse_qualities("!") == [0]

def test_reverse_complement():
    assert reverse_complement("ATGC") == "GCAT"
    assert reverse_complement("A") == "T"
    assert reverse_complement("C") == "G"

def test_calculate_gc():
    assert calculate_gc("GCGC") == 100.0
    assert calculate_gc("ATAT") == 0.0
    assert calculate_gc("gcgc") == 100.0  # Should be case-insensitive
    assert calculate_gc("Gattaca") == 14.285714285714285

def test_translate_with_n():
    # ATG (M), NCC (X), GTA (V)
    assert translate("ATGNCCGTA") == "MXV"
    assert translate("NNN") == "X"

def test_trim_low_quality():
    seq = "ATGCGTACGTAGCTAG"
    # Qualities: all 40s (good), then one 10 (bad), then 5s (bad)
    quals = [40] * 10 + [10] + [5] * 5
    trimmed_seq, trimmed_quals = trim_low_quality(seq, quals, threshold=20)
    
    assert len(trimmed_seq) == 10
    assert trimmed_seq == "ATGCGTACGT"
EOF

# Install pytest for the workspace
sudo -u ga pip3 install pytest --quiet

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

echo "=== Task Setup Complete ==="