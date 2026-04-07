#!/bin/bash
echo "=== Setting up implement_text_search task ==="

source /workspace/scripts/task_utils.sh

TASK_DIR="/home/ga/PycharmProjects/search_engine"

# 1. Clean previous run
rm -rf "$TASK_DIR" 2>/dev/null || true
rm -f /tmp/text_search_result.json /tmp/task_start_time /tmp/test_checksums.md5 2>/dev/null || true

# 2. Create Project Structure
mkdir -p "$TASK_DIR/engine"
mkdir -p "$TASK_DIR/tests"
mkdir -p "$TASK_DIR/data"

# 3. Create requirements.txt
cat > "$TASK_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# 4. Generate Data (50 RFC-like abstracts)
cat > "$TASK_DIR/data/generate_corpus.py" << 'PYTHON_EOF'
import json
import random

# Realistic terms for networking documents
terms = ["protocol", "network", "tcp", "udp", "http", "packet", "router", "switch", 
         "security", "authentication", "encryption", "layer", "interface", "address",
         "ipv4", "ipv6", "header", "payload", "connection", "latency", "throughput"]

corpus = []
for i in range(1, 51):
    doc_id = i
    rfc_num = 1000 + i
    # Generate a random abstract
    num_words = random.randint(20, 50)
    words = [random.choice(terms) for _ in range(num_words)]
    # Ensure some specific docs have specific terms for testing
    if i == 1:
        words = ["internet", "protocol", "specifies", "the", "standard"] # RFC 791-ish
        rfc_num = 791
    elif i == 2:
        words = ["transmission", "control", "protocol", "tcp", "reliable"] # RFC 793-ish
        rfc_num = 793
    
    abstract = " ".join(words) + "."
    
    corpus.append({
        "id": doc_id,
        "title": f"RFC {rfc_num} Specification",
        "number": rfc_num,
        "abstract": abstract
    })

with open("corpus.json", "w") as f:
    json.dump(corpus, f, indent=2)
PYTHON_EOF

cd "$TASK_DIR/data" && python3 generate_corpus.py && rm generate_corpus.py

# 5. Create Source Stubs (The Agent's Job)

# engine/__init__.py
touch "$TASK_DIR/engine/__init__.py"

# engine/tokenizer.py
cat > "$TASK_DIR/engine/tokenizer.py" << 'EOF'
from typing import List, Set

STOP_WORDS = {"a", "an", "the", "in", "on", "at", "to", "for", "of", "with", "is", "are", "was", "were"}

def tokenize(text: str) -> List[str]:
    """Split text on non-alphanumeric characters, return list of tokens."""
    raise NotImplementedError("Implement tokenize")

def normalize(tokens: List[str]) -> List[str]:
    """Lowercase all tokens, remove empty strings."""
    raise NotImplementedError("Implement normalize")

def remove_stopwords(tokens: List[str]) -> List[str]:
    """Remove tokens that appear in STOP_WORDS set."""
    raise NotImplementedError("Implement remove_stopwords")
EOF

# engine/indexer.py
cat > "$TASK_DIR/engine/indexer.py" << 'EOF'
from typing import List, Dict, Set
from collections import defaultdict

class InvertedIndex:
    def __init__(self):
        # Maps term -> list of doc_ids
        self.index: Dict[str, List[int]] = defaultdict(list)
        # Maps term -> document frequency
        self.doc_freqs: Dict[str, int] = defaultdict(int)
        # Maps doc_id -> list of tokens (for retrieval/snippets)
        self.documents: Dict[int, List[str]] = {}
        
    def add_document(self, doc_id: int, tokens: List[str]) -> None:
        """Add a processed document to the index."""
        raise NotImplementedError("Implement add_document")

    def get_postings(self, term: str) -> List[int]:
        """Return sorted list of doc_ids containing the term."""
        raise NotImplementedError("Implement get_postings")

    def get_document_frequency(self, term: str) -> int:
        """Return number of documents containing the term."""
        raise NotImplementedError("Implement get_document_frequency")

    def get_total_documents(self) -> int:
        """Return total number of indexed documents."""
        raise NotImplementedError("Implement get_total_documents")
        
    def get_document_tokens(self, doc_id: int) -> List[str]:
        """Return the processed tokens for a document."""
        return self.documents.get(doc_id, [])
EOF

# engine/scorer.py
cat > "$TASK_DIR/engine/scorer.py" << 'EOF'
import math
from typing import List
from engine.indexer import InvertedIndex

def term_frequency(term: str, doc_tokens: List[str]) -> float:
    """Calculate TF: count(term in doc) / len(doc_tokens)."""
    raise NotImplementedError("Implement term_frequency")

def inverse_document_frequency(term: str, index: InvertedIndex) -> float:
    """Calculate IDF: log(N / df). Use natural log (math.log). If df=0, return 0.0."""
    raise NotImplementedError("Implement inverse_document_frequency")

def tfidf_score(term: str, doc_tokens: List[str], index: InvertedIndex) -> float:
    """Calculate TF-IDF: TF * IDF."""
    raise NotImplementedError("Implement tfidf_score")
EOF

# engine/query.py
cat > "$TASK_DIR/engine/query.py" << 'EOF'
from typing import Dict, Set, Any
from engine.indexer import InvertedIndex

def parse_boolean_query(query_str: str) -> Dict[str, Any]:
    """
    Parse a simple boolean query string.
    Supported formats:
    - "term" -> {"op": "TERM", "value": "term"}
    - "term1 AND term2" -> {"op": "AND", "left": "term1", "right": "term2"}
    - "term1 OR term2" -> {"op": "OR", "left": "term1", "right": "term2"}
    - "NOT term" -> {"op": "NOT", "value": "term"}
    Assume single operator per query for simplicity (no nested parens needed).
    """
    raise NotImplementedError("Implement parse_boolean_query")

def evaluate_query(query: Dict[str, Any], index: InvertedIndex) -> Set[int]:
    """
    Evaluate parsed query against index.
    Returns set of matching doc_ids.
    """
    raise NotImplementedError("Implement evaluate_query")
EOF

# engine/searcher.py
cat > "$TASK_DIR/engine/searcher.py" << 'EOF'
import json
from typing import List, Tuple
from engine.tokenizer import tokenize, normalize, remove_stopwords
from engine.indexer import InvertedIndex
from engine.scorer import tfidf_score
from engine.query import parse_boolean_query, evaluate_query

class Searcher:
    def __init__(self, corpus_path: str):
        self.index = InvertedIndex()
        self.load_corpus(corpus_path)
        
    def load_corpus(self, path: str):
        """Load JSON corpus and build index."""
        raise NotImplementedError("Implement load_corpus")
        
    def search(self, query_str: str, top_k: int = 10) -> List[Tuple[int, float]]:
        """
        Ranked retrieval using TF-IDF.
        1. Tokenize/normalize/remove_stopwords from query
        2. Score documents based on sum of TF-IDF for query terms
        3. Return top_k (doc_id, score) pairs sorted by score desc
        """
        raise NotImplementedError("Implement search")
        
    def boolean_search(self, query_str: str) -> List[int]:
        """
        Boolean retrieval.
        1. Parse query
        2. Evaluate
        3. Return sorted list of matching doc_ids
        """
        raise NotImplementedError("Implement boolean_search")
EOF

# 6. Create Test Files (Reference Implementation Logic)

# tests/conftest.py
cat > "$TASK_DIR/tests/conftest.py" << 'EOF'
import pytest
from engine.indexer import InvertedIndex

@pytest.fixture
def empty_index():
    return InvertedIndex()

@pytest.fixture
def populated_index():
    idx = InvertedIndex()
    # Doc 1: "apple banana"
    idx.add_document(1, ["apple", "banana"])
    # Doc 2: "banana cherry"
    idx.add_document(2, ["banana", "cherry"])
    # Doc 3: "apple cherry date"
    idx.add_document(3, ["apple", "cherry", "date"])
    return idx
EOF

# tests/test_tokenizer.py
cat > "$TASK_DIR/tests/test_tokenizer.py" << 'EOF'
from engine.tokenizer import tokenize, normalize, remove_stopwords

def test_tokenize_splits_basic():
    text = "Hello world"
    assert tokenize(text) == ["Hello", "world"]

def test_tokenize_removes_punctuation():
    text = "Hello, world! This-is; a test."
    # Expect simple alphanumeric splitting
    # Implementation might use re.findall(r'\w+', text)
    tokens = tokenize(text)
    assert "Hello" in tokens
    assert "world" in tokens
    assert "," not in tokens

def test_normalize_lowercases():
    tokens = ["Hello", "WORLD", "PyThOn"]
    assert normalize(tokens) == ["hello", "world", "python"]

def test_remove_stopwords():
    tokens = ["the", "quick", "brown", "fox", "is", "a", "dog"]
    # STOP_WORDS includes 'the', 'is', 'a'
    clean = remove_stopwords(tokens)
    assert clean == ["quick", "brown", "fox", "dog"]

def test_full_pipeline():
    text = "The QUICK brown fox."
    tokens = tokenize(text)
    norm = normalize(tokens)
    clean = remove_stopwords(norm)
    assert clean == ["quick", "brown", "fox"]
EOF

# tests/test_indexer.py
cat > "$TASK_DIR/tests/test_indexer.py" << 'EOF'
def test_add_document(empty_index):
    empty_index.add_document(1, ["a", "b"])
    assert empty_index.get_total_documents() == 1
    assert empty_index.get_postings("a") == [1]

def test_postings_multiple_docs(populated_index):
    # 'banana' is in 1 and 2
    assert sorted(populated_index.get_postings("banana")) == [1, 2]
    # 'date' is in 3
    assert populated_index.get_postings("date") == [3]

def test_document_frequency(populated_index):
    assert populated_index.get_document_frequency("banana") == 2
    assert populated_index.get_document_frequency("apple") == 2
    assert populated_index.get_document_frequency("unknown") == 0

def test_get_document_tokens(populated_index):
    assert populated_index.get_document_tokens(1) == ["apple", "banana"]
EOF

# tests/test_scorer.py
cat > "$TASK_DIR/tests/test_scorer.py" << 'EOF'
import math
from engine.scorer import term_frequency, inverse_document_frequency, tfidf_score

def test_tf_basic():
    # term appears 2 times in 4 tokens -> 0.5
    tokens = ["a", "b", "a", "c"]
    assert term_frequency("a", tokens) == 0.5
    assert term_frequency("b", tokens) == 0.25

def test_idf_calculation(populated_index):
    # N=3. 'apple' in 2 docs. IDF = log(3/2)
    expected = math.log(3/2)
    assert abs(inverse_document_frequency("apple", populated_index) - expected) < 0.0001

def test_tfidf_score(populated_index):
    # Doc 1: ["apple", "banana"]. N=3.
    # TF("apple") = 0.5. IDF("apple") = log(1.5).
    expected = 0.5 * math.log(1.5)
    score = tfidf_score("apple", ["apple", "banana"], populated_index)
    assert abs(score - expected) < 0.0001
EOF

# tests/test_query.py
cat > "$TASK_DIR/tests/test_query.py" << 'EOF'
from engine.query import parse_boolean_query, evaluate_query

def test_parse_term():
    q = parse_boolean_query("apple")
    assert q["op"] == "TERM"
    assert q["value"] == "apple"

def test_parse_and():
    q = parse_boolean_query("apple AND banana")
    assert q["op"] == "AND"
    assert q["left"] == "apple"
    assert q["right"] == "banana"

def test_evaluate_and(populated_index):
    # apple(1,3) AND banana(1,2) -> {1}
    q = {"op": "AND", "left": "apple", "right": "banana"}
    assert evaluate_query(q, populated_index) == {1}

def test_evaluate_or(populated_index):
    # banana(1,2) OR date(3) -> {1, 2, 3}
    q = {"op": "OR", "left": "banana", "right": "date"}
    assert evaluate_query(q, populated_index) == {1, 2, 3}
EOF

# tests/test_searcher.py
cat > "$TASK_DIR/tests/test_searcher.py" << 'EOF'
import os
import pytest
from engine.searcher import Searcher

@pytest.fixture
def corpus_path():
    # Use real corpus path relative to this file
    return os.path.join(os.path.dirname(__file__), "../data/corpus.json")

def test_load_corpus(corpus_path):
    s = Searcher(corpus_path)
    # Should have 50 docs
    assert s.index.get_total_documents() == 50

def test_search_ranking(corpus_path):
    s = Searcher(corpus_path)
    # RFC 791 (doc 1) contains "internet", "protocol"
    # Search for "internet protocol"
    results = s.search("internet protocol")
    assert len(results) > 0
    # Top result should be doc 1
    top_doc_id, score = results[0]
    assert top_doc_id == 1
    assert score > 0

def test_boolean_search(corpus_path):
    s = Searcher(corpus_path)
    # RFC 793 (doc 2) contains "transmission", "control"
    results = s.boolean_search("transmission AND control")
    assert 2 in results
EOF

# 7. Record Checksums (Anti-gaming)
md5sum "$TASK_DIR"/tests/*.py > /tmp/test_checksums.md5

# 8. Record Start Time
date +%s > /tmp/task_start_time

# 9. Set permissions
chown -R ga:ga "$TASK_DIR"

# 10. Launch PyCharm with project
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$TASK_DIR' > /tmp/pycharm.log 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 60
sleep 5
focus_pycharm_window
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="