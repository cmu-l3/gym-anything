#!/usr/bin/env python3
"""
Verifier for build_financial_summary_dashboard task.

This verifier uses TiddlyWiki's Node.js rendering engine to evaluate the agent's
tiddler dynamically. It performs a baseline render, injects a new mock transaction,
and performs a second render to absolutely guarantee that the agent used dynamic 
filter math instead of hardcoding the totals.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_financial_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Initial totals from seeded data
    init_contrib = str(metadata.get('initial_contrib', 6150))
    init_exp = str(metadata.get('initial_exp', 2450))
    init_net = str(metadata.get('initial_net', 3700))
    
    # Updated totals after dummy $10,000 contribution
    dyn_contrib = str(metadata.get('dynamic_contrib', 16150))
    dyn_exp = str(metadata.get('dynamic_exp', 2450))
    dyn_net = str(metadata.get('dynamic_net', 13700))

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
    
    tiddler_found = result.get('tiddler_found', False)
    raw_text = result.get('raw_text', '')
    rendered_initial = result.get('rendered_initial', '')
    rendered_dynamic = result.get('rendered_dynamic', '')

    # CRITERION 1: Tiddler Exists (10 points)
    if tiddler_found:
        score += 10
        feedback_parts.append("Tiddler 'Financial Summary Report' found")
    else:
        feedback_parts.append("FAIL: Target tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Evidence of Dynamic Syntax in Raw Text (30 points)
    # Checks that the user actually used filters and widgets rather than just typing 6150.
    syntax_score = 0
    if 'sum[' in raw_text:
        syntax_score += 10
    if 'subtract[' in raw_text or '-' in raw_text:
        syntax_score += 10
    if 'get[amount]' in raw_text or 'get{amount}' in raw_text or '!!amount' in raw_text:
        syntax_score += 10
        
    score += syntax_score
    if syntax_score == 30:
        feedback_parts.append("Dynamic filter math syntax detected")
    elif syntax_score > 0:
        feedback_parts.append(f"Partial dynamic syntax detected ({syntax_score}/30)")
    else:
        feedback_parts.append("WARNING: No standard filter math syntax found in raw wikitext")

    # CRITERION 3: Baseline Initial Render Values Correct (30 points)
    # Renders the initial seeded data exactly as requested
    initial_correct = 0
    if init_contrib in rendered_initial or f"{init_contrib[:1]},{init_contrib[1:]}" in rendered_initial:
        initial_correct += 10
    if init_exp in rendered_initial or f"{init_exp[:1]},{init_exp[1:]}" in rendered_initial:
        initial_correct += 10
    if init_net in rendered_initial or f"{init_net[:1]},{init_net[1:]}" in rendered_initial:
        initial_correct += 10

    score += initial_correct
    if initial_correct == 30:
        feedback_parts.append("Baseline math totals calculated correctly")
    elif initial_correct > 0:
        feedback_parts.append(f"Partial baseline math match ({initial_correct}/30)")
    else:
        feedback_parts.append("FAIL: Did not calculate initial math totals correctly")

    # CRITERION 4: Dynamic Re-Render Values Correct (30 points)
    # This completely blocks "hardcoding" gaming because the export script
    # secretly added a $10,000 contribution and forced a re-render.
    dynamic_correct = 0
    if dyn_contrib in rendered_dynamic or f"{dyn_contrib[:2]},{dyn_contrib[2:]}" in rendered_dynamic:
        dynamic_correct += 10
    if dyn_exp in rendered_dynamic or f"{dyn_exp[:1]},{dyn_exp[1:]}" in rendered_dynamic:
        dynamic_correct += 10
    if dyn_net in rendered_dynamic or f"{dyn_net[:2]},{dyn_net[2:]}" in rendered_dynamic:
        dynamic_correct += 10

    score += dynamic_correct
    if dynamic_correct == 30:
        feedback_parts.append("Dynamic automatic recalculation verified perfectly (Anti-gaming passed)")
    elif dynamic_correct > 0:
        feedback_parts.append(f"Partial dynamic recalculation verified ({dynamic_correct}/30)")
    else:
        if initial_correct == 30:
            feedback_parts.append("FAIL: Values did not dynamically update (Hardcoded text suspected)")
        else:
            feedback_parts.append("FAIL: Dynamic recalculation failed")

    # Pass logic: Needs strong score and proven dynamic updating
    is_passed = (score >= 80) and (dynamic_correct >= 20)

    return {
        "passed": is_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }