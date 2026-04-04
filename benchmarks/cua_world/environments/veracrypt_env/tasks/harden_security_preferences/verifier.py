#!/usr/bin/env python3
"""
Verifier for harden_security_preferences task.

Verification Strategy:
1. Parse VeraCrypt's Configuration.xml to verify 6 specific security settings.
2. Verify existence and content of compliance report file.
3. Anti-gaming: Check that config file was modified AFTER task start.

Scoring Breakdown (100 pts):
- 12 pts: CachePasswords disabled
- 12 pts: DismountOnInactivity enabled
- 15 pts: MaxVolumeIdleTime set to 15
- 12 pts: ForceAutoDismount enabled
- 12 pts: WipeCacheOnAutoDismount enabled
- 12 pts: WipeCacheOnClose enabled
- 10 pts: Compliance report exists (>100 bytes)
- 10 pts: Compliance report content check (keywords)
- 5 pts:  Anti-gaming (Config modified during task)
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_harden_security_preferences(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected settings from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {
        "CachePasswords": "0",
        "DismountOnInactivity": "1",
        "MaxVolumeIdleTime": "15",
        "ForceAutoDismount": "1",
        "WipeCacheOnAutoDismount": "1",
        "WipeCacheOnClose": "1"
    })

    score = 0
    feedback_parts = []
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Anti-Gaming: Check Config Modification Time
    task_start = result.get('task_start', 0)
    config_mtime = result.get('config_mtime', 0)
    config_values = result.get('config_values', {})
    
    if not result.get('config_found'):
        return {"passed": False, "score": 0, "feedback": "VeraCrypt configuration file not found."}
        
    if config_mtime > task_start:
        score += 5
        feedback_parts.append("Config modified during task")
    else:
        feedback_parts.append("Warning: Configuration not saved during task session")

    # 2. Check Individual Settings (75 points total)
    settings_score = 0
    
    # CachePasswords (0 = Disabled) - 12 pts
    if config_values.get("CachePasswords") == expected["CachePasswords"]:
        settings_score += 12
        feedback_parts.append("CachePasswords disabled")
    else:
        feedback_parts.append(f"CachePasswords incorrect ({config_values.get('CachePasswords')})")

    # DismountOnInactivity (1 = Enabled) - 12 pts
    if config_values.get("DismountOnInactivity") == expected["DismountOnInactivity"]:
        settings_score += 12
        feedback_parts.append("Auto-dismount enabled")
    else:
        feedback_parts.append("Auto-dismount not enabled")

    # MaxVolumeIdleTime (15) - 15 pts
    # Allow string "15" or integer 15
    if str(config_values.get("MaxVolumeIdleTime")) == expected["MaxVolumeIdleTime"]:
        settings_score += 15
        feedback_parts.append("Idle timeout set to 15m")
    else:
        feedback_parts.append(f"Idle timeout incorrect ({config_values.get('MaxVolumeIdleTime')})")

    # ForceAutoDismount (1 = Enabled) - 12 pts
    if config_values.get("ForceAutoDismount") == expected["ForceAutoDismount"]:
        settings_score += 12
        feedback_parts.append("Force auto-dismount enabled")
    else:
        feedback_parts.append("Force auto-dismount not enabled")

    # WipeCacheOnAutoDismount (1 = Enabled) - 12 pts
    if config_values.get("WipeCacheOnAutoDismount") == expected["WipeCacheOnAutoDismount"]:
        settings_score += 12
        feedback_parts.append("Wipe cache on auto-dismount enabled")
    else:
        feedback_parts.append("Wipe cache on auto-dismount not enabled")

    # WipeCacheOnClose (1 = Enabled) - 12 pts
    if config_values.get("WipeCacheOnClose") == expected["WipeCacheOnClose"]:
        settings_score += 12
        feedback_parts.append("Wipe cache on exit enabled")
    else:
        feedback_parts.append("Wipe cache on exit not enabled")

    score += settings_score

    # 3. Check Compliance Report (20 pts)
    report_exists = result.get("report_exists", False)
    report_size = result.get("report_size", 0)
    report_content = result.get("report_content_preview", "").lower()
    
    if report_exists and report_size > 50: # Minimal check for non-empty file
        score += 10
        feedback_parts.append("Compliance report created")
        
        # Check for keywords in report content
        keywords_found = 0
        required_keywords = ["cache", "dismount", "15", "force", "wipe", "exit"]
        found_words = []
        for kw in required_keywords:
            if kw in report_content:
                keywords_found += 1
                found_words.append(kw)
        
        # Need substantial content for full points
        if keywords_found >= 4:
            score += 10
            feedback_parts.append("Report content accurate")
        elif keywords_found >= 1:
            score += 5
            feedback_parts.append("Report content partial")
        else:
            feedback_parts.append("Report content missing key details")
            
    else:
        feedback_parts.append("Compliance report missing or empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }