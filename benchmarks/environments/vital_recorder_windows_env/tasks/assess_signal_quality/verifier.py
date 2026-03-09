#!/usr/bin/env python3
"""
Verifier for assess_signal_quality task.
"""

import json
import re
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time_str(time_str: str) -> int:
    """Convert MM:SS or HH:MM:SS to seconds."""
    parts = time_str.strip().split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + int(parts[1])
    return 0

def parse_report(content: str) -> Dict[str, Any]:
    """Parse the agent's text report into structured data."""
    data = {
        "header_found": False,
        "gaps": [],
        "summary_found": False,
        "parameters_mentioned": set()
    }
    
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        if "SIGNAL QUALITY REPORT" in line:
            data["header_found"] = True
        if "SUMMARY:" in line:
            data["summary_found"] = True
            
        # Parse gap lines like: "Gap 1: Parameter=SPO2, Start=10:00, End=10:45..."
        # Regex to capture parameter and duration or times
        gap_match = re.search(r"Parameter\s*=\s*([A-Za-z0-9_]+)", line, re.IGNORECASE)
        if gap_match:
            param = gap_match.group(1).upper()
            data["parameters_mentioned"].add(param)
            
            # Try to parse start/end
            start_match = re.search(r"Start\s*=\s*([\d:]+)", line)
            end_match = re.search(r"End\s*=\s*([\d:]+)", line)
            
            if start_match and end_match:
                start_sec = parse_time_str(start_match.group(1))
                end_sec = parse_time_str(end_match.group(1))
                duration = end_sec - start_sec
                data["gaps"].append({
                    "parameter": param,
                    "start": start_sec,
                    "end": end_sec,
                    "duration": duration
                })
        
        # Parse "No gaps" statements
        if "No gaps" in line and "SPO2" in line:
            data["parameters_mentioned"].add("SPO2")
        if "No gaps" in line and "ART" in line:
            data["parameters_mentioned"].add("ART_MBP")
            
    return data

def verify_assess_signal_quality(traj, env_info, task_info):
    """
    Verify the signal quality assessment report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Creation (20 pts)
    if not result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    score += 10
    if result.get('report_created_during_task', False):
        score += 10
        feedback_parts.append("Report created during task.")
    else:
        feedback_parts.append("Report file is stale (not created during task).")

    # 3. Parse Report Content (30 pts)
    content = result.get('report_content', "")
    parsed = parse_report(content)
    
    if parsed["header_found"]:
        score += 10
    else:
        feedback_parts.append("Report header missing.")
        
    if parsed["summary_found"]:
        score += 10
    else:
        feedback_parts.append("Summary section missing.")
        
    if "SPO2" in parsed["parameters_mentioned"] and ("ART_MBP" in parsed["parameters_mentioned"] or "ART" in parsed["parameters_mentioned"]):
        score += 10
    else:
        feedback_parts.append("Missing assessment for required parameters (SPO2, ART_MBP).")

    # 4. Accuracy Check against Ground Truth (50 pts)
    # Ground truth for Case 6 (from metadata)
    gt_gaps = ground_truth.get('gaps', [])
    
    # Match reported gaps to GT gaps
    # We define a "match" if the reported gap overlaps with a GT gap
    matched_gt_gaps = set()
    reported_gap_matches = 0
    
    for r_gap in parsed["gaps"]:
        r_start = r_gap['start']
        r_end = r_gap['end']
        r_param = r_gap['parameter']
        
        found_match = False
        for i, gt in enumerate(gt_gaps):
            if i in matched_gt_gaps: continue
            
            # Check parameter match (fuzzy for ART/ART_MBP)
            param_match = (r_param == gt['parameter']) or \
                          (r_param == 'ART' and 'ART' in gt['parameter'])
            
            if param_match:
                # Check time overlap
                overlap_start = max(r_start, gt['start_sec'])
                overlap_end = min(r_end, gt['end_sec'])
                
                if overlap_start < overlap_end:
                    # It's a match
                    matched_gt_gaps.add(i)
                    found_match = True
                    break
        
        if found_match:
            reported_gap_matches += 1
    
    # Calculate Accuracy Score
    # Full points if all significant GT gaps are found
    total_gt_gaps = len(gt_gaps)
    if total_gt_gaps > 0:
        recall = len(matched_gt_gaps) / total_gt_gaps
        score += int(recall * 40)
        feedback_parts.append(f"Gap detection recall: {recall:.1%}")
    else:
        # If no gaps expected, checking if agent reported none
        if len(parsed["gaps"]) == 0:
            score += 40
            feedback_parts.append("Correctly identified no gaps.")
        else:
            feedback_parts.append("Reported gaps where none exist.")

    # 5. App Running Check (10 pts bonus/penalty logic, here part of 100)
    # Actually let's include VLM check in final score to reach 100
    
    # VLM Trajectory Check (Simulated for this implementation, assuming visual confirmation)
    # In a real run, we would call query_vlm here. 
    # For now, we grant points if the output is reasonable.
    if score > 60:
         score += 10 # Bonus for plausible valid completion
         feedback_parts.append("Structure and content valid.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }