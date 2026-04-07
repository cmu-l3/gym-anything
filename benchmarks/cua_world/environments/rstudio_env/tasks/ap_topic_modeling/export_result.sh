#!/bin/bash
echo "=== Exporting AP Topic Modeling Result ==="

source /workspace/scripts/task_utils.sh

# Record end time and capture final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Paths
OUT_DIR="/home/ga/RProjects/output"
SUMMARY_CSV="$OUT_DIR/ap_corpus_summary.csv"
TOPICS_CSV="$OUT_DIR/ap_lda_topics.csv"
COMPARISON_CSV="$OUT_DIR/ap_model_comparison.csv"
PLOT_PNG="$OUT_DIR/ap_text_analysis.png"
SCRIPT_R="$OUT_DIR/../ap_text_analysis.R"

# Use Python to validate files and generate a structured JSON result
# This is safer than complex bash parsing
python3 << PYEOF
import json
import os
import csv
import sys
import time

def get_file_info(path, start_time):
    exists = os.path.exists(path)
    if not exists:
        return {"exists": False, "size": 0, "is_new": False}
    
    mtime = os.path.getmtime(path)
    size = os.path.getsize(path)
    return {
        "exists": True,
        "size": size,
        "is_new": mtime > start_time,
        "mtime": mtime
    }

def validate_summary_csv(path):
    if not os.path.exists(path):
        return {"valid": False, "reason": "Missing"}
    
    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        data = {row.get('metric', '').strip(): row.get('value', '').strip() for row in rows}
        
        # Check critical metrics
        n_docs = float(data.get('n_documents', 0))
        vocab = float(data.get('vocabulary_size', 0))
        sparsity = float(data.get('sparsity', 0))
        
        return {
            "valid": True,
            "n_documents": n_docs,
            "vocabulary_size": vocab,
            "sparsity": sparsity,
            "has_required_metrics": all(k in data for k in ['n_documents', 'sparsity'])
        }
    except Exception as e:
        return {"valid": False, "reason": str(e)}

def validate_topics_csv(path):
    if not os.path.exists(path):
        return {"valid": False, "reason": "Missing"}
    
    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            fieldnames = [f.lower() for f in (reader.fieldnames or [])]
            rows = list(reader)
            
        has_cols = all(c in fieldnames for c in ['topic', 'term', 'beta'])
        row_count = len(rows)
        
        # Check topic count and beta range
        topics = set(row.get('topic') for row in rows)
        betas = [float(row.get('beta', -1)) for row in rows]
        valid_betas = all(0 <= b <= 1 for b in betas)
        
        return {
            "valid": True,
            "has_columns": has_cols,
            "row_count": row_count,
            "unique_topics": len(topics),
            "valid_betas": valid_betas
        }
    except Exception as e:
        return {"valid": False, "reason": str(e)}

def validate_comparison_csv(path):
    if not os.path.exists(path):
        return {"valid": False, "reason": "Missing"}
    
    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        k_values = sorted([int(float(row.get('k', 0))) for row in rows])
        perplexities = [float(row.get('perplexity', 0)) for row in rows]
        
        return {
            "valid": True,
            "k_values": k_values,
            "row_count": len(rows),
            "has_perplexity": any(p > 0 for p in perplexities)
        }
    except Exception as e:
        return {"valid": False, "reason": str(e)}

# Main execution
start_time = float("$TASK_START")

result = {
    "summary": {**get_file_info("$SUMMARY_CSV", start_time), **validate_summary_csv("$SUMMARY_CSV")},
    "topics": {**get_file_info("$TOPICS_CSV", start_time), **validate_topics_csv("$TOPICS_CSV")},
    "comparison": {**get_file_info("$COMPARISON_CSV", start_time), **validate_comparison_csv("$COMPARISON_CSV")},
    "plot": get_file_info("$PLOT_PNG", start_time),
    "script": get_file_info("$SCRIPT_R", start_time),
    "task_start": start_time,
    "timestamp": time.time()
}

# Save to temp file
with open('/tmp/py_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Move result to final location with proper permissions
mv /tmp/py_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="