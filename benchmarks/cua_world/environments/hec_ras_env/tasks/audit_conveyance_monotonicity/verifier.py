#!/usr/bin/env python3
"""
Verifier for audit_conveyance_monotonicity task.

Verifies that the agent correctly audited the HEC-RAS hydraulic tables.
Checks:
1. Output JSON exists and is valid.
2. Structure matches schema.
3. Monotonicity check results match expectations for Muncie model (0 violations).
4. Hydraulic quantities (max conveyance, downstream curve) are physically reasonable.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_conveyance(traj, env_info, task_info):
    """
    Verify the conveyance audit results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Retrieve files
    task_result = {}
    user_output = {}
    ground_truth = {}
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Get task result metadata
        try:
            copy_from_env("/tmp/task_result.json", f"{temp_dir}/task_result.json")
            with open(f"{temp_dir}/task_result.json", 'r') as f:
                task_result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task metadata"}

        # Get user output
        if task_result.get("output_exists", False):
            try:
                copy_from_env("/tmp/user_output.json", f"{temp_dir}/user_output.json")
                with open(f"{temp_dir}/user_output.json", 'r') as f:
                    user_output = json.load(f)
            except Exception:
                feedback_parts.append("Output file exists but could not be parsed as JSON")
        else:
            feedback_parts.append("Output file not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Get ground truth (simplified)
        try:
            copy_from_env("/tmp/ground_truth_export.json", f"{temp_dir}/ground_truth.json")
            with open(f"{temp_dir}/ground_truth.json", 'r') as f:
                ground_truth = json.load(f)
        except Exception:
            logger.warning("Could not retrieve ground truth, using defaults")
            ground_truth = {"expected_violations_count": 0, "max_k_value_min": 500000}

    # 2. Verify File Existence & Creation (20 pts)
    if task_result.get("output_exists"):
        score += 10
        if task_result.get("file_created_during_task"):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File pre-existed or timestamp error")
    
    # 3. Verify Schema Compliance (20 pts)
    required_keys = ["monotonicity_violations", "max_conveyance_station", "downstream_station_curve"]
    schema_valid = True
    for key in required_keys:
        if key not in user_output:
            schema_valid = False
            feedback_parts.append(f"Missing JSON key: {key}")
    
    if schema_valid:
        score += 20
        feedback_parts.append("Valid JSON schema")
    
    # 4. Verify Monotonicity Results (20 pts)
    # Muncie model is generally good quality, expect 0 or very few violations
    violations = user_output.get("monotonicity_violations", [])
    if isinstance(violations, list):
        if len(violations) <= 2: # Allow small tolerance for minor noise
            score += 20
            feedback_parts.append(f"Monotonicity check passed (violations: {len(violations)})")
        else:
            # If user found many, they might be hypersensitive or code is wrong, 
            # but strictly speaking Muncie shouldn't have huge issues.
            score += 10
            feedback_parts.append(f"High number of violations reported ({len(violations)}) - Verify logic")
    
    # 5. Verify Max Conveyance (20 pts)
    max_conv_data = user_output.get("max_conveyance_station", {})
    max_val = max_conv_data.get("max_conveyance_value", 0)
    
    # Expectation: Large river, high flow. K = Q/sqrt(S). For Q=20000, S=0.001 -> K ~ 600,000+
    if isinstance(max_val, (int, float)) and max_val > ground_truth.get("max_k_value_min", 500000):
        score += 20
        feedback_parts.append(f"Max conveyance value reasonable ({max_val:.2e})")
    else:
        feedback_parts.append(f"Max conveyance value suspicious ({max_val})")

    # 6. Verify Downstream Curve Data (20 pts)
    curve_data = user_output.get("downstream_station_curve", {})
    points = curve_data.get("data_points", [])
    
    if isinstance(points, list) and len(points) > 5:
        # Check if points look like a curve (increasing stage, increasing conveyance)
        is_increasing = True
        prev_k = -1
        for p in points:
            k = p.get("conveyance", -1)
            if k < prev_k:
                is_increasing = False # Unless it detected the violation here!
            prev_k = k
        
        if is_increasing:
            score += 20
            feedback_parts.append(f"Curve data looks valid ({len(points)} points)")
        else:
            score += 10
            feedback_parts.append("Curve data extracted but not strictly monotonic")
    else:
        feedback_parts.append("Insufficient curve data points")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }