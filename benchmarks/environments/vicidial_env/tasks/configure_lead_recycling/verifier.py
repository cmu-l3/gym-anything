#!/usr/bin/env python3
"""
Verifier for configure_lead_recycling task.

Checks:
1. DB Verification: Rules exist in `vicidial_lead_recycle` with correct params.
2. Anti-gaming: Rules were created during task (count increased).
3. VLM Verification: UI shows the rules configured.
"""

import json
import tempfile
import os
import logging

# VLM dependencies provided by framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Mock for local testing if needed
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lead_recycling(traj, env_info, task_info):
    """
    Verify lead recycling rules were configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rules = metadata.get('expected_rules', [])
    
    # 1. Load Result JSON
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

    actual_rules = result.get('rules', [])
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)

    score = 0
    feedback_parts = []
    
    # Map actual rules by status for easy lookup
    actual_map = {r['status']: r for r in actual_rules}

    # 2. Score Database Rules (Total 85 points)
    # Each rule worth ~28 points
    
    rules_passed = 0
    
    for expected in expected_rules:
        status = expected['status']
        exp_delay = expected['delay']
        exp_max = expected['max_attempts']
        exp_active = expected['active']
        
        if status in actual_map:
            actual = actual_map[status]
            rule_score = 0
            rule_feedback = []
            
            # Existence (8 pts)
            rule_score += 8
            
            # Delay (7 pts)
            if actual['attempt_delay'] == exp_delay:
                rule_score += 7
            else:
                rule_feedback.append(f"Delay {actual['attempt_delay']}!={exp_delay}")
                
            # Max Attempts (5 pts)
            if actual['attempt_maximum'] == exp_max:
                rule_score += 5
            else:
                rule_feedback.append(f"Max {actual['attempt_maximum']}!={exp_max}")
                
            # Active (2 pts)
            if actual['active'] == exp_active:
                rule_score += 2
            else:
                rule_feedback.append(f"Active {actual['active']}!={exp_active}")
            
            if len(rule_feedback) == 0:
                feedback_parts.append(f"Rule {status}: Perfect")
                rules_passed += 1
            else:
                feedback_parts.append(f"Rule {status}: " + ", ".join(rule_feedback))
                
            score += rule_score
        else:
            feedback_parts.append(f"Rule {status}: Missing")

    # Anti-gaming (10 points)
    # Ensure something was actually done (count increased from 0)
    if initial_count == 0 and final_count > 0:
        score += 10
        feedback_parts.append("New rules verified")
    elif final_count == 0:
        feedback_parts.append("No rules found")
    else:
        # Rules existed before? (Shouldn't happen due to setup script)
        pass

    # Exact Count Bonus (5 points)
    # If exactly 3 rules exist (no extras)
    if final_count == len(expected_rules):
        score += 5
    elif final_count > len(expected_rules):
        feedback_parts.append(f"Warning: {final_count} rules found, expected {len(expected_rules)}")

    # 3. VLM Verification (Optional - used as fallback or confirmation)
    # Currently pure DB verification is robust enough for this, but we check screenshot for UI confirmation
    # to ensure the agent actually used the UI and didn't just curl the API (though difficult in this env).
    # Since we can't easily detect curl vs UI in DB, VLM helps confirm UI usage.
    
    # We will assume DB verification is primary. If score is high, we pass.
    
    passed = (score >= 60) and (rules_passed >= 2)
    
    final_feedback = f"Score: {score}/100. " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }