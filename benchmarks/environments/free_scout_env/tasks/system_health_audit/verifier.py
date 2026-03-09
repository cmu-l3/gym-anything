#!/usr/bin/env python3
"""
Verifier for system_health_audit task.
Compares agent's extracted JSON data against programmatic ground truth.
"""

import json
import tempfile
import os
import re

def normalize_version(v_str):
    """Normalize version string for fuzzy comparison."""
    if not v_str:
        return ""
    # Remove common prefixes/suffixes like "v", "-cli", "-MariaDB"
    v = str(v_str).lower().strip()
    # Extract the main version number pattern (e.g., "1.2.3")
    match = re.search(r'(\d+(\.\d+)+)', v)
    if match:
        return match.group(1)
    return v

def check_version_match(agent_val, gt_val, label):
    """
    Check if agent version matches ground truth.
    Returns (score, feedback_string)
    """
    if not agent_val:
        return 0, f"{label} missing"
    
    norm_agent = normalize_version(agent_val)
    norm_gt = normalize_version(gt_val)
    
    # Exact match of normalized strings
    if norm_agent == norm_gt:
        return 1.0, f"{label} correct ({agent_val})"
    
    # Substring match (e.g. "10.11" in "10.11.6")
    if norm_gt.startswith(norm_agent) or norm_agent.startswith(norm_gt):
        return 0.9, f"{label} mostly correct ({agent_val} vs {gt_val})"
        
    return 0, f"{label} incorrect (Got: '{agent_val}', Expected: '{gt_val}')"

def verify_system_health_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # 1. File Existence & Validity (30 pts)
    if result.get('file_exists'):
        score += 20
        feedback_parts.append("File created")
        if result.get('valid_json'):
            score += 10
            feedback_parts.append("Valid JSON")
        else:
            feedback_parts.append("Invalid JSON format")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Content Verification (70 pts)
    agent_data = result.get('agent_output', {})
    ground_truth = result.get('ground_truth', {})
    
    # FreeScout Version (20 pts)
    s, f = check_version_match(agent_data.get('freescout_version'), ground_truth.get('freescout_version'), "FreeScout Ver")
    score += s * 20
    feedback_parts.append(f)
    
    # PHP Version (20 pts)
    s, f = check_version_match(agent_data.get('php_version'), ground_truth.get('php_version'), "PHP Ver")
    score += s * 20
    feedback_parts.append(f)
    
    # Database Version (15 pts)
    s, f = check_version_match(agent_data.get('database_version'), ground_truth.get('database_version'), "DB Ver")
    score += s * 15
    feedback_parts.append(f)
    
    # Timezone (15 pts)
    agent_tz = str(agent_data.get('timezone', '')).strip()
    gt_tz = str(ground_truth.get('timezone', '')).strip()
    if agent_tz.lower() == gt_tz.lower():
        score += 15
        feedback_parts.append(f"Timezone correct ({agent_tz})")
    elif agent_tz:
        # Check for UTC/GMT equivalence or standard variations
        if 'UTC' in agent_tz.upper() and 'UTC' in gt_tz.upper():
             score += 15
             feedback_parts.append(f"Timezone correct ({agent_tz})")
        else:
             feedback_parts.append(f"Timezone mismatch (Got: {agent_tz}, Exp: {gt_tz})")
    else:
        feedback_parts.append("Timezone missing")

    # Anti-gaming: File creation time
    if not result.get('file_created_during_task'):
        feedback_parts.append("WARNING: File timestamp too old")
        score = max(0, score - 20)

    return {
        "passed": score >= 70,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }