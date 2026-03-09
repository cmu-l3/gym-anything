#!/usr/bin/env python3
"""
Verifier for artifact_search_inventory task.
"""
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(content):
    """
    Parses the agent's text report into a list of dictionaries.
    Expected format:
    Path: ...
    Size: ...
    SHA-256: ...
    """
    entries = []
    current_entry = {}
    
    lines = content.split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            if current_entry:
                entries.append(current_entry)
                current_entry = {}
            continue
            
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip().lower()
            value = value.strip()
            
            if 'path' in key:
                current_entry['path'] = value
            elif 'size' in key:
                # Remove commas or 'bytes' text if agent added them
                clean_size = re.sub(r'[^\d]', '', value)
                if clean_size:
                    current_entry['size'] = int(clean_size)
            elif 'sha' in key or 'checksum' in key:
                current_entry['sha256'] = value.lower()
    
    if current_entry:
        entries.append(current_entry)
        
    return entries

def verify_artifact_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result file
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

    # Basic Checks
    if not result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file ~/artifact_inventory_report.txt not found."}

    score = 0
    feedback = []
    
    # Criterion 1: Report Exists (5 pts)
    score += 5
    feedback.append("Report file found.")
    
    # Criterion 2: Timestamp (5 pts)
    if result.get('report_created_during_task', False):
        score += 5
    else:
        feedback.append("Warning: Report file not modified during task.")

    # Parse Report
    report_content = result.get('report_content', '')
    reported_items = parse_report(report_content)
    ground_truth = result.get('ground_truth', [])
    
    # Criterion 3: Format (10 pts)
    # Check if we successfully parsed anything that looks like our structure
    if len(reported_items) > 0 and 'path' in reported_items[0]:
        score += 10
        feedback.append("Report format looks correct.")
    else:
        feedback.append("Report format invalid or empty.")

    # Verify Artifacts (20 pts per artifact x 4 = 80 pts)
    # Total available so far: 20. Remaining: 80.
    
    matches_found = 0
    
    for gt_item in ground_truth:
        gt_filename = gt_item.get('filename', '')
        gt_sha = gt_item.get('sha256', '').lower()
        gt_size = gt_item.get('size', 0)
        gt_path = gt_item.get('path', '')
        
        # Find corresponding item in report
        # We match primarily by filename existence in the reported path
        match = None
        for item in reported_items:
            # Check if filename is in the path string
            if gt_filename in item.get('path', ''):
                match = item
                break
        
        item_score = 0
        item_feedback = []
        
        if match:
            matches_found += 1
            item_score += 5  # Found
            
            # Check SHA256 (10 pts)
            rep_sha = match.get('sha256', '').lower()
            if rep_sha == gt_sha:
                item_score += 10
            else:
                item_feedback.append(f"SHA mismatch (Got {rep_sha[:8]}..., Exp {gt_sha[:8]}...)")
                
            # Check Size (5 pts)
            rep_size = match.get('size', 0)
            if rep_size == gt_size:
                item_score += 5
            else:
                item_feedback.append(f"Size mismatch (Got {rep_size}, Exp {gt_size})")
                
            score += item_score
            if item_feedback:
                feedback.append(f"{gt_filename}: " + ", ".join(item_feedback))
        else:
            feedback.append(f"Missing entry for {gt_filename}")

    # Final tally
    feedback.append(f"Found {matches_found}/4 artifacts in report.")
    
    passed = (score >= 60) and (matches_found >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }