#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Implementation Approaches Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create iterative implementation
cat > "$WORKSPACE_DIR/data_processor_iterative.py" << 'EOF'
"""Iterative approach to data processing"""
from typing import List
import time

def process_records(data: List[dict]) -> List[dict]:
    """Process records using iterative approach"""
    result = []
    for record in data:
        if record.get('score', 0) > 50:
            processed = record.copy()
            score = processed['score']
            if score >= 90:
                processed['grade'] = 'A'
            elif score >= 80:
                processed['grade'] = 'B'
            elif score >= 70:
                processed['grade'] = 'C'
            else:
                processed['grade'] = 'D'
            result.append(processed)
    return result

def benchmark(data: List[dict], iterations: int = 1000) -> float:
    start = time.perf_counter()
    for _ in range(iterations):
        process_records(data)
    return time.perf_counter() - start
EOF

# Create functional implementation
cat > "$WORKSPACE_DIR/data_processor_functional.py" << 'EOF'
"""Functional programming approach to data processing"""
from typing import List
import time

def process_records(data: List[dict]) -> List[dict]:
    """Process records using functional approach"""
    def add_grade(record: dict) -> dict:
        score = record['score']
        grade = 'A' if score >= 90 else 'B' if score >= 80 else 'C' if score >= 70 else 'D'
        return {**record, 'grade': grade}
    
    return list(map(add_grade, filter(lambda r: r.get('score', 0) > 50, data)))

def benchmark(data: List[dict], iterations: int = 1000) -> float:
    start = time.perf_counter()
    for _ in range(iterations):
        process_records(data)
    return time.perf_counter() - start
EOF

# Create test file
cat > "$WORKSPACE_DIR/test_processor.py" << 'EOF'
"""Test both processor implementations"""
import importlib
import sys

def test_implementation(module_name: str):
    try:
        processor = importlib.import_module(module_name)
    except ImportError as e:
        print(f"❌ Failed to import {module_name}: {e}")
        return None
    
    test_data = [
        {'id': 1, 'score': 95, 'name': 'Alice'},
        {'id': 2, 'score': 45, 'name': 'Bob'},
        {'id': 3, 'score': 82, 'name': 'Charlie'},
        {'id': 4, 'score': 67, 'name': 'Diana'},
        {'id': 5, 'score': 55, 'name': 'Eve'},
    ]
    
    result = processor.process_records(test_data)
    print(f"\n=== {module_name} ===")
    print(f"Records: {len(test_data)} → {len(result)}")
    print(f"Results: {result}")
    
    try:
        assert len(result) == 4, f"Expected 4, got {len(result)}"
        assert all('grade' in r for r in result), "Missing 'grade' in results"
        assert result[0]['grade'] == 'A', f"Expected grade 'A', got {result[0]['grade']}"
        print("✓ Correctness tests passed")
    except AssertionError as e:
        print(f"❌ Test failed: {e}")
        return None
    
    time_taken = processor.benchmark(test_data)
    print(f"Benchmark: {time_taken:.4f}s (1000 iterations)")
    
    return time_taken

if __name__ == '__main__':
    print("="*50)
    print("Testing Data Processor Implementations")
    print("="*50)
    
    t1 = test_implementation('data_processor_iterative')
    t2 = test_implementation('data_processor_functional')
    
    if t1 is not None and t2 is not None:
        print(f"\n{'='*50}")
        print("Performance Comparison")
        print(f"{'='*50}")
        print(f"Iterative:  {t1:.4f}s")
        print(f"Functional: {t2:.4f}s")
        faster = "Iterative" if t1 < t2 else "Functional"
        diff = abs((t1 - t2) / min(t1, t2) * 100)
        print(f"\n{faster} is {diff:.1f}% faster")
    else:
        print("\n❌ Could not complete comparison due to errors")
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Compare Implementation Approaches Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open both data_processor_*.py files in VSCode"
echo "  2. Use diff feature: Right-click → 'Select for Compare', then compare with other file"
echo "  3. Open terminal (Ctrl+\`) and run: python test_processor.py"
echo "  4. Create DECISION.md documenting your choice and reasoning"
echo "  5. Rename non-selected file to add .archived extension"
echo ""
echo "Workspace: $WORKSPACE_DIR"