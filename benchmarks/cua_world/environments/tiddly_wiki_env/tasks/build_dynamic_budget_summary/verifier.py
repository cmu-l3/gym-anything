#!/usr/bin/env python3
"""Verifier for build_dynamic_budget_summary task."""

import json
import tempfile
import os
import re


def contains_number(text, number):
    """Check if a specific number appears in the text, accounting for formatting like commas."""
    if not text:
        return False
    
    # Looking for exact match of the number or comma-separated version
    num_str = str(number)
    formatted_num_str = f"{number:,}"
    
    # We use regex to ensure it's a discrete number, not part of a larger number
    # (e.g., 800 shouldn't match 5800)
    pattern1 = r'(?<![\d,])' + re.escape(num_str) + r'(?![\d,])'
    pattern2 = r'(?<![\d,])' + re.escape(formatted_num_str) + r'(?![\d,])'
    
    return bool(re.search(pattern1, text)) or bool(re.search(pattern2, text))


def verify_budget_summary(traj, env_info, task_info):
    """Verify the dynamic budget dashboard."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    initial_total = metadata.get('initial_total', 2560)
    initial_flight = metadata.get('initial_flight', 1200)
    initial_accomm = metadata.get('initial_accommodation', 800)
    initial_transport = metadata.get('initial_transport', 400)
    initial_activity = metadata.get('initial_activity', 110)
    
    final_total = metadata.get('final_total', 7560)
    final_activity = metadata.get('final_activity', 5110)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/budget_summary_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Tiddler exists and has Dashboard tag (10 pts)
    if result.get('tiddler_found'):
        score += 5
        feedback_parts.append("Tiddler found")
        
        tags = result.get('tiddler_tags', '')
        if 'Dashboard' in tags or 'dashboard' in tags.lower():
            score += 5
            feedback_parts.append("Dashboard tag found")
        else:
            feedback_parts.append("FAIL: Dashboard tag missing")
    else:
        feedback_parts.append("FAIL: Target tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Uses sum filter in raw text (20 pts)
    if result.get('uses_sum_filter'):
        score += 20
        feedback_parts.append("Uses 'sum[]' filter operator")
    else:
        raw_text = result.get('raw_text', '')
        if 'sum' in raw_text and 'cost' in raw_text:
            score += 10
            feedback_parts.append("Found filter keywords, but syntax might be imperfect")
        else:
            feedback_parts.append("FAIL: Did not use 'sum[]' filter operator (possible hardcoding)")

    # Analyze Initial Render
    initial_render = result.get('initial_render_text', '')
    final_render = result.get('final_render_text', '')
    
    # Criterion 3: Initial Total calculated correctly (10 pts)
    if contains_number(initial_render, initial_total):
        score += 10
        feedback_parts.append(f"Initial total correct ({initial_total})")
    else:
        feedback_parts.append(f"FAIL: Initial total {initial_total} not found in output")

    # Criterion 4: Initial Subtotals calculated correctly (20 pts)
    subtotals = [
        ("Flight", initial_flight), 
        ("Accommodation", initial_accomm), 
        ("Transport", initial_transport), 
        ("Activity", initial_activity)
    ]
    
    subs_found = 0
    for name, val in subtotals:
        if contains_number(initial_render, val):
            subs_found += 1
            
    if subs_found == 4:
        score += 20
        feedback_parts.append("All 4 initial subtotals correct")
    elif subs_found > 0:
        score += (subs_found * 5)
        feedback_parts.append(f"{subs_found}/4 initial subtotals correct")
    else:
        feedback_parts.append("FAIL: Initial subtotals not found or incorrect")

    # Criterion 5 & 6: Anti-Gaming Dynamic Math Update (40 pts)
    # The verifier script injected a hidden $5000 Activity expense. 
    # If the filter is dynamic, both the Total and the Activity subtotal will reflect this.
    
    dynamic_total = contains_number(final_render, final_total)
    dynamic_activity = contains_number(final_render, final_activity)
    
    if dynamic_total:
        score += 20
        feedback_parts.append(f"Dynamic math verified: Total updated to {final_total}")
    else:
        feedback_parts.append("FAIL: Total did not dynamically update upon data injection (Hardcoded values?)")
        
    if dynamic_activity:
        score += 20
        feedback_parts.append(f"Dynamic math verified: Activity subtotal updated to {final_activity}")
    else:
        feedback_parts.append("FAIL: Category subtotal did not dynamically update")

    # Final logic
    passed = score >= 70 and (dynamic_total or dynamic_activity)
    
    if not passed and score >= 70:
        feedback_parts.append("FAILED: Did not pass anti-gaming dynamic check.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }