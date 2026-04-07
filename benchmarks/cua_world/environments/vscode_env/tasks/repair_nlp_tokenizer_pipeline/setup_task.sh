#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair NLP Tokenizer Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/tokenizer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tokenizer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ──────────────────────────────────────────────
# 1. tokenizer/pre_tokenizers.py (BUGS 1 & 2)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tokenizer/pre_tokenizers.py" << 'EOF'
import re

def pre_tokenize(text):
    """
    Splits input text into a list of words or tokens.
    """
    # BUG 1: text.strip().split() permanently destroys whitespace characters
    # BUG 2: \w+ groups all CJK characters together into massive tokens
    words = text.strip().split()
    tokens = []
    for w in words:
        # Group alphanumeric characters together, split punctuation
        tokens.extend(re.findall(r'\w+|[^\w\s]+', w))
    return tokens
EOF

# ──────────────────────────────────────────────
# 2. tokenizer/bpe_builder.py (BUGS 3 & 4)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tokenizer/bpe_builder.py" << 'EOF'
import re

def get_stats(splits, word_counts):
    pairs = {}
    for word, freq in word_counts.items():
        split = splits[word]
        if len(split) == 1:
            continue
        for i in range(len(split) - 1):
            pair = (split[i], split[i+1])
            pairs[pair] = pairs.get(pair, 0) + freq
    return pairs

def merge_vocab(pair, splits):
    new_splits = {}
    
    # BUG 4: pair strings are not escaped, causing regex metacharacter injection
    pattern = r'(?<!\S)' + pair[0] + ' ' + pair[1] + r'(?!\S)'
    replacement = pair[0] + pair[1]
    
    for word, split in splits.items():
        split_str = ' '.join(split)
        new_split_str = re.sub(pattern, replacement, split_str)
        new_splits[word] = new_split_str.split(' ')
    return new_splits

def build_bpe(word_counts, num_merges):
    splits = {w: [c for c in w] for w in word_counts}
    
    for i in range(num_merges):
        pair_counts = get_stats(splits, word_counts)
        if not pair_counts:
            break
            
        # BUG 3: Sub-optimal merge. Selects the first pair in the dict instead of the most frequent.
        best_pair = list(pair_counts.keys())[0]
        
        splits = merge_vocab(best_pair, splits)
        
    return splits
EOF

# ──────────────────────────────────────────────
# 3. tokenizer/decoder.py (BUG 5)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tokenizer/decoder.py" << 'EOF'
def decode_utf8_bytes(byte_list):
    """
    Converts a sequence of byte integers into a string.
    Must handle arbitrary byte sequences safely without crashing.
    """
    byte_array = bytearray(byte_list)
    # BUG 5: Does not gracefully handle invalid/partial UTF-8 sequences
    return byte_array.decode('utf-8')
EOF

# ──────────────────────────────────────────────
# 4. tests/test_tokenizer.py (Provided tests)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_tokenizer.py" << 'EOF'
import pytest
from tokenizer.pre_tokenizers import pre_tokenize
from tokenizer.bpe_builder import get_stats, merge_vocab, build_bpe
from tokenizer.decoder import decode_utf8_bytes

def test_whitespace_preserved():
    text = "def foo():\n    pass"
    tokens = pre_tokenize(text)
    assert any("\n" in t or " " in t for t in tokens), "Whitespace was permanently lost"

def test_cjk_not_grouped():
    text = "こんにちは世界"
    tokens = pre_tokenize(text)
    assert len(tokens) > 1, "CJK characters were incorrectly grouped into a single monolithic token"

def test_optimal_bpe_merge():
    word_counts = {"a b c": 1, "x y z": 1, "a b d": 100}
    splits = {w: w.split() for w in word_counts}
    pair_counts = get_stats(splits, word_counts)
    
    # Mocking the loop behavior to test correct pair extraction
    # The most frequent pair here should be ('a', 'b') with 101 occurrences
    best_pair = max(pair_counts, key=pair_counts.get)
    assert best_pair == ('a', 'b'), "BPE merge did not select the most frequent pair"

def test_regex_escaping():
    splits = {"hello . . world": ["hello", ".", ".", "world"]}
    pair = (".", ".")
    new_splits = merge_vocab(pair, splits)
    assert ".." in new_splits["hello . . world"], "Regex metacharacters were not escaped safely"

def test_emoji_byte_slice():
    try:
        # First 2 bytes of a 4-byte emoji sequence (invalid stand-alone UTF-8)
        result = decode_utf8_bytes([240, 159])
    except UnicodeDecodeError:
        pytest.fail("decode_utf8_bytes crashed with UnicodeDecodeError. Should handle safely.")
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Focus VS Code window if running
focus_vscode_window 2>/dev/null || true
sleep 1

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="