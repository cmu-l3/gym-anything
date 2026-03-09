#!/usr/bin/env python3
"""
Verifier for tcp_flow_control_analysis task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_flow_control_analysis(traj, env_info, task_info):
    """
    Verify the TCP Flow Control Analysis report.
    
    Scoring:
    - Report file exists & valid format: 10 pts
    - Accuracy of 8 metrics: ~11-12 pts each (Total 90 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result from container
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
    feedback = []
    
    # 1. Check Report Existence (10 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file flow_control_report.txt not found."}
        
    if not result.get('report_created_during_task'):
        feedback.append("Warning: Report file timestamp indicates it wasn't created during this task session.")
        # We don't fail immediately, but it's suspicious.
        
    score += 5
    feedback.append("Report file exists.")

    user_vals = result.get('user_values', {})
    gt_vals = result.get('ground_truth', {})
    
    # Helper to score a field
    def score_field(field_name, label, points, tolerance=0):
        val = user_vals.get(field_name)
        gt = gt_vals.get(field_name)
        
        if val is None:
            return 0, f"{label}: Missing or invalid format"
            
        # Handle tolerance (absolute or percentage)
        diff = abs(val - gt)
        
        # Special case for window sizes where scaling might confuse things
        # But instructions asked for RAW values.
        # We give full points for exact raw match.
        # If tolerance allowed, we check percentage.
        
        # Check strict match first
        if diff == 0:
            return points, f"{label}: Correct ({val})"
            
        # Check tolerance
        if tolerance > 0 and diff <= tolerance:
             return points, f"{label}: Close enough ({val}, expected {gt})"
             
        # Check percentage tolerance for large numbers
        if gt > 0 and (diff / gt) <= 0.01: # 1% tolerance
            return points, f"{label}: Within 1% ({val}, expected {gt})"
            
        return 0, f"{label}: Incorrect ({val}, expected {gt})"

    # Scoring individual metrics
    # We have 95 points remaining. Let's distribute.
    
    # Format check (implicitly checked by extract_val returning not None)
    none_count = sum(1 for v in user_vals.values() if v is None)
    if none_count == 0:
        score += 5
        feedback.append("Report format correct.")
    else:
        feedback.append(f"Report format issues: {none_count} fields could not be parsed.")

    # Metrics
    s, f = score_field('total_packets', 'Total Packets', 10)
    score += s; feedback.append(f)
    
    s, f = score_field('zero_window', 'Zero Window', 15)
    score += s; feedback.append(f)
    
    s, f = score_field('window_update', 'Window Update', 15)
    score += s; feedback.append(f)
    
    s, f = score_field('window_full', 'Window Full', 15)
    score += s; feedback.append(f)
    
    s, f = score_field('max_window', 'Max Window Size', 10)
    score += s; feedback.append(f)
    
    s, f = score_field('min_window', 'Min Non-Zero Window', 10)
    score += s; feedback.append(f)
    
    s, f = score_field('conversations', 'TCP Conversations', 10)
    score += s; feedback.append(f)
    
    s, f = score_field('syn_wscale', 'SYN with Window Scale', 5)
    score += s; feedback.append(f)

    # Threshold
    passed = score >= 60 and none_count < 4 # At least half fields parsed and score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }