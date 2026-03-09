#!/usr/bin/env python3
"""
Verifier for configure_water_monitoring_pipeline task.

Checks:
1. Feeds exist and are configured correctly (PHPFina, 10s).
2. Physics verification:
   - Total Volume matches pulse_count * 0.01 (1 pulse = 10L = 0.01m3)
   - Flow Rate matches calculated L/min from pulse delta
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_water_monitoring_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_m3_test_val', 200.1)
    expected_flow = metadata.get('expected_flow_lpm_test_val', 600.0)
    
    # Tolerances
    # Total: exact scalar multiplication, low tolerance
    tol_total = 0.5 
    # Flow: rate calculation might vary slightly based on exact timing, higher tolerance
    tol_flow = 20.0 

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Feeds Created (20 pts)
    if result.get("feed_total_exists") and result.get("feed_flow_exists"):
        score += 20
        feedback_parts.append("Both feeds created")
    elif result.get("feed_total_exists") or result.get("feed_flow_exists"):
        score += 10
        feedback_parts.append("One feed created")
    else:
        feedback_parts.append("No feeds created")
        return {"passed": False, "score": 0, "feedback": "No feeds created"}

    # Criterion 2: Configuration (10 pts)
    if result.get("total_config_ok") and result.get("flow_config_ok"):
        score += 10
        feedback_parts.append("Feed configuration correct (PHPFina/10s)")
    elif result.get("total_config_ok") or result.get("flow_config_ok"):
        score += 5
        feedback_parts.append("Partial configuration match")

    # Criterion 3: Total Volume Accuracy (35 pts)
    measured_total = float(result.get("measured_total_m3", 0))
    if abs(measured_total - expected_total) <= tol_total:
        score += 35
        feedback_parts.append(f"Volume calculation correct ({measured_total} m3)")
    else:
        feedback_parts.append(f"Volume incorrect (Expected {expected_total}, Got {measured_total})")
        # Diagnostic Hint
        if abs(measured_total - (expected_total * 100)) < 1.0:
             feedback_parts.append("Hint: Did you forget to scale pulses to m3 (x0.01)?")

    # Criterion 4: Flow Rate Accuracy (35 pts)
    measured_flow = float(result.get("measured_flow_lpm", 0))
    if abs(measured_flow - expected_flow) <= tol_flow:
        score += 35
        feedback_parts.append(f"Flow rate calculation correct ({measured_flow} L/min)")
    else:
        feedback_parts.append(f"Flow rate incorrect (Expected {expected_flow}, Got {measured_flow})")
        # Diagnostic Hints
        if abs(measured_flow - (expected_flow / 60)) < 1.0:
            feedback_parts.append("Hint: Value looks like Liters/Second. Did you scale to Minutes (x60)?")
        elif abs(measured_flow - (expected_flow / 600)) < 1.0:
            feedback_parts.append("Hint: Value looks like pulses/sec. Did you scale to Liters (x10) AND Minutes (x60)?")

    # Anti-gaming
    if not result.get("feeds_created_during_task", False):
        score = 0
        feedback_parts.append("FAIL: Feeds pre-existed or not created during task")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }