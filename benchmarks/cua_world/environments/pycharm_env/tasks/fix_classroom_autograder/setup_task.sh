#!/bin/bash
echo "=== Setting up fix_classroom_autograder ==="

# Load standard utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_classroom_autograder"
PROJECT_DIR="/home/ga/PycharmProjects/autograder"

# Clean up any previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
rm -f /tmp/tests_checksum.md5 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Create project structure
mkdir -p "$PROJECT_DIR/grader"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# --- Create Source Code with Bugs ---

# 1. scorer.py (Bug: Compound vs Linear penalty)
cat > "$PROJECT_DIR/grader/scorer.py" << 'EOF'
"""
Scoring module for calculating raw scores and penalties.
"""

def score_submission(submission, test_results):
    """
    Calculate score based on passing tests.
    """
    total_tests = len(test_results)
    if total_tests == 0:
        return 0.0
    
    passed = sum(1 for t in test_results if t['passed'])
    return (passed / total_tests) * submission['max_score']

def apply_late_penalty(score, days_late, penalty_rate=0.10, max_late_days=3):
    """
    Apply late penalty to a score.
    Policy: 10% deduction per day late, up to 3 days.
    """
    if days_late <= 0:
        return score
    
    if days_late > max_late_days:
        return 0.0
    
    # BUG: Calculates compound penalty (score * 0.9^days) instead of linear (score * (1 - 0.1*days))
    # For 3 days late: 
    #   Linear (Correct): score * (1 - 0.3) = score * 0.7
    #   Compound (Bug):   score * (0.9)^3   = score * 0.729
    # The linear deduction is standard department policy.
    penalty_factor = (1 - penalty_rate) ** days_late
    return score * penalty_factor
EOF

# 2. grades.py (Bug: Strict inequality & Bug: Weighted avg denominator)
cat > "$PROJECT_DIR/grader/grades.py" << 'EOF'
"""
Grade calculation module.
"""

def letter_grade(score):
    """
    Convert numeric percentage to letter grade.
    """
    # BUG: Strict inequality (> 90) means exactly 90.0 gets B+ instead of A-
    if score > 93: return 'A'
    if score > 90: return 'A-'
    if score > 87: return 'B+'
    if score > 83: return 'B'
    if score > 80: return 'B-'
    if score > 77: return 'C+'
    if score > 73: return 'C'
    if score > 70: return 'C-'
    if score > 67: return 'D+'
    if score > 63: return 'D'
    if score > 60: return 'D-'
    return 'F'

def weighted_average(category_scores, category_weights):
    """
    Compute weighted average of scores.
    category_scores: dict mapping category name to average score (0-100)
    category_weights: dict mapping category name to weight (0.0-1.0)
    """
    total_score = 0.0
    
    # BUG: The denominator sums ALL configured weights, even if the category 
    # has no scores yet (e.g. Final Exam). It should only sum weights for 
    # categories present in category_scores.
    # If Homework(30) + Lab(25) + Midterm(20) are done, but Final(25) is not,
    # we should divide by 0.75, not 1.0.
    total_weight = sum(category_weights.values())
    
    if total_weight == 0:
        return 0.0

    for category, score in category_scores.items():
        if category in category_weights:
            weight = category_weights[category]
            total_score += score * weight
            
    return total_score / total_weight
EOF

# 3. export.py (Bug: Column swap)
cat > "$PROJECT_DIR/grader/export.py" << 'EOF'
"""
Export module for generating grade reports.
"""
import csv

def export_csv(grades, output_path):
    """
    Export grades to CSV.
    Expected Header: student_id, name, score, letter_grade
    """
    with open(output_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['student_id', 'name', 'score', 'letter_grade'])
        
        for student in grades:
            # BUG: Data columns swapped (name, student_id) vs Header (student_id, name)
            writer.writerow([
                student['name'],
                student['student_id'],
                f"{student['final_score']:.2f}",
                student['letter_grade']
            ])
EOF

# 4. __init__.py
touch "$PROJECT_DIR/grader/__init__.py"

# --- Create Tests ---

cat > "$PROJECT_DIR/tests/__init__.py" << 'EOF'
EOF

cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest

@pytest.fixture
def sample_weights():
    return {
        'Homework': 0.30,
        'Lab': 0.25,
        'Midterm': 0.20,
        'Final': 0.25
    }

@pytest.fixture
def sample_submission():
    return {'max_score': 100}
EOF

cat > "$PROJECT_DIR/tests/test_scorer.py" << 'EOF'
import pytest
from grader.scorer import apply_late_penalty

def test_no_penalty_on_time():
    assert apply_late_penalty(100, 0) == 100

def test_late_penalty_one_day():
    # 10% deduction
    assert apply_late_penalty(100, 1) == 90.0

def test_late_penalty_three_days():
    # 3 days late = 30% deduction (Linear)
    # 100 * (1 - 0.30) = 70.0
    # The bug (compound) would give 100 * 0.9^3 = 72.9
    score = apply_late_penalty(100, 3)
    assert score == pytest.approx(70.0, 0.01), "Should use linear deduction (10% per day), not compound"
EOF

cat > "$PROJECT_DIR/tests/test_grades.py" << 'EOF'
import pytest
from grader.grades import letter_grade, weighted_average

def test_grade_boundary_clear_A():
    assert letter_grade(95) == 'A'

def test_grade_boundary_exact_90():
    # Boundary condition: 90.0 should be A-, not B+
    assert letter_grade(90.0) == 'A-', "Inclusive boundary check failed (>= 90 should be A-)"

def test_grade_boundary_exact_80():
    assert letter_grade(80.0) == 'B-', "Inclusive boundary check failed (>= 80 should be B-)"

def test_weighted_average_all_categories(sample_weights):
    scores = {
        'Homework': 100,
        'Lab': 100,
        'Midterm': 100,
        'Final': 100
    }
    assert weighted_average(scores, sample_weights) == 100.0

def test_weighted_average_missing_category(sample_weights):
    # Student hasn't taken Final Exam yet
    # Weights: HW(0.3), Lab(0.25), Midterm(0.2) = 0.75 total used weight
    # Scores: 100 on all
    # Calculation should be: (100*0.3 + 100*0.25 + 100*0.2) / 0.75 = 100.0
    # Buggy calculation divides by 1.0 (total possible weight) -> 75.0
    scores = {
        'Homework': 100,
        'Lab': 100,
        'Midterm': 100
    }
    avg = weighted_average(scores, sample_weights)
    assert avg == pytest.approx(100.0, 0.01), "Should normalize by sum of *active* weights only"
EOF

cat > "$PROJECT_DIR/tests/test_export.py" << 'EOF'
import pytest
import csv
import os
from grader.export import export_csv

def test_csv_column_order(tmp_path):
    output_file = tmp_path / "grades.csv"
    data = [{
        'student_id': '12345',
        'name': 'John Doe',
        'final_score': 88.5,
        'letter_grade': 'B+'
    }]
    
    export_csv(data, str(output_file))
    
    with open(output_file, 'r') as f:
        reader = csv.DictReader(f)
        row = next(reader)
        
        # Verify columns map correctly
        assert row['student_id'] == '12345', "student_id column contains wrong data (check column order)"
        assert row['name'] == 'John Doe', "name column contains wrong data"
        assert row['score'] == '88.50'
        assert row['letter_grade'] == 'B+'
EOF

# --- Create Data ---
cat > "$PROJECT_DIR/data/sample_submissions.json" << 'EOF'
[
    {"student_id": "1001", "name": "Alice", "assignment": "HW1", "score": 95},
    {"student_id": "1002", "name": "Bob", "assignment": "HW1", "score": 88}
]
EOF

# Store checksum of tests for anti-gaming verification
find "$PROJECT_DIR/tests" -type f -exec md5sum {} + | sort > /tmp/tests_checksum.md5

# Setup PyCharm
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "autograder" 120

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="