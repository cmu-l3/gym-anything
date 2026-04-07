#!/usr/bin/env python3
"""
Verifier for Accessibility Terminal Config task.

Scoring Breakdown (100 points total):
1.  Settings (60 pts):
    - Default Font Size >= 20px (20 pts)
    - Minimum Font Size >= 16px (20 pts)
    - Homepage set to usa.gov (15 pts)
    - Home Button Enabled (5 pts)
2.  Verification (10 pts):
    - Visited usa.gov AND ssa.gov after task start (5 pts each)
3.  Documentation (30 pts):
    - File exists and modified after start (10 pts)
    - Mentions "font" and "size" (5 pts)
    - Mentions "usa.gov" (5 pts)
    - Content length > 100 chars (10 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_accessibility_config(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    prefs = result.get("prefs", {})
    history = result.get("history", [])
    doc = result.get("doc", {})
    
    # --- 1. SETTINGS VERIFICATION (60 pts) ---
    
    # Font Size (Default >= 20)
    actual_default_font = prefs.get("default_font_size", 16)
    if actual_default_font >= 20:
        score += 20
        feedback.append(f"✓ Default font size is {actual_default_font}px (>=20px)")
    else:
        feedback.append(f"✗ Default font size is {actual_default_font}px (Required: >=20px)")

    # Min Font Size (Min >= 16)
    actual_min_font = prefs.get("minimum_font_size", 0)
    if actual_min_font >= 16:
        score += 20
        feedback.append(f"✓ Minimum font size is {actual_min_font}px (>=16px)")
    else:
        feedback.append(f"✗ Minimum font size is {actual_min_font}px (Required: >=16px)")

    # Homepage URL
    homepage = prefs.get("homepage", "").lower()
    if "usa.gov" in homepage:
        score += 15
        feedback.append("✓ Homepage set to usa.gov")
    else:
        feedback.append(f"✗ Homepage is '{homepage}' (Required: usa.gov)")

    # Home Button
    if prefs.get("show_home_button") is True:
        score += 5
        feedback.append("✓ Home button enabled")
    else:
        feedback.append("✗ Home button not enabled")

    # --- 2. HISTORY VERIFICATION (10 pts) ---
    
    visited_usa = any("usa.gov" in h["url"] for h in history)
    visited_ssa = any("ssa.gov" in h["url"] for h in history)
    
    if visited_usa:
        score += 5
        feedback.append("✓ Verified settings on usa.gov")
    else:
        feedback.append("✗ Did not visit usa.gov to verify settings")
        
    if visited_ssa:
        score += 5
        feedback.append("✓ Verified settings on ssa.gov")
    else:
        feedback.append("✗ Did not visit ssa.gov to verify settings")

    # --- 3. DOCUMENTATION VERIFICATION (30 pts) ---
    
    if doc.get("exists") and doc.get("modified_after_start"):
        score += 10
        feedback.append("✓ Reference document created")
        
        content = doc.get("content", "").lower()
        
        # Content Check: Mentions font settings
        if "font" in content and "size" in content:
            score += 5
            feedback.append("✓ Document mentions font size settings")
        else:
            feedback.append("✗ Document missing font size details")
            
        # Content Check: Mentions homepage
        if "usa.gov" in content:
            score += 5
            feedback.append("✓ Document mentions homepage URL")
        else:
            feedback.append("✗ Document missing homepage URL")
            
        # Content Check: Substantive content
        if len(content) > 100:
            score += 10
            feedback.append("✓ Document is comprehensive")
        else:
            feedback.append("✗ Document is too short (<100 chars)")
    else:
        feedback.append("✗ Reference document missing or created before task start")

    # Pass Threshold
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }