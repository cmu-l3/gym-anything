#!/usr/bin/env python3
"""
Verifier for Analyze Voltage Quality task.
Checks the agent's JSON report against ground truth generated during setup.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_voltage_quality(traj, env_info, task_info):
    """
    Verify the voltage quality report.
    
    Criteria:
    1. Report file exists and is valid JSON (20 pts)
    2. Total samples analyzed is accurate within tolerance (10 pts)
    3. Over-voltage count is accurate within strict tolerance (30 pts)
    4. Duration calculation is correct (20 pts)
    5. Max voltage is correct (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve files from container
    # We expect: task_result.json, agent_report.json, ground_truth.json
    
    # Helper to copy and read json
    def read_json_from_env(remote_path):
        local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        local_path = local_tmp.name
        local_tmp.close()
        try:
            copy_from_env(remote_path, local_path)
            with open(local_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to read {remote_path}: {e}")
            return None
        finally:
            if os.path.exists(local_path):
                os.unlink(local_path)

    task_res = read_json_from_env("/tmp/export_stage/task_result.json")
    agent_report = read_json_from_env("/tmp/export_stage/agent_report.json")
    ground_truth = read_json_from_env("/tmp/export_stage/ground_truth.json")
    
    if not task_res:
        return {"passed": False, "score": 0, "feedback": "System error: could not read task result"}
    
    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "System error: ground truth missing"}

    # CRITERION 1: File Existence & Validity (20 pts)
    if not task_res.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file ~/voltage_quality_report.json not found."}
    
    if not agent_report:
        return {"passed": False, "score": 10, "feedback": "Report file exists but contains invalid JSON."}
        
    score += 20
    feedback_parts.append("Valid JSON report found (+20)")
    
    # CRITERION 2: Total Samples (10 pts)
    # 24h * 60m * 6 = 8640 samples. Allow +/- 50 (agent might miss end/start slightly)
    agent_total = agent_report.get("total_samples_analyzed", 0)
    gt_total = ground_truth.get("total_samples", 8640)
    
    if abs(agent_total - gt_total) <= 50:
        score += 10
        feedback_parts.append(f"Total samples accurate ({agent_total}) (+10)")
    else:
        feedback_parts.append(f"Total samples mismatch: got {agent_total}, expected approx {gt_total}")
        
    # CRITERION 3: Excursion Count (30 pts)
    # Strict tolerance (+/- 1% or 2 samples, whichever is larger)
    agent_count = agent_report.get("samples_over_threshold", 0)
    gt_count = ground_truth.get("samples_over_253", 0)
    tolerance = max(2, int(gt_count * 0.01))
    
    if abs(agent_count - gt_count) <= tolerance:
        score += 30
        feedback_parts.append(f"Excursion count accurate ({agent_count}) (+30)")
    else:
        feedback_parts.append(f"Excursion count incorrect: got {agent_count}, expected {gt_count}")
        
    # CRITERION 4: Duration (20 pts)
    # Should match ground truth minutes within 1 minute
    agent_mins = agent_report.get("minutes_over_threshold", 0.0)
    gt_mins = ground_truth.get("minutes_over_253", 0.0)
    
    if abs(agent_mins - gt_mins) <= 1.0:
        score += 20
        feedback_parts.append(f"Duration accurate ({agent_mins}m) (+20)")
    else:
        feedback_parts.append(f"Duration incorrect: got {agent_mins}m, expected {gt_mins}m")
        
    # CRITERION 5: Max Voltage (20 pts)
    # Tolerance +/- 0.1V
    agent_max = agent_report.get("max_observed_voltage", 0.0)
    gt_max = ground_truth.get("max_voltage", 0.0)
    
    if abs(agent_max - gt_max) <= 0.15:
        score += 20
        feedback_parts.append(f"Max voltage accurate ({agent_max}V) (+20)")
    else:
        feedback_parts.append(f"Max voltage incorrect: got {agent_max}V, expected {gt_max}V")
        
    # Final check
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }