#!/usr/bin/env python3
"""
Verifier for update_opportunity_details task.

Checks if the agent correctly updated the opportunity fields:
1. Expected Revenue: $75,000
2. Probability: 60%
3. Priority: High (2 stars)
4. Tag: "Enterprise"

Also checks for anti-gaming (record actually modified during task).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_opportunity_details(traj, env_info, task_info):
    """
    Verify the Odoo opportunity update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get target values from metadata
    metadata = task_info.get('metadata', {})
    target_revenue = metadata.get('target_revenue', 75000.0)
    target_probability = metadata.get('target_probability', 60.0)
    target_priority = metadata.get('target_priority', "2")
    target_tag = metadata.get('target_tag', "Enterprise")

    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic errors
    if "error" in result:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Task failed: {result['error']}"
        }

    score = 0
    feedback_parts = []
    
    # Current values from agent's work
    actual_revenue = result.get('expected_revenue', 0.0)
    actual_probability = result.get('probability', 0.0)
    actual_priority = str(result.get('priority', '0'))
    actual_tags = result.get('tag_names', [])
    write_ts = result.get('write_timestamp', 0)
    task_start = result.get('task_start', 0)

    # 1. Check Revenue (25 pts)
    # Allow small float tolerance
    if abs(float(actual_revenue) - float(target_revenue)) < 1.0:
        score += 25
        feedback_parts.append(f"Revenue updated correctly (${actual_revenue})")
    else:
        feedback_parts.append(f"Revenue incorrect (expected ${target_revenue}, got ${actual_revenue})")

    # 2. Check Probability (25 pts)
    if abs(float(actual_probability) - float(target_probability)) < 1.0:
        score += 25
        feedback_parts.append(f"Probability updated correctly ({actual_probability}%)")
    else:
        feedback_parts.append(f"Probability incorrect (expected {target_probability}%, got {actual_probability}%)")

    # 3. Check Priority (25 pts)
    if actual_priority == target_priority:
        score += 25
        feedback_parts.append(f"Priority updated correctly ({actual_priority} stars)")
    else:
        feedback_parts.append(f"Priority incorrect (expected {target_priority}, got {actual_priority})")

    # 4. Check Tags (25 pts)
    # Case-insensitive check
    tag_found = any(t.lower() == target_tag.lower() for t in actual_tags)
    if tag_found:
        score += 25
        feedback_parts.append(f"Tag '{target_tag}' added")
    else:
        feedback_parts.append(f"Tag '{target_tag}' missing (found: {actual_tags})")

    # Anti-gaming: "Do Nothing" Check
    # If all values match initial state, force fail
    initial_revenue = metadata.get('initial_revenue', 25000.0)
    initial_prob = metadata.get('initial_probability', 20.0)
    
    is_initial_state = (
        abs(float(actual_revenue) - float(initial_revenue)) < 1.0 and
        abs(float(actual_probability) - float(initial_prob)) < 1.0 and
        actual_priority == "0" and
        not actual_tags
    )
    
    if is_initial_state:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected. The opportunity is still in its initial state."
        }

    # Anti-gaming: Timestamp Check
    # Verify the record was modified *after* task start
    # Odoo timestamps can be tricky with timezones, so we use a loose check
    # If write_ts is 0 or significantly before task_start, warn/penalize
    if write_ts > 0 and write_ts < task_start:
         feedback_parts.append("WARNING: Record modification time is before task start.")
         # We won't fail completely on this due to potential clock skew/timezone issues in docker
         # but it's a strong signal for review

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }