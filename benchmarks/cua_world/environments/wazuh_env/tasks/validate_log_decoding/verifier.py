#!/usr/bin/env python3
"""
Verifier for validate_log_decoding task.

Checks:
1. JSON Report file existence and validity (10 pts)
2. JSON structure correctness (10 pts)
3. Accuracy of results vs Ground Truth (80 pts total, 16 pts per sample)
   - Checks decoder name and rule ID primarily.
4. Anti-gaming: File timestamp must be during task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_validate_log_decoding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use a temporary file to load the result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []

    # 1. File Existence and Valid JSON (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/logtest_report.json not found."}
    
    if "error" in result.get("agent_report", {}):
        return {"passed": False, "score": 0, "feedback": f"Report file is not valid JSON: {result['agent_report'].get('error')}"}

    score += 10
    feedback.append("File exists and is valid JSON")

    # Anti-gaming: Created during task
    if not result.get("file_created_during_task", False):
        feedback.append("WARNING: File timestamp indicates it was not created during this task session.")
        # Penalty? Or fail? Let's penalize heavily.
        score -= 10
        feedback.append("(Penalty: -10 pts for stale file)")

    # 2. Structure Check (10 pts)
    agent_data = result.get("agent_report", {})
    test_results = agent_data.get("test_results", [])
    
    if not isinstance(test_results, list) or len(test_results) != 5:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"JSON structure incorrect. Expected 'test_results' list with 5 items, got {len(test_results) if isinstance(test_results, list) else 'invalid type'}."
        }
    
    # Check fields in first item as a sample
    required_fields = ["log_sample", "decoder_name", "rule_id", "rule_level", "rule_description"]
    missing_fields = [f for f in required_fields if f not in test_results[0]]
    if missing_fields:
        return {
            "passed": False,
            "score": score,
            "feedback": f"JSON objects missing required fields: {', '.join(missing_fields)}"
        }

    score += 10
    feedback.append("JSON structure is correct")

    # 3. Accuracy Check (16 pts per sample * 5 = 80 pts)
    ground_truth = result.get("ground_truth", [])
    
    if len(ground_truth) != 5:
        # This shouldn't happen unless API failed during export
        return {"passed": False, "score": score, "feedback": "Verifier failed to generate ground truth."}

    correct_count = 0
    
    for i, gt in enumerate(ground_truth):
        agent_res = test_results[i]
        
        # Verify matching logic
        # We check decoder name and rule ID. IDs should be treated loosely (str vs int).
        
        gt_decoder = str(gt.get("decoder", "")).lower()
        agent_decoder = str(agent_res.get("decoder_name", "")).lower()
        
        gt_rule = str(gt.get("rule_id", ""))
        agent_rule = str(agent_res.get("rule_id", ""))
        
        sample_score = 0
        match_details = []
        
        # Decoder match (8 pts)
        if gt_decoder and gt_decoder == agent_decoder:
            sample_score += 8
        else:
            match_details.append(f"Decoder mismatch (Exp: {gt_decoder}, Got: {agent_decoder})")

        # Rule ID match (8 pts)
        if gt_rule and gt_rule == agent_rule:
            sample_score += 8
        else:
            match_details.append(f"Rule ID mismatch (Exp: {gt_rule}, Got: {agent_rule})")
            
        score += sample_score
        
        if sample_score == 16:
            correct_count += 1
        else:
            feedback.append(f"Sample {i+1}: " + ", ".join(match_details))

    feedback.append(f"Accuracy: {correct_count}/5 samples perfectly correct.")

    # Final result
    passed = (score >= 60 and correct_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }