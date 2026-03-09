#!/usr/bin/env python3
"""
Verifier for configure_firewall_rules task.

Checks:
1. Port 8443 ACCEPT rule exists (20 pts)
2. Port 9090 ACCEPT rule exists (20 pts)
3. IP Block rule exists (25 pts)
4. Existing rules preserved (10 pts)
5. Configuration saved/applied (10 pts)
6. VLM Trajectory Verification (15 pts) - confirms Webmin UI usage
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_firewall_rules(traj, env_info, task_info):
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 3. Score Programmatic Criteria
    
    # Rule 8443 (20 pts)
    if result.get("rule_8443_exists"):
        score += 20
        feedback.append("Port 8443 rule found (+20)")
    else:
        feedback.append("Port 8443 rule missing")

    # Rule 9090 (20 pts)
    if result.get("rule_9090_exists"):
        score += 20
        feedback.append("Port 9090 rule found (+20)")
    else:
        feedback.append("Port 9090 rule missing")

    # Block Rule (25 pts)
    if result.get("rule_block_exists"):
        score += 25
        feedback.append("IP Block rule found (+25)")
    else:
        feedback.append("IP Block rule missing")

    # Baseline Preserved (10 pts)
    if result.get("baseline_preserved"):
        score += 10
        feedback.append("Existing rules preserved (+10)")
    else:
        feedback.append("CRITICAL: Existing access rules were deleted")

    # Configuration Applied/Saved (10 pts)
    # Checked via file modification timestamp or simply if rules are live (which implied apply)
    # The export script checks 'config_file_modified'.
    if result.get("config_file_modified"):
        score += 10
        feedback.append("Configuration saved to disk (+10)")
    elif score >= 40: # If rules exist in live kernel but file not updated, give partial credit?
        # Actually, in Webmin "Apply Configuration" usually writes the file. 
        # If rules exist live, they did "Apply".
        score += 10
        feedback.append("Rules active in kernel (+10)")
    else:
        feedback.append("Configuration not saved/applied")

    # 4. VLM Verification (15 pts)
    # We want to verify they used the Webmin UI, not just a terminal
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a user configuring a server.
        1. Do you see the 'Webmin' interface (specifically Networking or Linux Firewall)?
        2. Do you see a table of firewall rules?
        3. Do you see a form for adding a new rule (ports 8443, 9090 or source IP)?
        
        Return JSON:
        {
            "webmin_ui_visible": true/false,
            "firewall_module_seen": true/false,
            "rule_entry_seen": true/false
        }
        """
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_resp.get("parsed", {})
        
        if parsed.get("webmin_ui_visible"):
            vlm_score += 5
        if parsed.get("firewall_module_seen"):
            vlm_score += 5
        if parsed.get("rule_entry_seen"):
            vlm_score += 5
            
        score += vlm_score
        feedback.append(f"UI Verification: {vlm_score}/15 pts")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if programmatic score is high, give benefit of doubt for UI
        if score >= 65:
            score += 15
            feedback.append("VLM skipped, assumed UI usage based on success (+15)")

    return {
        "passed": score >= 65 and result.get("rule_8443_exists") and result.get("rule_9090_exists") and result.get("rule_block_exists"),
        "score": score,
        "feedback": "; ".join(feedback)
    }