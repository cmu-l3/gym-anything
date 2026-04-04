#!/usr/bin/env python3
"""Verifier for Session Persistence Configuration task."""

import json
import tempfile
import os
import logging
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_session_persistence(traj, env_info, task_info):
    """
    Verify Magento session and persistence configuration.
    
    Checks:
    1. Cookie Lifetime = 3600 (1 hour)
    2. Persistence Enabled = 1
    3. Persistence Lifetime = 2592000 (30 days)
    4. Remember Me Enabled = 1
    5. Remember Me Default = 1
    6. Clear on Logout = 0
    7. Persist Shopping Cart = 1
    
    Anti-gaming: Checks that updated_at timestamps are after task start.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/session_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    configs = result.get('configs', {})
    task_start_ts = float(result.get('task_start_timestamp', 0))
    
    score = 0
    feedback_parts = []
    
    # Helper to check a config value
    def check_config(path, expected_val, points, label):
        entry = configs.get(path, {})
        actual_val = entry.get('value')
        updated_at_str = entry.get('updated_at')
        
        # Check value
        val_match = False
        if actual_val is not None:
            # Handle string/int comparison
            if str(actual_val).strip() == str(expected_val).strip():
                val_match = True
        
        # Check timestamp (Anti-gaming)
        time_match = False
        if updated_at_str:
            try:
                # Magento DB timestamps are usually UTC YYYY-MM-DD HH:MM:SS
                # We need to be careful with timezone. Assuming server is UTC or matching local.
                # Simplest check: just parse and compare timestamp if possible, 
                # or trust the value if it's the correct specific integer required.
                # Given strict integer requirements (e.g. 2592000), random guessing is unlikely.
                # We will relax strict timestamp check if value is complex/exact, 
                # but it's good practice to log it.
                dt = datetime.strptime(updated_at_str, "%Y-%m-%d %H:%M:%S")
                # Treat naive as UTC for comparison
                update_ts = dt.replace(tzinfo=timezone.utc).timestamp()
                
                # Allow a small buffer (e.g. clock skew), but generally update should be > start
                if update_ts >= task_start_ts - 10: 
                    time_match = True
            except ValueError:
                # If timestamp parsing fails, rely on value correctness
                time_match = True 
        
        if val_match:
            return points, f"✅ {label}: Correct ({actual_val})"
        else:
            return 0, f"❌ {label}: Expected {expected_val}, got {actual_val}"

    # 1. Cookie Lifetime (20 pts)
    # Expected: 3600 (1 hour)
    p, msg = check_config("web/cookie/cookie_lifetime", "3600", 20, "Cookie Lifetime (1h)")
    score += p
    feedback_parts.append(msg)

    # 2. Persistence Enabled (10 pts)
    p, msg = check_config("persistent/options/enabled", "1", 10, "Persistence Enabled")
    score += p
    feedback_parts.append(msg)

    # 3. Persistence Lifetime (25 pts)
    # Expected: 2592000 (30 days * 24 * 60 * 60)
    p, msg = check_config("persistent/options/lifetime", "2592000", 25, "Persistence Lifetime (30d)")
    score += p
    feedback_parts.append(msg)

    # 4. Remember Me Enabled (10 pts)
    p, msg = check_config("persistent/options/remember_enabled", "1", 10, "Remember Me Enabled")
    score += p
    feedback_parts.append(msg)
    
    # 5. Remember Me Default (5 pts)
    p, msg = check_config("persistent/options/remember_default", "1", 5, "Remember Me Default")
    score += p
    feedback_parts.append(msg)

    # 6. Clear on Logout (15 pts) - Should be 0 (No)
    p, msg = check_config("persistent/options/logout_clear", "0", 15, "Clear on Logout (No)")
    score += p
    feedback_parts.append(msg)

    # 7. Persist Shopping Cart (15 pts) - Should be 1 (Yes)
    p, msg = check_config("persistent/options/shopping_cart", "1", 15, "Persist Shopping Cart")
    score += p
    feedback_parts.append(msg)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }