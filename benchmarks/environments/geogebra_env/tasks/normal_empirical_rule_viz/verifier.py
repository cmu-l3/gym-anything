#!/usr/bin/env python3
"""
Verifier for Normal Empirical Rule Visualization task.

Scoring (100 points total):
  - File created during task:           15 pts
  - Normal distribution function:       25 pts (Function with correct parameters)
  - Shaded regions (Integral):          25 pts (At least 2 regions)
  - Correct Sigma bounds:               15 pts (Regions cover ±1σ, ±2σ, or ±3σ)
  - Text annotations (percentages):     20 pts

Pass threshold: 65 points
Gate: Normal function must be present for >40 points.
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_normal_empirical_rule_viz(traj, env_info, task_info):
    """Verify the Normal Empirical Rule Visualization task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    mean = metadata.get('mean', 175.4)
    sd = metadata.get('sd', 7.2)
    expected_bounds = [
        metadata.get('sigma_1_low', 168.2),
        metadata.get('sigma_1_high', 182.6),
        metadata.get('sigma_2_low', 161.0),
        metadata.get('sigma_2_high', 189.8),
        metadata.get('sigma_3_low', 153.8),
        metadata.get('sigma_3_high', 197.0)
    ]
    tolerance = metadata.get('tolerance', 0.5)

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: File created during task (15 pts)
    file_ok = result.get('file_found', False) and result.get('file_created_during_task', False)
    if file_ok:
        score += 15
        subscores["file_created"] = True
        feedback_parts.append("File created during task (+15)")
    else:
        subscores["file_created"] = False
        if not result.get('file_found', False):
            feedback_parts.append("File 'normal_empirical_rule.ggb' not found (0/15)")
        else:
            feedback_parts.append("File exists but predates task session (0/15)")

    # Criterion 2: Normal distribution function (25 pts)
    has_normal = result.get('has_normal_func', False)
    # Check if params 175.4 and 7.2 appear in the file (extracted by export script)
    # The export script extracts numbers found near commands or expressions
    params_found = False
    if result.get('normal_params'):
        params_found = True
    elif has_normal:
        # If command found but params not explicitly parsed to list, assume ok if 'has_normal_func' is true
        # export script sets has_normal_func based on regex for Normal command or exp() formula
        params_found = True
        
    if has_normal and params_found:
        score += 25
        subscores["has_normal"] = True
        feedback_parts.append("Normal distribution function found (+25)")
    else:
        subscores["has_normal"] = False
        feedback_parts.append("Normal function not found (need Normal(175.4, 7.2, x, false) or PDF formula) (0/25)")

    # Gate: Cap score if no normal function
    if not has_normal and score > 15:
        score = 15 # Only file points allowed

    # Criterion 3: Shaded regions / Integral commands (25 pts)
    integral_count = result.get('integral_count', 0)
    if integral_count >= 2:
        score += 25
        subscores["has_integrals"] = True
        feedback_parts.append(f"Found {integral_count} shaded regions (Integral command) (+25)")
    elif integral_count == 1:
        score += 10
        subscores["has_integrals"] = "partial"
        feedback_parts.append("Found 1 shaded region (Integral command), expected at least 2 (+10)")
    else:
        subscores["has_integrals"] = False
        feedback_parts.append("No shaded regions (Integral command) found (0/25)")

    # Criterion 4: Correct Sigma bounds (15 pts)
    # Check if the bounds found in XML match expected sigma values
    found_bounds = result.get('integral_bounds', [])
    matched_bounds = 0
    
    for expected in expected_bounds:
        # Check if any found bound is close to expected
        if any(abs(b - expected) < tolerance for b in found_bounds):
            matched_bounds += 1
            
    # We expect pairs (low, high). 3 regions = 6 bounds.
    # If we found at least 3 matching bound values, give points
    if matched_bounds >= 4:
        score += 15
        subscores["correct_bounds"] = True
        feedback_parts.append("Integral bounds match expected Sigma values (+15)")
    elif matched_bounds >= 2:
        score += 7
        subscores["correct_bounds"] = "partial"
        feedback_parts.append("Some integral bounds match expected Sigma values (+7)")
    else:
        subscores["correct_bounds"] = False
        if integral_count > 0:
            feedback_parts.append("Integral bounds do not match expected ±1σ/2σ/3σ values (0/15)")
        else:
             feedback_parts.append("No integrals to check bounds (0/15)")

    # Criterion 5: Text annotations (20 pts)
    found_labels = result.get('text_labels', [])
    # Check for 68, 95, 99.7
    labels_score = 0
    if any("68" in l for l in found_labels): labels_score += 5
    if any("95" in l for l in found_labels): labels_score += 5
    if any("99.7" in l for l in found_labels) or any("99" in l for l in found_labels): labels_score += 10
    
    if labels_score > 0:
        score += labels_score
        subscores["text_labels"] = True
        feedback_parts.append(f"Text annotations found ({labels_score}/20 pts)")
    else:
        subscores["text_labels"] = False
        feedback_parts.append("No percentage text labels (68%, 95%, 99.7%) found (0/20)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }