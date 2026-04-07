#!/bin/bash
echo "=== Setting up implement_sequence_analysis task ==="

source /workspace/scripts/task_utils.sh

TASK_DIR="/home/ga/PycharmProjects/seq_toolkit"

# 1. Clean previous runs
rm -rf "$TASK_DIR" 2>/dev/null || true
rm -f /tmp/seq_analysis_result.json 2>/dev/null || true

# 2. Create Project Structure
mkdir -p "$TASK_DIR/sequence"
mkdir -p "$TASK_DIR/data"
mkdir -p "$TASK_DIR/tests"

# 3. Write Data File (E. coli lacZ gene fragment for testing)
# We generate a file that corresponds to real biological data structure
cat > "$TASK_DIR/data/ecoli_lacZ.fasta" << 'FASTAEOF'
>U00096.3:c363557-360483 Escherichia coli str. K-12 substr. MG1655, complete genome
ATGACCATGATTACGGATTCACTGGCCGTCGTTTTACAACGTCGTGACTGGGAAAACCCTGGCGTTACCC
AACTTAATCGCCTTGCAGCACATCCCCCTTTCGCCAGCTGGCGTAATAGCGAAGAGGCCCGCACCGATCG
CCCTTCCCAACAGTTGCGCAGCCTGAATGGCGAATGGCGCTTTGCCTGGTTTCCGGCACCAGAAGCGGTG
CCGGAAAGCTGGCTGGAGTGCGATCTTCCTGAGGCCGATACTGTCGTCGTCCCCTCAAACTGGCAGATGC
ACGGTTACGATGCGCCCATCTACACCAACGTGACCTATCCCATTACGGTCAATCCGCCGTTTGTTCCCAC
GGAGAATCCGACGGGTTGTTACTCGCTCACATTTAATGTTGATGAAAGCTGGCTACAGGAAGGCCAGACG
CGAATTATTTTTGATGGCGTTAACTCGGCGTTTCATCTGTGGTGCAACGGGCGCTGGGTCGGTTACGGCC
AGGACAGTCGTTTGCCGTCTGAATTTGACCTGAGCGCATTTTTACGCGCCGGAGAAAACCGCCTCGCGGT
GATGGTGCTGCGCTGGAGTGACGGCAGTTATCTGGAAGATCAGGATATGTGGCGGATGAGCGGCATTTTC
CGTGACGTCTCGTTGCTGCATAAACCGACTACACAAATCAGCGATTTCCATGTTGCCACTCGCTTTAATG
ATGATTTCAGCCGCGCTGTACTGGAGGCTGAAGTTCAGATGTGCGGCGAGTTGCGTGACTACCTACGGGT
AACAGTTTCTTTATGGCAGGGTGAAACGCAGGTCGCCAGCGGCACCGCGCCTTTCGGCGGTGAAATTATC
GATGAGCGTGGTGGTTATGCCGATCGCGTCACACTACGTCTGAACGTCGAAAACCCGAAACTGTGGAGCG
CCGAAATCCCGAATCTCTATCGTGCGGTGGTTGAACTGCACACCGCCGACGGCACGCTGATTGAAGCAGA
AGCCTGCGATGTCGGTTTCCGCGAGGTGCGGATTGAAAATGGTCTGCTGCTGCTGAACGGCAAGCCGTTG
CTGATTCGAGGCGTTAACCGTCACGAGCATCATCCTCTGCATGGTCAGGTCATGGATGAGCAGACGATGG
TGCAGGATATCCTGCTGATGAAGCAGAACAACTTTAACGCCGTGCGCTGTTCGCATTATCCGAACCATCC
GCTGTGGTACACGCTGTGCGACCGCTACGGCCTGTATGTGGTGGATGAAGCCAATATTGAAACCCACGGC
ATGGTGCCAATGAATCGTCTGACCGATGATCCGCGCTGGCTACCGGCGATGAGCGAACGCGTAACGCGAA
TGGTGCAGCGCGATCGTAATCACCCGAGTGTGATCATCTGGTCGCTGGGGAATGAATCAGGCCACGGCGC
TAATCACGACGCGCTGTATCGCTGGATCAAATCTGTCGATCCTTCCCGCCCGGTGCAGTATGAAGGCGGC
GGAGCCGACACCACGGCCACCGATATTATTTGCCCGATGTACGCGCGCGTGGATGAAGACCAGCCCTTCC
CGGCTGTGCCGAAATGGTCCATCAAAAAATGGCTTTCGCTACCTGGAGAGACGCGCCCGCTGATCCTTTG
CGAATACGCCCACGCGATGGGTAACAGTCTTGGCGGTTTCGCTAAATACTGGCAGGCGTTTCGTCAGTAT
CCCCGTTTACAGGGCGGCTTCGTCTGGGACTGGGTGGATCAGTCGCTGATTAAATATGATGAAAACGGCA
ACCCGTGGTCGGCTTACGGCGGTGATTTTGGCGATACGCCGAACGATCGCCAGTTCTGTATGAACGGTCT
GGTCTTTGCCGACCGCACGCCGCATCCAGCGCTGACGGAAGCAAAACACCAGCAGCAGTTTTTCCAGTTC
CGTTTATCCGGGCAAACCATCGAAGTGACCAGCGAATACCTGTTCCGTCATAGCGATAACGAGCTCCTGC
ACTGGATGGTGGCGCTGGATGGTAAGCCGCTGGCAAGCGGTGAAGTGCCTCTGGATGTCGCTCCACAAGG
TAAACAGTTGATTGAACTGCCTGAACTACCGCAGCCGGAGAGCGCCGGGCAACTCTGGCTCACAGTACGC
GTAGTGCAACCGAACGCGACCGCATGGTCAGAAGCCGGGCACATCAGCGCCTGGCAGCAGTGGCGTCTGG
CGGAAAACCTCAGTGTGACGCTCCCCGCCGCGTCCCACGCCATCCCGCATCTGACCACCAGCGAAATGGA
TTTTTGCATCGAGCTGGGTAATAAGCGTTGGCAATTTAACCGCCAGTCAGGCTTTCTTTCACAGATGTGG
ATTGGCGATAAAAAACAACTGCTGACGCCGCTGCGCGATCAGTTCACCCGTGCACCGCTGGATAACGACA
TTGGCGTAAGTGAAGCGACCCGCATTGACCCTAACGCCTGGGTCGAACGCTGGAAGGCGGCGGGCCATTA
CCAGGCCGAAGCAGCGTTGTTGCAGTGCACGGCAGATACACTTGCTGATGCGGTGCTGATTACGACCGCT
CACGCGTGGCAGCATCAGGGGAAAACCTTATTTATCAGCCGGAAAACCTACCGGATTGATGGTAGTGGTC
AAATGGCGATTACCGTTGATGTTGAAGTGGCGAGCGATACACCGCATCCGGCGCGGATTGGCCTGAACTG
CCAGCTGGCGCAGGTAGCAGAGCGGGTAAACTGGCTCGGATTAGGGCCGCAAGAAAACTATCCCGACCGC
CTTACTGCCGCCTGTTTTGACCGCTGGGATCTGCCATTGTCAGACATGTATACCCCGTACGTCTTCCCGA
GCGAAAACGGTCTGCGCTGCGGGACGCGCGAATTGAATTATGGCCCACACCAGTGGCGCGGCGACTTCCA
GTTCAACATCAGCCGCTACAGTCAACAGCAACTGATGGAAACCAGCCATCGCCATCTGCTGCACGCGGAA
GAAGGCACATGGCTGAATATCGACGGTTTCCATATGGGGATTGGTGGCGACGACTCCTGGAGCCCGTCAG
TATCGGCGGAATTCCAGCTGAGCGCCGGTCGCTACCATTACCAGTTGGTCTGGTGTCAAAAATAATAATA
ACCGGGCAGGCCATGTCTGCCCGTATTTCGCGTAAGGAAATCCATTATGTACTATTTAAAAAACACAAAC
TTTTGGATGTTCGGTTTATTCTTTTTCTTTTACTTTTTTATCATGGGAGCCTACTTCCCGTTTTTCCCGA
TTTGGCTACATGACATCAACCATATCAGCAAAAGTGATACGGGTATTATTTTTGCCGCTATTTCTCTGTT
CTCGCTATTATTCCAACCGCTGTTTGGTCTGCTTTCTGACAAACTCGGAACTTGTTTATTGCAGCTTATA
ATGGTTACAAATAAAGCAATAGCATCACAAATTTCACAAATTTAATTAAGGCCGCGGGATCGATCCCGTC
GATTTATTTAATTT
FASTAEOF

# 4. Write Implementation Stubs

# sequence/__init__.py
touch "$TASK_DIR/sequence/__init__.py"

# sequence/basic.py
cat > "$TASK_DIR/sequence/basic.py" << 'PYEOF'
"""Basic DNA sequence operations."""
from typing import List


def gc_content(seq: str) -> float:
    """
    Calculate GC content of a DNA sequence.

    Args:
        seq: DNA sequence string (case-insensitive).

    Returns:
        float: GC percentage as a decimal between 0.0 and 1.0.

    Raises:
        ValueError: If sequence is empty or contains characters other than A, C, G, T.
    """
    raise NotImplementedError("TODO: implement gc_content")


def reverse_complement(seq: str) -> str:
    """
    Return the reverse complement of a DNA sequence.

    Converts A<->T and C<->G, then reverses the string.
    Output must be uppercase.

    Args:
        seq: DNA sequence string.

    Returns:
        str: Reverse complement sequence.

    Raises:
        ValueError: If sequence contains invalid characters.
    """
    raise NotImplementedError("TODO: implement reverse_complement")


def transcribe(seq: str) -> str:
    """
    Transcribe DNA to RNA.

    Replaces all occurrences of T with U.
    Output must be uppercase.

    Args:
        seq: DNA sequence string.

    Returns:
        str: RNA sequence.

    Raises:
        ValueError: If sequence contains invalid characters.
    """
    raise NotImplementedError("TODO: implement transcribe")


def find_motifs(seq: str, motif: str) -> List[int]:
    """
    Find all starting positions of a motif in a sequence.

    Args:
        seq: DNA sequence to search.
        motif: Substring to find.

    Returns:
        List[int]: Sorted list of 1-based start positions.
                   Overlapping matches should be included.
                   Returns empty list if no match found.
    """
    raise NotImplementedError("TODO: implement find_motifs")
PYEOF

# sequence/translation.py
cat > "$TASK_DIR/sequence/translation.py" << 'PYEOF'
"""Translation and ORF finding."""
from typing import List, Tuple

CODON_TABLE = {
    'ATA': 'I', 'ATC': 'I', 'ATT': 'I', 'ATG': 'M',
    'ACA': 'T', 'ACC': 'T', 'ACG': 'T', 'ACT': 'T',
    'AAC': 'N', 'AAT': 'N', 'AAA': 'K', 'AAG': 'K',
    'AGC': 'S', 'AGT': 'S', 'AGA': 'R', 'AGG': 'R',
    'CTA': 'L', 'CTC': 'L', 'CTG': 'L', 'CTT': 'L',
    'CCA': 'P', 'CCC': 'P', 'CCG': 'P', 'CCT': 'P',
    'CAC': 'H', 'CAT': 'H', 'CAA': 'Q', 'CAG': 'Q',
    'CGA': 'R', 'CGC': 'R', 'CGG': 'R', 'CGT': 'R',
    'GTA': 'V', 'GTC': 'V', 'GTG': 'V', 'GTT': 'V',
    'GCA': 'A', 'GCC': 'A', 'GCG': 'A', 'GCT': 'A',
    'GAC': 'D', 'GAT': 'D', 'GAA': 'E', 'GAG': 'E',
    'GGA': 'G', 'GGC': 'G', 'GGG': 'G', 'GGT': 'G',
    'TCA': 'S', 'TCC': 'S', 'TCG': 'S', 'TCT': 'S',
    'TTC': 'F', 'TTT': 'F', 'TTA': 'L', 'TTG': 'L',
    'TAC': 'Y', 'TAT': 'Y', 'TAA': '*', 'TAG': '*',
    'TGC': 'C', 'TGT': 'C', 'TGA': '*', 'TGG': 'W',
}

# RNA codon table derived from DNA table by replacing T with U
RNA_CODON_TABLE = {k.replace('T', 'U'): v for k, v in CODON_TABLE.items()}


def translate(rna: str) -> str:
    """
    Translate RNA sequence to protein string.

    Uses standard genetic code. Translation starts at position 0.
    Stops at the first stop codon (*). The stop codon is NOT included in output.
    If length is not a multiple of 3, trailing bases are ignored.

    Args:
        rna: RNA sequence string.

    Returns:
        str: Protein sequence (single-letter amino acid codes).

    Raises:
        ValueError: If sequence contains characters other than A, C, G, U.
    """
    raise NotImplementedError("TODO: implement translate")


def find_orfs(seq: str, min_length: int = 100) -> List[Tuple[int, int, str]]:
    """
    Find Open Reading Frames (ORFs) in a DNA sequence.

    Searches all 6 reading frames (3 forward, 3 reverse complement).
    An ORF starts with ATG and ends with a stop codon (TAA, TAG, TGA).

    Args:
        seq: DNA sequence string.
        min_length: Minimum length of the ORF in nucleotides (start to stop inclusive).

    Returns:
        List[Tuple[int, int, str]]: List of (start, end, strand) tuples.
            start: 1-based start position (inclusive).
            end: 1-based end position (inclusive, includes stop codon).
            strand: '+' or '-'.
            
            Note: For '-' strand, start < end relative to the FORWARD sequence.
            (e.g. if ORF is on reverse complement from index 0 to 100,
             coordinates should be mapped back to forward strand indices).
    """
    raise NotImplementedError("TODO: implement find_orfs")
PYEOF

# sequence/analysis.py
cat > "$TASK_DIR/sequence/analysis.py" << 'PYEOF'
"""Sequence analysis tools."""
from typing import Dict, List


def melting_temperature(seq: str) -> float:
    """
    Calculate melting temperature (Tm) of a DNA oligo.

    Formulas:
    - Length <= 13: Tm = 2 * (A+T) + 4 * (G+C) (Wallace rule)
    - Length > 13:  Tm = 64.9 + 41 * (G+C - 16.4) / length

    Args:
        seq: DNA sequence string.

    Returns:
        float: Tm in Celsius, rounded to 1 decimal place.

    Raises:
        ValueError: If sequence is empty or invalid.
    """
    raise NotImplementedError("TODO: implement melting_temperature")


def restriction_sites(seq: str, enzyme_sites: Dict[str, str]) -> Dict[str, List[int]]:
    """
    Find restriction enzyme cut sites.

    Args:
        seq: DNA sequence.
        enzyme_sites: Dictionary mapping enzyme name to recognition sequence.
                      e.g., {'EcoRI': 'GAATTC'}

    Returns:
        Dict[str, List[int]]: Map of enzyme name to sorted list of 1-based start positions.
    """
    raise NotImplementedError("TODO: implement restriction_sites")


def codon_frequency(seq: str) -> Dict[str, float]:
    """
    Calculate codon frequency for a coding sequence.

    Reads sequence in triplets from the beginning.
    Ignores trailing bases if not divisible by 3.

    Args:
        seq: DNA sequence.

    Returns:
        Dict[str, float]: Dictionary mapping codon (e.g. 'ATG') to relative frequency
                          (count / total_codons).
    
    Raises:
        ValueError: If sequence length < 3.
    """
    raise NotImplementedError("TODO: implement codon_frequency")
PYEOF

# 5. Write Tests

mkdir -p "$TASK_DIR/tests"
touch "$TASK_DIR/tests/__init__.py"

cat > "$TASK_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import os

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data')
FASTA_PATH = os.path.join(DATA_DIR, 'ecoli_lacZ.fasta')

@pytest.fixture
def sample_dna_short():
    return "AGCTATAG"

@pytest.fixture
def sample_dna_long():
    # A fragment of lacZ for consistent testing
    return "ATGACCATGATTACGGATTCACTGGCCGTCGTTTTACAACGTCGTGACTGGGAAAACCCTGGCGTTACCCAACTTAATCGCCTTGCAGCACATCCCCCTTTCGCCAGCTGGCGTAATAGCGAAGAGGCCCGCACCGATCGCCCTTCCCAACAGTTGCGCAGCCTGAATGGCGAATGGCGCTTTGCCTGGTTTCCGG"

@pytest.fixture
def lacz_sequence():
    """Reads the full gene from the fasta file, stripping header and newlines."""
    with open(FASTA_PATH, 'r') as f:
        lines = f.readlines()
    # Skip header (>...) and join the rest
    seq = "".join(line.strip() for line in lines if not line.startswith(">"))
    return seq
PYEOF

cat > "$TASK_DIR/tests/test_basic.py" << 'PYEOF'
import pytest
from sequence.basic import gc_content, reverse_complement, transcribe, find_motifs

def test_gc_content_simple():
    # 50% GC
    assert gc_content("GCAT") == 0.5
    # 0% GC
    assert gc_content("ATAT") == 0.0
    # 100% GC
    assert gc_content("GCGC") == 1.0

def test_gc_content_case_insensitive():
    assert gc_content("gcgc") == 1.0
    assert gc_content("GcAt") == 0.5

def test_gc_content_invalid():
    with pytest.raises(ValueError):
        gc_content("AGCX")
    with pytest.raises(ValueError):
        gc_content("")

def test_reverse_complement_simple():
    # A->T, T->A, C->G, G->C, then reverse
    assert reverse_complement("AAAACCCG") == "CGGGTTTT"

def test_reverse_complement_palindrome():
    # EcoRI site is palindromic
    assert reverse_complement("GAATTC") == "GAATTC"

def test_reverse_complement_invalid():
    with pytest.raises(ValueError):
        reverse_complement("AGCX")

def test_transcribe_simple():
    # T -> U
    assert transcribe("AAATTTCCCGGG") == "AAAUUUCCCGGG"

def test_transcribe_invalid():
    with pytest.raises(ValueError):
        transcribe("AGCU") # U is not valid in DNA input here based on spec

def test_transcribe_empty():
    assert transcribe("") == ""

def test_find_motifs_simple():
    seq = "GATATATGCATATACTT"
    motif = "ATATA"
    # Matches at index 1 (G[ATATA]T...) and index 3 (GAT[ATATA]CTT)
    # 1-based indices: 2 and 4
    assert find_motifs(seq, motif) == [2, 4]

def test_find_motifs_none():
    assert find_motifs("AGCT", "ZZ") == []

def test_find_motifs_case_insensitive():
    assert find_motifs("AgCt", "gc") == [2]
PYEOF

cat > "$TASK_DIR/tests/test_translation.py" << 'PYEOF'
import pytest
from sequence.translation import translate, find_orfs

def test_translate_simple():
    # AUG -> M, UUU -> F, UAA -> Stop
    assert translate("AUGUUUUAA") == "MF"

def test_translate_partial():
    # Ignore trailing bases
    assert translate("AUGUUUUAAAG") == "MF"

def test_translate_no_stop():
    assert translate("AUGUUU") == "MF"

def test_translate_invalid():
    with pytest.raises(ValueError):
        translate("ATG") # DNA passed instead of RNA

def test_find_orfs_short(sample_dna_long):
    # The sample starts with ATGACCATG... (Met-Thr-Met...)
    # We need to set a small min_length to find something in this fragment
    orfs = find_orfs(sample_dna_long, min_length=30)
    # Check that we found at least one
    assert len(orfs) > 0
    # Check structure
    for start, end, strand in orfs:
        assert isinstance(start, int)
        assert isinstance(end, int)
        assert strand in ['+', '-']
        assert end > start

def test_find_orfs_lacz(lacz_sequence):
    # The real LacZ gene is a large ORF.
    # It starts at 1 and ends at 3075 (inclusive) on the + strand of this file
    # (since the file is the coding sequence).
    orfs = find_orfs(lacz_sequence, min_length=1000)
    
    found = False
    for start, end, strand in orfs:
        if start == 1 and end == 3075 and strand == '+':
            found = True
            break
    assert found, "Did not find full LacZ ORF (1-3075)"

def test_find_orfs_reverse():
    # Create a sequence with an ORF on the reverse strand
    # Forward: TTT TTA CAT ... (Reverse: ... ATG TAA AAA)
    seq = "TTTTTACAT" 
    # RevComp: ATGTAAAAA -> Met-Stop
    # Length 9. 
    orfs = find_orfs(seq, min_length=6)
    # Should find one on '-' strand
    # Coordinates on forward strand: start is index 1 (T), end is index 9 (T)
    # 1-based.
    # Rev comp of "TTTTTACAT" is "ATGTAAAAA".
    # ORF is whole thing.
    # So on forward strand, it covers 1 to 9.
    found = any(o == (1, 9, '-') for o in orfs)
    assert found

def test_find_orfs_min_length():
    seq = "ATGAAATAA" # 9 bases
    assert len(find_orfs(seq, min_length=10)) == 0
    assert len(find_orfs(seq, min_length=9)) == 1
PYEOF

cat > "$TASK_DIR/tests/test_analysis.py" << 'PYEOF'
import pytest
from sequence.analysis import melting_temperature, restriction_sites, codon_frequency

def test_melting_temperature_short():
    # Wallace rule: 2(A+T) + 4(G+C)
    # "AAAA" -> 2*4 = 8
    assert melting_temperature("AAAA") == 8.0
    # "GCGC" -> 4*4 = 16
    assert melting_temperature("GCGC") == 16.0

def test_melting_temperature_long():
    # Formula: 64.9 + 41 * (G+C - 16.4) / length
    # Seq: 20 bases, 10 GC.
    # Tm = 64.9 + 41 * (10 - 16.4) / 20
    # Tm = 64.9 + 41 * (-6.4) / 20
    # Tm = 64.9 + (-262.4) / 20
    # Tm = 64.9 - 13.12 = 51.78 -> 51.8
    seq = "GCTAGCTAGCAAAAAATTTT" # 10 GC, 10 AT
    assert len(seq) == 20
    # Count GC: G(2)+C(2)+G(2)+C(2) + ... wait
    # GCTAGCTAGC = 2 G, 2 C, 2 G, 2 C = 8 GC?
    # Let's use a simpler one.
    # 20 bases all G. 
    # Tm = 64.9 + 41 * (20 - 16.4) / 20
    # Tm = 64.9 + 41 * 3.6 / 20 = 64.9 + 7.38 = 72.28 -> 72.3
    seq_all_g = "G" * 20
    assert melting_temperature(seq_all_g) == 72.3

def test_restriction_sites_ecori():
    seq = "AAAGAATTCAAA"
    # EcoRI: GAATTC
    # Match at index 4 (1-based)
    sites = restriction_sites(seq, {"EcoRI": "GAATTC"})
    assert sites["EcoRI"] == [4]

def test_restriction_sites_multiple():
    seq = "GAATTC...GGATCC"
    enzymes = {"EcoRI": "GAATTC", "BamHI": "GGATCC"}
    sites = restriction_sites(seq, enzymes)
    assert sites["EcoRI"] == [1]
    assert sites["BamHI"] == [10] # 1(G)2(A)3(A)4(T)5(T)6(C)7(.)8(.)9(.)10(G)

def test_codon_frequency_simple():
    # ATG ATG TAA
    seq = "ATGATGTAA"
    freqs = codon_frequency(seq)
    assert freqs["ATG"] == 2/3
    assert freqs["TAA"] == 1/3
    assert abs(sum(freqs.values()) - 1.0) < 0.0001

def test_codon_frequency_error():
    with pytest.raises(ValueError):
        codon_frequency("AT")
PYEOF

# 6. Create requirements.txt
cat > "$TASK_DIR/requirements.txt" << 'REQEOF'
pytest>=7.0
pytest-cov>=4.0
REQEOF

# 7. Record checksums of test files (anti-gaming)
md5sum "$TASK_DIR/tests/"*.py > /tmp/tests_checksum.md5

# 8. Set up timestamp
date +%s > /tmp/task_start_time.txt

# 9. Launch PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$TASK_DIR' > /tmp/pycharm.log 2>&1 &"

# 10. Wait and setup window
sleep 15
wait_for_pycharm 120
focus_pycharm_window
dismiss_dialogs 5

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="