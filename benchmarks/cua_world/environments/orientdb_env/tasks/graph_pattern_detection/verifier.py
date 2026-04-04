#!/usr/bin/env python3
"""
Verifier for graph_pattern_detection task.
Evaluates the task based on the JSON result exported from the container.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_graph_pattern_detection(traj, env_info, task_info):
    """
    Verifies the Graph Pattern Detection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_edge_count = metadata.get('expected_edge_count', 14)
    expected_sum = metadata.get('expected_shared_hotels_sum', 18)
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    db = result.get('db_metrics', {})
    report_exists = result.get('report_exists', False)
    
    # --- Check 1: Schema Correctness (15 pts) ---
    if db.get('class_exists'):
        if db.get('class_extends_e'):
            score += 10
            feedback.append("TravelBuddy class exists and extends E.")
        else:
            score += 5
            feedback.append("TravelBuddy class exists but does not extend E properly.")
    else:
        feedback.append("TravelBuddy class missing.")

    if db.get('property_exists'):
        p_type = db.get('property_type', '').upper()
        if p_type == 'INTEGER':
            score += 5
            feedback.append("SharedHotels property exists and is INTEGER.")
        else:
            score += 2
            feedback.append(f"SharedHotels property exists but type is {p_type} (expected INTEGER).")
    else:
        feedback.append("SharedHotels property missing.")

    # --- Check 2: Graph Connectivity (35 pts) ---
    edge_count = db.get('edge_count', 0)
    if edge_count == expected_edge_count:
        score += 20
        feedback.append(f"Correct number of edges created ({edge_count}).")
    elif abs(edge_count - expected_edge_count) <= 2:
        score += 10
        feedback.append(f"Edge count close ({edge_count}), expected {expected_edge_count}.")
    else:
        feedback.append(f"Edge count incorrect ({edge_count}), expected {expected_edge_count}.")

    # Sum check
    shared_sum = db.get('shared_hotels_sum', 0)
    if shared_sum == expected_sum:
        score += 10
        feedback.append(f"Total SharedHotels sum matches ground truth ({shared_sum}).")
    elif shared_sum > 0:
        feedback.append(f"Total SharedHotels sum mismatch ({shared_sum}), expected {expected_sum}.")

    # Self loops check
    if db.get('self_loops', 0) == 0:
        score += 5
    else:
        feedback.append("Warning: Self-loops detected in graph.")

    # --- Check 3: Spot Checks (15 pts) ---
    jd_shared = db.get('john_david_shared', 0)
    if jd_shared == 2:
        score += 10
        feedback.append("John-David connection correct (2 shared).")
    else:
        feedback.append(f"John-David connection incorrect (got {jd_shared}, expected 2).")

    ml_shared = db.get('maria_luca_shared', 0)
    if ml_shared == 1:
        score += 5
        feedback.append("Maria-Luca connection correct (1 shared).")
    else:
        feedback.append(f"Maria-Luca connection incorrect (got {ml_shared}, expected 1).")

    # --- Check 4: Report File (35 pts) ---
    if report_exists:
        score += 5
        
        # Decode content
        try:
            content_b64 = result.get('report_content_b64', '')
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            content_lower = content.lower()
            
            # Content checks
            if str(expected_edge_count) in content:
                score += 5
                feedback.append("Report mentions correct total count.")
                
            if "david" in content_lower and "jones" in content_lower:
                if "8" in content: # Score 8
                    score += 15
                    feedback.append("Report correctly identifies David Jones with score 8.")
                else:
                    score += 5
                    feedback.append("Report mentions David Jones but score might be missing/wrong.")
            else:
                feedback.append("Report fails to identify top traveler (David Jones).")
                
            # Check for timestamp validity (Anti-gaming)
            task_start = result.get('task_start', 0)
            report_mtime = result.get('report_mtime', 0)
            if report_mtime > task_start:
                score += 10
                feedback.append("Report file created during task window.")
            else:
                feedback.append("Report file timestamp predates task start.")
                
        except Exception as e:
            feedback.append(f"Error parsing report content: {e}")
    else:
        feedback.append("Report file not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }