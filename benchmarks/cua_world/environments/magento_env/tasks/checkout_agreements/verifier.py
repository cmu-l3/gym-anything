#!/usr/bin/env python3
"""Verifier for Checkout Agreements task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_checkout_agreements(traj, env_info, task_info):
    """
    Verify checkout agreements configuration and content.
    
    Criteria:
    1. Terms and Conditions feature enabled in config (15 pts)
    2. Agreement 1 (Handmade) created with correct settings and content (40 pts)
    3. Agreement 2 (Privacy) created with correct settings and content (40 pts)
    4. Both agreements assigned to store views (5 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/checkout_agreements_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Config Check (15 pts)
    config_val = str(result.get("config_enabled", "0")).strip()
    if config_val == "1":
        score += 15
        feedback_parts.append("Config enabled (15 pts)")
    else:
        feedback_parts.append(f"Terms & Conditions config NOT enabled (value: {config_val})")

    # 2. Agreement 1 Check (Handmade) (40 pts max)
    a1 = result.get("agreement1", {})
    if a1.get("found"):
        # Basic settings (10 pts)
        is_active = str(a1.get("is_active", "0")) == "1"
        is_html = str(a1.get("is_html", "0")) == "1"
        is_manual = str(a1.get("mode", "0")) == "1"
        
        if is_active and is_html and is_manual:
            score += 10
            feedback_parts.append("Agreement 1 settings correct (10 pts)")
        else:
            feedback_parts.append(f"Agreement 1 settings issue: Active={is_active}, HTML={is_html}, Manual={is_manual}")
            if is_active: score += 3

        # Checkbox text (10 pts)
        text = a1.get("checkbox_text", "").lower()
        if "terms of service" in text and "handmade" in text:
            score += 10
            feedback_parts.append("Agreement 1 checkbox text correct (10 pts)")
        elif "terms of service" in text:
            score += 5
            feedback_parts.append("Agreement 1 checkbox text partial (5 pts)")
        else:
            feedback_parts.append("Agreement 1 checkbox text incorrect")

        # Content (20 pts)
        content = a1.get("content", "").lower()
        reqs = ["<h2", "terms of service", "handmade", "14 days"]
        # Allow 2-4 weeks or 2 to 4 weeks
        time_ok = "2-4 weeks" in content or "2 to 4 weeks" in content
        
        matches = sum(1 for r in reqs if r in content)
        if time_ok: matches += 1
        
        content_score = matches * 4 # 5 items * 4 pts = 20 pts
        score += content_score
        if content_score == 20:
             feedback_parts.append("Agreement 1 content correct (20 pts)")
        else:
             feedback_parts.append(f"Agreement 1 content missing elements ({content_score}/20 pts)")
    else:
        feedback_parts.append("Agreement 1 ('Handmade Goods') NOT found")

    # 3. Agreement 2 Check (Privacy) (40 pts max)
    a2 = result.get("agreement2", {})
    if a2.get("found"):
        # Basic settings (10 pts)
        is_active = str(a2.get("is_active", "0")) == "1"
        is_html = str(a2.get("is_html", "0")) == "1"
        is_manual = str(a2.get("mode", "0")) == "1"
        
        if is_active and is_html and is_manual:
            score += 10
            feedback_parts.append("Agreement 2 settings correct (10 pts)")
        else:
            feedback_parts.append(f"Agreement 2 settings issue: Active={is_active}, HTML={is_html}, Manual={is_manual}")
            if is_active: score += 3

        # Checkbox text (10 pts)
        text = a2.get("checkbox_text", "").lower()
        if "privacy" in text and "data" in text:
            score += 10
            feedback_parts.append("Agreement 2 checkbox text correct (10 pts)")
        elif "privacy" in text:
            score += 5
            feedback_parts.append("Agreement 2 checkbox text partial (5 pts)")
        else:
            feedback_parts.append("Agreement 2 checkbox text incorrect")

        # Content (20 pts)
        content = a2.get("content", "").lower()
        reqs = ["<h2", "privacy policy", "data", "cookie"]
        matches = sum(1 for r in reqs if r in content)
        
        content_score = matches * 5 # 4 items * 5 pts = 20 pts
        score += content_score
        if content_score == 20:
             feedback_parts.append("Agreement 2 content correct (20 pts)")
        else:
             feedback_parts.append(f"Agreement 2 content missing elements ({content_score}/20 pts)")
    else:
        feedback_parts.append("Agreement 2 ('Privacy Policy') NOT found")

    # 4. Store Assignment (5 pts)
    # Both must be assigned to at least one store (usually store_id=0 for All Store Views)
    s1 = int(a1.get("store_count", 0))
    s2 = int(a2.get("store_count", 0))
    if s1 > 0 and s2 > 0:
        score += 5
        feedback_parts.append("Store assignment correct (5 pts)")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }