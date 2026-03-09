#!/usr/bin/env python3
"""
Verifier for compute_inundation_width task.

Criteria:
1. CSV File Exists & Created During Task
2. CSV Format Correct (Headers, Rows)
3. Numeric Accuracy (Compare Agent's CSV vs Ground Truth from HDF)
4. Summary File Exists & Correct
"""

import json
import tempfile
import os
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_inundation_width(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    max_score = 100
    feedback = []
    
    # 1. Check CSV Existence (10 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("CSV file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "CSV file not found."}
        
    # 2. Check Anti-Gaming (Created during task) (10 pts)
    if result.get('csv_created_during_task'):
        score += 10
    else:
        feedback.append("Warning: CSV file timestamp is old (pre-task?).")

    # Parse Ground Truth
    gt_data = result.get('ground_truth', {})
    if 'error' in gt_data:
        feedback.append(f"Verification Error: {gt_data['error']}")
        # Fallback if ground truth failed (shouldn't happen)
        gt_rows = []
    else:
        gt_rows = gt_data.get('ground_truth', [])
        
    # Parse Agent CSV
    agent_csv_text = result.get('agent_csv_content', '')
    agent_rows = []
    try:
        reader = csv.DictReader(io.StringIO(agent_csv_text))
        for row in reader:
            agent_rows.append(row)
    except Exception as e:
        feedback.append(f"Failed to parse CSV: {e}")
        
    # 3. Validation
    if not agent_rows:
        return {"passed": False, "score": score, "feedback": "CSV file is empty or invalid format."}
        
    # Validate Headers
    expected_headers = {'River_Station', 'Peak_WSE_ft', 'Top_Width_ft'}
    agent_headers = set(agent_rows[0].keys())
    if expected_headers.issubset(agent_headers):
        score += 5
        feedback.append("CSV headers correct.")
    else:
        feedback.append(f"Missing CSV headers. Found: {agent_headers}")
        
    # Compare Values
    matches_wse = 0
    matches_width = 0
    total_comparisons = 0
    
    # Create lookup for ground truth
    gt_lookup = {r['River_Station']: r for r in gt_rows}
    
    for row in agent_rows:
        rs = row.get('River_Station', '').strip()
        if rs in gt_lookup:
            total_comparisons += 1
            gt = gt_lookup[rs]
            
            # WSE Check (Tol: 0.1 ft)
            try:
                val = float(row.get('Peak_WSE_ft', -999))
                if abs(val - gt['Peak_WSE_ft']) < 0.1:
                    matches_wse += 1
            except: pass
            
            # Width Check (Tol: 5% or 5ft)
            try:
                val = float(row.get('Top_Width_ft', -999))
                diff = abs(val - gt['Top_Width_ft'])
                if diff < 5.0 or diff < (gt['Top_Width_ft'] * 0.05):
                    matches_width += 1
            except: pass
            
    if total_comparisons > 0:
        wse_acc = matches_wse / total_comparisons
        width_acc = matches_width / total_comparisons
        
        score += int(30 * wse_acc) # Up to 30 pts for WSE
        score += int(30 * width_acc) # Up to 30 pts for Width
        
        feedback.append(f"WSE Accuracy: {wse_acc:.1%}, Width Accuracy: {width_acc:.1%}")
    else:
        feedback.append("No matching river stations found to compare.")

    # 4. Summary File Check (15 pts)
    if result.get('summary_exists'):
        score += 5
        summary_text = result.get('agent_summary_content', '')
        # Check for key values in summary
        # Max Width
        gt_max = gt_data.get('max_width', 0)
        gt_station = gt_data.get('max_width_station', '')
        
        # Simple heuristic check of summary content
        if str(gt_station) in summary_text:
            score += 5
            feedback.append("Max width station found in summary.")
        
        # Check for numeric presence near the value (rough check)
        if any(str(int(gt_max)) in summary_text for _ in [1]): 
            score += 5
    else:
        feedback.append("Summary file missing.")
        
    passed = score >= 60 and matches_width > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }