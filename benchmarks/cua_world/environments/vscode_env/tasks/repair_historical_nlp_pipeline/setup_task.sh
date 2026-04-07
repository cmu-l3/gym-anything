#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Historical NLP Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/historical_nlp"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p data pipeline tests output .vscode

# ─────────────────────────────────────────────────────────────
# Create dummy data
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/raw_gutenberg_excerpt.txt" << 'EOF'
Chapter 1
It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.
However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well-
fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.

Mr. Darcy was a well-
known figure in the county. The beautiful façade of his estate was striking&#x2014;truly magnificent to behold.
"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"
EOF
chown ga:ga "$WORKSPACE_DIR/data/raw_gutenberg_excerpt.txt"

# ─────────────────────────────────────────────────────────────
# Buggy Python Modules
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/pipeline/normalizer.py" << 'EOF'
import re
import html
import unicodedata

def clean_text(text):
    """Clean the raw text but preserve important characters."""
    # BUG 1: Destroys diacritics (e.g., façade -> faade)
    text = text.encode('ascii', 'ignore').decode('ascii')
    return text

def unescape_entities(text):
    """Convert HTML entities back to characters."""
    # BUG 2: Regex misses hex entities like &#x2014; and numeric entities
    return re.sub(r'&([a-zA-Z]+);', lambda m: html.unescape(m.group(0)), text)
EOF

cat > "$WORKSPACE_DIR/pipeline/cleaner.py" << 'EOF'
import re

def remove_line_wrap_hyphens(text):
    """Remove hyphens that occur due to line wrapping, joining the words."""
    # BUG 3: Indiscriminately removes hyphens followed by space, breaking "well-known"
    return re.sub(r'-\s+', '', text)
EOF

cat > "$WORKSPACE_DIR/pipeline/sentence_splitter.py" << 'EOF'
import re

def split_sentences(text):
    """Split text into sentences."""
    # BUG 4: Splits on abbreviations like Mr. and Mrs.
    # A negative lookbehind is missing for common honorifics.
    sentences = re.split(r'(?<=[.!?])\s+(?=[A-Z"\'”])', text)
    return [s.strip() for s in sentences if s.strip()]
EOF

cat > "$WORKSPACE_DIR/pipeline/bpe_tokenizer.py" << 'EOF'
def apply_bpe_merges(tokens, merge_rules):
    """
    Apply BPE merges to a list of tokens based on learned merge rules.
    merge_rules is a dict of {('token1', 'token2'): frequency_score}
    Higher frequency scores should be merged first.
    """
    # BUG 5: Sorting by token pair (alphabetical) instead of frequency score (x[1])
    sorted_merges = sorted(merge_rules.items(), key=lambda x: x[0], reverse=True)
    
    for (pair, _) in sorted_merges:
        i = 0
        while i < len(tokens) - 1:
            if tokens[i] == pair[0] and tokens[i+1] == pair[1]:
                tokens[i] = tokens[i] + tokens[i+1]
                del tokens[i+1]
            else:
                i += 1
    return tokens
EOF

cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
import json
import sys
from pipeline.normalizer import clean_text, unescape_entities
from pipeline.cleaner import remove_line_wrap_hyphens
from pipeline.sentence_splitter import split_sentences

def main():
    if len(sys.argv) < 3:
        print("Usage: python run_pipeline.py <input> <output>")
        return
        
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        text = f.read()
        
    text = unescape_entities(text)
    text = clean_text(text)
    text = remove_line_wrap_hyphens(text)
    sentences = split_sentences(text)
    
    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        for s in sentences:
            f.write(json.dumps({"text": s}) + "\n")

if __name__ == "__main__":
    main()
EOF

# ─────────────────────────────────────────────────────────────
# Test Suite
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_normalizer.py" << 'EOF'
from pipeline.normalizer import clean_text, unescape_entities

def test_diacritics_preserved():
    text = "The beautiful façade"
    cleaned = clean_text(text)
    assert "façade" in cleaned, f"Diacritics were destroyed: {cleaned}"

def test_hex_entities_unescaped():
    text = "striking&#x2014;truly"
    unescaped = unescape_entities(text)
    assert "striking—truly" in unescaped, f"Hex entity not unescaped: {unescaped}"
EOF

cat > "$WORKSPACE_DIR/tests/test_cleaner.py" << 'EOF'
from pipeline.cleaner import remove_line_wrap_hyphens

def test_line_wrap_hyphens_removed():
    text = "a well-\nknown figure"
    cleaned = remove_line_wrap_hyphens(text)
    assert "well-known" in cleaned, "Line wrap hyphen not correctly removed"

def test_standard_hyphens_preserved():
    text = "a well-known figure"
    cleaned = remove_line_wrap_hyphens(text)
    assert "well-known" in cleaned, "Standard hyphen was incorrectly removed"
EOF

cat > "$WORKSPACE_DIR/tests/test_sentence_splitter.py" << 'EOF'
from pipeline.sentence_splitter import split_sentences

def test_sentence_splitter_abbreviations():
    text = "Mr. Darcy walked in. He looked around."
    sentences = split_sentences(text)
    assert len(sentences) == 2, f"Expected 2 sentences, got {len(sentences)}"
    assert "Mr. Darcy walked in." in sentences[0], "Split incorrectly on Mr."
EOF

cat > "$WORKSPACE_DIR/tests/test_bpe_tokenizer.py" << 'EOF'
from pipeline.bpe_tokenizer import apply_bpe_merges

def test_bpe_merges_priority():
    tokens = ['e', 's', 't', 'a', 't', 'e']
    # 'e', 's' has score 10. 's', 't' has score 100.
    # 's', 't' should merge first to 'st'.
    merge_rules = {
        ('e', 's'): 10,
        ('s', 't'): 100
    }
    result = apply_bpe_merges(tokens, merge_rules)
    assert 'st' in result, "Merges were not applied in order of frequency score"
    assert 'es' not in result, "Lower priority merge applied first"
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# Record initial test hash to prevent gaming
# ─────────────────────────────────────────────────────────────
find "$WORKSPACE_DIR/tests" -type f -exec md5sum {} + | sort | md5sum | awk '{print $1}' > /tmp/initial_tests_hash.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start VSCode
echo "Starting VS Code..."
sudo -u ga DISPLAY=:1 code --new-window "$WORKSPACE_DIR" > /tmp/vscode.log 2>&1 &
sleep 5

# Focus and maximize
focus_vscode_window 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="