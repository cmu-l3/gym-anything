#!/bin/bash
set -e
echo "=== Setting up fix_recommender_system task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/recommender_system"

# Clean up previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/recommender_result.json 2>/dev/null || true

# Create project structure
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/engine"
mkdir -p "$PROJECT_DIR/tests"

# --- 1. Create Data (Small realistic subset) ---
cat > "$PROJECT_DIR/data/movies.csv" << 'CSV'
movie_id,title,genres
1,Toy Story (1995),Adventure|Animation|Children|Comedy|Fantasy
2,Jumanji (1995),Adventure|Children|Fantasy
3,Grumpier Old Men (1995),Comedy|Romance
4,Waiting to Exhale (1995),Comedy|Drama|Romance
5,Father of the Bride Part II (1995),Comedy
6,Heat (1995),Action|Crime|Thriller
CSV

cat > "$PROJECT_DIR/data/ratings.csv" << 'CSV'
user_id,movie_id,rating,timestamp
1,1,4.0,964982703
1,3,4.0,964981247
1,6,4.0,964982224
2,1,5.0,964982703
2,3,2.0,964981247
2,6,5.0,964982224
3,1,1.0,964982703
3,3,5.0,964981247
3,6,1.0,964982224
4,2,3.0,964982703
5,1,5.0,964982703
5,2,5.0,964982703
CSV

# --- 2. Create Source Code (With Bugs) ---

# BUG 1: Similarity (engine/similarity.py)
# Calculates denominator as sum(A)*sum(B) instead of sqrt(sum(A^2))*sqrt(sum(B^2))
cat > "$PROJECT_DIR/engine/similarity.py" << 'PYEOF'
import numpy as np

def calculate_cosine_similarity(vec_a, vec_b):
    """
    Calculate Cosine Similarity between two vectors.
    Formula: dot(A, B) / (norm(A) * norm(B))
    """
    if len(vec_a) != len(vec_b):
        raise ValueError("Vectors must be same length")

    dot_product = np.dot(vec_a, vec_b)
    
    # BUG: Incorrect denominator calculation for Cosine Similarity
    # Using sum instead of Euclidean norm (sqrt of sum of squares)
    norm_a = np.sum(np.abs(vec_a))
    norm_b = np.sum(np.abs(vec_b))
    
    if norm_a == 0 or norm_b == 0:
        return 0.0
        
    return dot_product / (norm_a * norm_b)
PYEOF

# BUG 2: Selection (engine/selection.py)
# argsort sorts ascending, taking [:k] gets the SMALLEST values (least similar)
cat > "$PROJECT_DIR/engine/selection.py" << 'PYEOF'
import numpy as np

def get_top_k_neighbors(similarity_scores, k=5):
    """
    Select indices of the top k highest similarity scores.
    Args:
        similarity_scores: List or array of floats
        k: Number of neighbors to select
    Returns:
        Indices of the top k neighbors
    """
    arr = np.array(similarity_scores)
    
    # BUG: np.argsort sorts in ascending order (smallest to largest).
    # Taking the first k elements gives the LEAST similar users, not the most similar.
    sorted_indices = np.argsort(arr)
    
    return sorted_indices[:k]
PYEOF

# BUG 3: Prediction (engine/prediction.py)
# Weighted average divides by k (count) instead of sum of weights
cat > "$PROJECT_DIR/engine/prediction.py" << 'PYEOF'
import numpy as np

def predict_score(neighbor_ratings, neighbor_similarities):
    """
    Calculate predicted rating using weighted average.
    Formula: sum(rating * similarity) / sum(similarity)
    """
    if not neighbor_ratings or not neighbor_similarities:
        return 0.0
        
    ratings = np.array(neighbor_ratings)
    sims = np.array(neighbor_similarities)
    
    weighted_sum = np.sum(ratings * sims)
    
    # BUG: Weighted average should divide by the sum of weights (similarities),
    # not the count of neighbors.
    normalization_factor = len(neighbor_ratings)
    
    if normalization_factor == 0:
        return 0.0
        
    return weighted_sum / normalization_factor
PYEOF

touch "$PROJECT_DIR/engine/__init__.py"

# --- 3. Create Tests ---

cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import numpy as np
import pandas as pd
import os

@pytest.fixture
def sample_vectors():
    return np.array([1, 2, 3]), np.array([1, 2, 3])

@pytest.fixture
def orthogonal_vectors():
    return np.array([1, 0]), np.array([0, 1])
PYEOF

cat > "$PROJECT_DIR/tests/test_similarity.py" << 'PYEOF'
import numpy as np
import pytest
from engine.similarity import calculate_cosine_similarity

def test_identical_vectors(sample_vectors):
    # Cosine similarity of identical vectors should be 1.0
    v1, v2 = sample_vectors
    assert calculate_cosine_similarity(v1, v2) == pytest.approx(1.0, 0.001)

def test_orthogonal_vectors(orthogonal_vectors):
    # Cosine similarity of orthogonal vectors should be 0.0
    v1, v2 = orthogonal_vectors
    assert calculate_cosine_similarity(v1, v2) == pytest.approx(0.0, 0.001)

def test_manual_calculation():
    # v1=[3, 4], v2=[6, 8] -> dot=18+32=50, norm1=5, norm2=10 -> sim=50/50=1.0
    v1 = np.array([3, 4])
    v2 = np.array([6, 8])
    assert calculate_cosine_similarity(v1, v2) == pytest.approx(1.0, 0.001)
PYEOF

cat > "$PROJECT_DIR/tests/test_selection.py" << 'PYEOF'
import numpy as np
from engine.selection import get_top_k_neighbors

def test_finds_highest_values():
    # Should pick indices 1 (0.9) and 3 (0.8)
    scores = [0.1, 0.9, 0.2, 0.8, 0.3]
    indices = get_top_k_neighbors(scores, k=2)
    
    # Convert to set for comparison as order within top-k doesn't strictly matter for set equality
    # but strictly argsort output might be ordered. 
    # Logic: indices should contain 1 and 3.
    assert 1 in indices
    assert 3 in indices
    assert 0 not in indices

def test_returns_correct_count():
    scores = [0.1, 0.2, 0.3, 0.4, 0.5]
    indices = get_top_k_neighbors(scores, k=3)
    assert len(indices) == 3
PYEOF

cat > "$PROJECT_DIR/tests/test_prediction.py" << 'PYEOF'
import numpy as np
from engine.prediction import predict_score

def test_weighted_average_simple():
    # Rating 5.0 with weight 1.0
    # Rating 3.0 with weight 0.5
    # Sum(r*w) = 5*1 + 3*0.5 = 6.5
    # Sum(w) = 1.0 + 0.5 = 1.5
    # Result = 6.5 / 1.5 = 4.333...
    
    ratings = [5.0, 3.0]
    weights = [1.0, 0.5]
    
    pred = predict_score(ratings, weights)
    assert pred == pytest.approx(4.333, 0.01)

def test_weighted_average_identical():
    # If all ratings are 4.0, weighted avg should be 4.0
    ratings = [4.0, 4.0, 4.0]
    weights = [0.1, 0.5, 0.9]
    pred = predict_score(ratings, weights)
    assert pred == pytest.approx(4.0, 0.001)
PYEOF

cat > "$PROJECT_DIR/requirements.txt" << 'TXT'
numpy>=1.20.0
pytest>=7.0.0
pandas>=1.3.0
TXT

# --- 4. Final Setup Actions ---
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_startup.log 2>&1 &"

# Record start time
date +%s > /tmp/recommender_start_time

echo "=== Setup complete ==="