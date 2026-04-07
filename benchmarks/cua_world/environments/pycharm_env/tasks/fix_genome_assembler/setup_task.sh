#!/bin/bash
echo "=== Setting up fix_genome_assembler task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_genome_assembler"
PROJECT_DIR="/home/ga/PycharmProjects/genome_assembler"

# Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create directory structure
su - ga -c "mkdir -p $PROJECT_DIR/assembler $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- 1. Real Data Generation (PhiX174 sample) ---
# We take a 100bp segment of the actual PhiX174 genome (start of sequence)
# and simulate 5 reads with overlaps to allow assembly.
# Genome start: GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA
# Read 1 (0-40):   GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCG
# Read 2 (30-70):                                ACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGAT
# Read 3 (60-100):                                                            TTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA
# (Simplified for the task to ensure clean linear assembly in tests)

cat > "$PROJECT_DIR/data/phix_sample.fasta" << 'FASTAEOF'
>read_1
GAGTTTTATCGCTTCCATGACGCAGAAGTTAACACTTTCG
>read_2
ACTTTCGGATATTTCTGATGAGTCGAAAAATTATCTTGAT
>read_3
TTATCTTGATAAAGCAGGAATTACTACTGCTTGTTTA
FASTAEOF
# Note: read_3 is the last one. If io.py is buggy, it might be dropped.

# --- 2. Create Implementation Files (with Bugs) ---

# assembler/__init__.py
touch "$PROJECT_DIR/assembler/__init__.py"

# assembler/io.py
# BUG 1: Drops the last sequence because yield is only inside the loop
cat > "$PROJECT_DIR/assembler/io.py" << 'PYEOF'
"""Input/Output utilities for FASTA files."""
from typing import Iterator, Tuple

def read_fasta(file_path: str) -> Iterator[Tuple[str, str]]:
    """
    Parse a FASTA file and yield (header, sequence) tuples.
    
    Args:
        file_path: Path to the FASTA file.
    
    Yields:
        Tuple of (header string, sequence string).
    """
    with open(file_path, 'r') as f:
        header = None
        sequence = []
        
        for line in f:
            line = line.strip()
            if not line:
                continue
                
            if line.startswith(">"):
                if header:
                    yield header, "".join(sequence)
                header = line[1:]
                sequence = []
            else:
                sequence.append(line)
        
        # BUG: Missing yield for the last record after loop finishes
        # Correct code should have:
        # if header:
        #     yield header, "".join(sequence)
PYEOF

# assembler/sequence.py
# BUG 2: Returns Complement but NOT Reversed (DNA strands must be antiparallel)
cat > "$PROJECT_DIR/assembler/sequence.py" << 'PYEOF'
"""DNA sequence manipulation utilities."""

def reverse_complement(seq: str) -> str:
    """
    Compute the reverse complement of a DNA sequence.
    
    Args:
        seq: Input DNA string (e.g., "ATCG")
        
    Returns:
        The reverse complement string (e.g., "CGAT")
    """
    complement_map = {
        'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C',
        'a': 't', 't': 'a', 'c': 'g', 'g': 'c',
        'N': 'N', 'n': 'n'
    }
    
    # BUG: This computes the Complement, but forgets to Reverse it.
    # DNA is directional (5'->3'), so the other strand is 3'<-5'.
    # To read it 5'->3', we must reverse the complement.
    # Correct: return "".join(complement_map.get(base, base) for base in seq)[::-1]
    return "".join(complement_map.get(base, base) for base in seq)
PYEOF

# assembler/overlap.py
# BUG 3: Duplicates the overlap region during merge
cat > "$PROJECT_DIR/assembler/overlap.py" << 'PYEOF'
"""Sequence overlap and merging logic."""

def find_overlap(suffix: str, prefix: str, min_length: int = 3) -> int:
    """
    Find the length of the longest suffix of 'suffix' that matches 
    a prefix of 'prefix'.
    
    Returns 0 if no overlap found >= min_length.
    (This function is correct)
    """
    start = 0
    while True:
        start = suffix.find(prefix[:min_length], start)
        if start == -1:
            return 0
        
        # Check if this match extends to the end
        overlap_len = len(suffix) - start
        if suffix[start:] == prefix[:overlap_len]:
            return overlap_len
        
        start += 1

def merge_sequences(seq1: str, seq2: str, overlap_len: int) -> str:
    """
    Merge two sequences given a known overlap length.
    
    Args:
        seq1: First sequence (upstream)
        seq2: Second sequence (downstream)
        overlap_len: Length of the overlapping region
        
    Returns:
        Merged sequence.
    """
    if overlap_len == 0:
        return seq1 + seq2
        
    # BUG: Duplicates the overlapping region.
    # If seq1 ends with "XYZ" and seq2 starts with "XYZ", and overlap is 3,
    # result should be ...XYZ...
    # Currently returns ...XYZXYZ...
    
    # Correct logic: return seq1 + seq2[overlap_len:]
    return seq1 + seq2
PYEOF

# --- 3. Create Test Files ---

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import os

@pytest.fixture
def sample_fasta(tmp_path):
    f = tmp_path / "test.fasta"
    f.write_text(">seq1\nATCG\n>seq2\nGGCC\n>seq3\nAAAA")
    return str(f)
PYEOF

# tests/test_io.py
cat > "$PROJECT_DIR/tests/test_io.py" << 'PYEOF'
import pytest
from assembler.io import read_fasta

def test_read_fasta_count(sample_fasta):
    """Test that all records are read, including the last one."""
    records = list(read_fasta(sample_fasta))
    # If bug exists, count will be 2 instead of 3
    assert len(records) == 3, "Parser failed to read all records (likely dropped the last one)"

def test_read_fasta_content(sample_fasta):
    records = list(read_fasta(sample_fasta))
    if len(records) >= 3:
        assert records[2][0] == "seq3"
        assert records[2][1] == "AAAA"
PYEOF

# tests/test_sequence.py
cat > "$PROJECT_DIR/tests/test_sequence.py" << 'PYEOF'
import pytest
from assembler.sequence import reverse_complement

def test_reverse_complement_simple():
    # Palindrome AT -> RevComp is AT
    # If bug (Complement only), AT -> TA (fail)
    seq = "AT"
    assert reverse_complement(seq) == "AT", "Expected 'AT' (RevComp), got something else"

def test_reverse_complement_general():
    seq = "AAACCC"
    # Complement: TTTGGG
    # Reverse: GGGTTT
    expected = "GGGTTT"
    assert reverse_complement(seq) == expected

def test_reverse_complement_mixed_case():
    assert reverse_complement("Aa") == "tT"
PYEOF

# tests/test_overlap.py
cat > "$PROJECT_DIR/tests/test_overlap.py" << 'PYEOF'
import pytest
from assembler.overlap import merge_sequences

def test_merge_simple_overlap():
    s1 = "ABCDE"
    s2 = "CDEFG"
    # Overlap is CDE (len 3)
    # Result should be ABCDEFG (len 7)
    # Buggy result: ABCDECDEFG (len 10)
    merged = merge_sequences(s1, s2, 3)
    assert merged == "ABCDEFG"
    assert len(merged) == 7

def test_merge_no_overlap():
    s1 = "ABC"
    s2 = "XYZ"
    merged = merge_sequences(s1, s2, 0)
    assert merged == "ABCXYZ"
PYEOF

# --- 4. Create Main Driver Script ---
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
from assembler.io import read_fasta
from assembler.sequence import reverse_complement
from assembler.overlap import find_overlap, merge_sequences
import sys

def assemble(fasta_path):
    print(f"Reading {fasta_path}...")
    reads = list(read_fasta(fasta_path))
    print(f"Loaded {len(reads)} reads.")
    
    if not reads:
        return ""
        
    # Naive greedy assembly for demonstration
    # (Strictly linear for this specific sample data)
    consensus = reads[0][1]
    
    for i in range(1, len(reads)):
        next_seq = reads[i][1]
        
        # Check direct overlap
        ov = find_overlap(consensus, next_seq)
        if ov > 0:
            consensus = merge_sequences(consensus, next_seq, ov)
        else:
            print(f"No overlap found for read {i+1}")
            consensus += next_seq
            
    return consensus

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python main.py <fasta_file>")
        sys.exit(1)
        
    result = assemble(sys.argv[1])
    print("\nConsensus Sequence:")
    print(result)
PYEOF

# Install dependencies
su - ga -c "pip3 install pytest"

# Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh $PROJECT_DIR > /dev/null 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 60

# Maximize
focus_pycharm_window

# Capture initial state
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="