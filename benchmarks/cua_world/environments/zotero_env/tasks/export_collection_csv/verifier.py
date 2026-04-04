#!/usr/bin/env python3
"""
Verifier for export_collection_csv task.

Criteria:
1. File exists at /home/ga/Documents/ml_papers.csv (20 pts)
2. File was created/modified AFTER task start (10 pts)
3. File is valid CSV with headers (20 pts)
4. Row count matches collection size (8 items) (20 pts)
5. Key paper titles are present (30 pts)
"""

import json
import os
import csv
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_export_collection_csv(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/home/ga/Documents/ml_papers.csv')
    required_titles = metadata.get('required_titles', [])
    expected_count = metadata.get('expected_count', 8)

    # 2. Get task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # Load JSON result
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

        # Check existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output file ml_papers.csv not found in Documents folder."}
        
        score += 20
        feedback_parts.append("File found")

        # Check timestamp (Anti-gaming)
        if result_data.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File timestamp predates task start")

        # 3. Analyze CSV Content
        try:
            copy_from_env(expected_path, temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Use Sniffer to check if it's actually CSV-like
                try:
                    dialect = csv.Sniffer().sniff(f.read(1024))
                    f.seek(0)
                except csv.Error:
                    # Fallback to standard reading if sniffing fails
                    f.seek(0)
                
                reader = csv.DictReader(f)
                
                # Check 1: Headers
                headers = reader.fieldnames
                if headers and 'Title' in headers and ('Author' in headers or 'Creators' in headers):
                    score += 20
                    feedback_parts.append("Valid CSV format with headers")
                else:
                    feedback_parts.append("Invalid CSV headers (Missing Title/Author)")
                    # If not valid CSV, we might stop here or try to parse anyway
                
                # Check 2: Rows and Content
                rows = list(reader)
                row_count = len(rows)
                
                # Score count (allow variance of +/- 1 in case of unexpected items)
                if expected_count - 1 <= row_count <= expected_count + 1:
                    score += 20
                    feedback_parts.append(f"Correct item count ({row_count})")
                else:
                    feedback_parts.append(f"Incorrect item count: {row_count} (expected {expected_count})")
                
                # Score Titles
                found_titles = 0
                total_required = len(required_titles)
                
                # Normalize for matching
                row_titles = [r.get('Title', '').lower() for r in rows]
                
                for req in required_titles:
                    if any(req.lower() in t for t in row_titles):
                        found_titles += 1
                
                if total_required > 0:
                    title_score = int(30 * (found_titles / total_required))
                    score += title_score
                    feedback_parts.append(f"Found {found_titles}/{total_required} required papers")

        except Exception as e:
            feedback_parts.append(f"Failed to parse CSV file: {str(e)}")
            
    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }