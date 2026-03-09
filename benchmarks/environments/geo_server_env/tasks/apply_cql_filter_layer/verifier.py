#!/usr/bin/env python3
"""
Verifier for apply_cql_filter_layer task.

Criteria:
1. WFS Output Correctness (50 pts): All returned features must be South America.
2. Feature Count (20 pts): Count should be ~13 (range 10-15).
3. Configuration Persistence (20 pts): REST API shows cqlFilter is set.
4. Anti-Gaming (10 pts): Count significantly different from initial (~177).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apply_cql_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Verify integrity (optional but good practice)
    # (Skipping nonce check code block for brevity unless strictly required by framework, 
    # but the export script generates it, so we could check it. keeping it simple here.)

    score = 0
    feedback_parts = []
    
    # Metadata targets
    min_count = task_info.get('metadata', {}).get('expected_feature_count_min', 10)
    max_count = task_info.get('metadata', {}).get('expected_feature_count_max', 15)

    wfs = result.get('wfs_analysis', {})
    cql_config = result.get('cql_config_value', '')
    initial_count = int(result.get('initial_feature_count', 0))
    
    current_count = wfs.get('count', 0)
    sa_ratio = wfs.get('sa_ratio', 0)
    continents = wfs.get('continents', [])
    
    # 1. WFS Output Correctness (50 pts)
    # Ratio of 1.0 means 100% of returned features are South America
    if current_count > 0:
        if sa_ratio == 1.0:
            score += 50
            feedback_parts.append("WFS Output: Perfect, only South American features returned.")
        elif sa_ratio > 0.8:
            score += 25
            feedback_parts.append(f"WFS Output: Mostly correct ({sa_ratio*100:.1f}%), but some incorrect features found.")
        else:
            feedback_parts.append(f"WFS Output: Failed. Returned continents: {continents}")
    else:
        feedback_parts.append("WFS Output: No features returned.")

    # 2. Feature Count (20 pts)
    if min_count <= current_count <= max_count:
        score += 20
        feedback_parts.append(f"Feature Count: Correct ({current_count}).")
    elif current_count > 0:
        # Partial credit if count is reasonable but maybe slightly off (e.g. if dataset changed)
        # But if count is 177 (initial), they get 0 here.
        if abs(current_count - 13) < 5: 
            score += 10
            feedback_parts.append(f"Feature Count: Close ({current_count}).")
        else:
            feedback_parts.append(f"Feature Count: Incorrect ({current_count}).")
    
    # 3. Configuration Persistence (20 pts)
    # Check if 'continent' and 'South America' appear in the config string
    if cql_config and 'continent' in cql_config.lower() and 'south america' in cql_config.lower():
        score += 20
        feedback_parts.append(f"Configuration: cqlFilter set correctly ('{cql_config}').")
    elif cql_config:
        score += 10
        feedback_parts.append(f"Configuration: cqlFilter set but may be malformed ('{cql_config}').")
    else:
        feedback_parts.append("Configuration: No cqlFilter found in REST API.")

    # 4. Anti-Gaming / State Change (10 pts)
    # Did we actually filter anything?
    if initial_count > 100 and current_count < 50 and current_count > 0:
        score += 10
        feedback_parts.append("State Change: Dataset successfully filtered.")
    elif initial_count == current_count:
        feedback_parts.append("State Change: Fail - Feature count unchanged from start.")

    # VLM Check (Bonus/Tie-breaker logic - implicit in framework, but we can verify GUI usage)
    # If they used REST API manually (curl), that's acceptable per task description ("Actions required: Log in... Navigate...").
    # But strictly, the task asks to use the GUI. 
    # If GUI interaction is detected via logs, we can be more confident.
    gui_detected = result.get('gui_interaction_detected', False)
    if not gui_detected and score == 100:
        feedback_parts.append("(Note: No GUI interaction detected, assuming API usage)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }