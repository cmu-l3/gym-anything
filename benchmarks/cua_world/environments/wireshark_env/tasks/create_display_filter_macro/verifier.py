#!/usr/bin/env python3
"""
Verifier for create_display_filter_macro task.
"""

import json
import os
import tempfile
import re

def verify_create_display_filter_macro(traj, env_info, task_info):
    """
    Verifies that the agent created the correct Wireshark macro and counted packets correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Expected values
    expected_name = "tcp_bad_quality"
    # Normalize expected expression for flexible matching (ignore whitespace)
    expected_expr_parts = [
        "tcp.analysis.retransmission",
        "tcp.analysis.fast_retransmission",
        "tcp.analysis.spurious_retransmission"
    ]
    
    # --- Criterion 1: Macro Configuration (40 points) ---
    macro_exists = result.get("macro_file_exists", False)
    macro_content = result.get("macro_content", "")
    
    macro_configured = False
    logic_correct = False
    
    if macro_exists and macro_content:
        # Check if name exists in file
        if expected_name in macro_content:
            score += 15
            feedback_parts.append(f"Macro '{expected_name}' found in config.")
            macro_configured = True
        else:
            feedback_parts.append(f"Macro '{expected_name}' NOT found in config.")

        # Check if expression logic is present
        # We check if all required fields are present in the file content associated with the macro
        missing_fields = [f for f in expected_expr_parts if f not in macro_content]
        
        if not missing_fields:
            score += 25
            feedback_parts.append("Macro logic contains all required TCP analysis fields.")
            logic_correct = True
        else:
            feedback_parts.append(f"Macro logic missing fields: {', '.join(missing_fields)}")
            
            # Partial credit if at least one field is there
            if len(missing_fields) < 3:
                score += 10
                feedback_parts.append("Partial credit for incomplete macro logic.")
    else:
        feedback_parts.append("Macro configuration file empty or not found.")

    # --- Criterion 2: Packet Count File (20 points) ---
    output_exists = result.get("output_file_exists", False)
    if output_exists:
        score += 20
        feedback_parts.append("Output file created.")
    else:
        feedback_parts.append("Output file missing.")

    # --- Criterion 3: Count Accuracy (40 points) ---
    user_count = result.get("user_count", -1)
    ground_truth = result.get("ground_truth_count", 0)
    
    # Allow small tolerance? No, exact match expected for deterministic filter
    if user_count == ground_truth:
        score += 40
        feedback_parts.append(f"Packet count correct ({user_count}).")
    elif user_count != -1:
        # Partial credit if close (maybe they missed one OR condition)
        diff = abs(user_count - ground_truth)
        if diff < 100: # Generous tolerance for potential minor version diffs in analysis
            score += 20
            feedback_parts.append(f"Packet count close ({user_count} vs {ground_truth}).")
        else:
            feedback_parts.append(f"Packet count incorrect ({user_count} vs {ground_truth}).")
    else:
        feedback_parts.append("No valid packet count found.")

    # Pass logic: Must have configured macro correctly AND got a reasonable count
    passed = (macro_configured and logic_correct and (score >= 70))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }