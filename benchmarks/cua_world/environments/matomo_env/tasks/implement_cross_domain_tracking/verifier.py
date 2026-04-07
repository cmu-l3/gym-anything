#!/usr/bin/env python3
import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_b64(b64_str):
    try:
        return base64.b64decode(b64_str).decode('utf-8')
    except Exception:
        return ""

def verify_cross_domain_tracking(traj, env_info, task_info):
    """
    Verify cross-domain tracking implementation.
    1. Check code in landing.html and shop.html (Static Analysis).
    2. Check if a real cross-domain visit was recorded (Functional Check).
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Static Code Analysis
    landing_code = decode_b64(result.get('landing_content_b64', ''))
    shop_code = decode_b64(result.get('shop_content_b64', ''))
    
    # Check Landing Page
    landing_score = 0
    if "setDomains" in landing_code and "enableCrossDomainLinking" in landing_code:
        landing_score += 40
        feedback.append("Landing page code looks correct (+40).")
    elif "setDomains" in landing_code:
        landing_score += 20
        feedback.append("Landing page has setDomains but missing enableCrossDomainLinking (+20).")
    elif "enableCrossDomainLinking" in landing_code:
        landing_score += 10
        feedback.append("Landing page has enableCrossDomainLinking but missing setDomains (+10).")
    else:
        feedback.append("Landing page code not updated.")
    
    # Check Shop Page (less weight as it's repetitive)
    shop_score = 0
    if "setDomains" in shop_code and "enableCrossDomainLinking" in shop_code:
        shop_score += 20
        feedback.append("Shop page code looks correct (+20).")
    elif "setDomains" in shop_code or "enableCrossDomainLinking" in shop_code:
        shop_score += 10
        feedback.append("Shop page code partially updated (+10).")
    else:
        feedback.append("Shop page code not updated.")

    # Check setDomains content specifically (anti-gaming: strictly checking array content is hard with regex, 
    # relying on presence + functional check)
    if "localhost" not in landing_code or "127.0.0.1" not in landing_code:
        landing_score = max(0, landing_score - 10)
        feedback.append("Landing page setDomains missing required domains (-10).")

    score += landing_score + shop_score

    # 2. Functional Verification (Database)
    # Did the agent actually test it and generate a linked session?
    cross_domain_visits = result.get('cross_domain_visits', 0)
    
    # Handle string/int conversion safety
    try:
        if isinstance(cross_domain_visits, str):
            # If query returned "1\n2", take the count
            cross_domain_visits = len(cross_domain_visits.strip().split('\n')) if cross_domain_visits.strip() else 0
        else:
            cross_domain_visits = int(cross_domain_visits)
    except:
        cross_domain_visits = 0

    if cross_domain_visits > 0:
        score += 40
        feedback.append(f"Functional verification passed: {cross_domain_visits} cross-domain visit(s) recorded (+40).")
    else:
        feedback.append("Functional verification failed: No visit found spanning both 'localhost' and '127.0.0.1'. Did you test your changes?")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }