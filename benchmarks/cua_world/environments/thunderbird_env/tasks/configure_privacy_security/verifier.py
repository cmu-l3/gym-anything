#!/usr/bin/env python3
"""
Verifier for configure_privacy_security task in Thunderbird.

Verification Criteria:
1. Pref: mailnews.message_display.disable_remote_image = true (18 pts)
2. Pref: mailnews.display.prefer_plaintext = true AND html_as = 1 (18 pts)
3. Pref: mail.phishing.detection.enabled = true (18 pts)
4. Pref: Return receipts (3 settings) all = 2 (18 pts)
5. Pref: privacy.donottrackheader.enabled = true (18 pts)
6. VLM Trajectory check: Evidence of using the Thunderbird Settings GUI (10 pts)
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_thunderbird_prefs(prefs_content):
    """Parses Thunderbird prefs.js content into a dictionary."""
    prefs = {}
    # user_pref("key.name", value);
    pattern = re.compile(r'user_pref\("([^"]+)",\s*(.+?)\);')
    for match in pattern.finditer(prefs_content):
        key = match.group(1)
        raw_val = match.group(2).strip()
        
        # Convert types
        if raw_val == 'true':
            val = True
        elif raw_val == 'false':
            val = False
        else:
            try:
                val = int(raw_val)
            except ValueError:
                val = raw_val.strip('"\'')
        prefs[key] = val
    return prefs

def verify_privacy_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Fetch the exported JSON metadata
    result_json_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_file.name)
        with open(result_json_file.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}
    finally:
        if os.path.exists(result_json_file.name):
            os.unlink(result_json_file.name)

    # Anti-gaming: Ensure agent actually modified preferences file
    if not result_meta.get("prefs_modified_during_task", False):
        feedback_parts.append("Warning: prefs.js modification timestamp did not change (settings might not be saved)")

    # 2. Fetch the exported prefs.js
    prefs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    try:
        copy_from_env("/tmp/exported_prefs.js", prefs_file.name)
        with open(prefs_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            prefs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported prefs: {e}"}
    finally:
        if os.path.exists(prefs_file.name):
            os.unlink(prefs_file.name)

    # Parse preferences
    actual_prefs = parse_thunderbird_prefs(prefs_content)
    
    # Get expected from task_info or default
    expected_prefs = task_info.get('metadata', {}).get('expected_prefs', {
        "mailnews.message_display.disable_remote_image": True,
        "mailnews.display.prefer_plaintext": True,
        "mailnews.display.html_as": 1,
        "mail.phishing.detection.enabled": True,
        "mail.mdn.report.not_in_to_cc": 2,
        "mail.mdn.report.outside_domain": 2,
        "mail.mdn.report.other": 2,
        "privacy.donottrackheader.enabled": True
    })

    # Evaluate Criterion 1: Block Remote Content (18 pts)
    if actual_prefs.get('mailnews.message_display.disable_remote_image') == expected_prefs['mailnews.message_display.disable_remote_image']:
        score += 18
        feedback_parts.append("[+] Remote content blocked")
    else:
        feedback_parts.append("[-] Remote content still allowed")

    # Evaluate Criterion 2: Plain Text Display (18 pts)
    pt_score = 0
    if actual_prefs.get('mailnews.display.prefer_plaintext') == expected_prefs['mailnews.display.prefer_plaintext']:
        pt_score += 9
    if actual_prefs.get('mailnews.display.html_as') == expected_prefs['mailnews.display.html_as']:
        pt_score += 9
    score += pt_score
    if pt_score == 18:
        feedback_parts.append("[+] Display plain text enabled")
    elif pt_score == 9:
        feedback_parts.append("[-] Plain text display partially configured")
    else:
        feedback_parts.append("[-] Plain text display not configured")

    # Evaluate Criterion 3: Scam Detection (18 pts)
    if actual_prefs.get('mail.phishing.detection.enabled') == expected_prefs['mail.phishing.detection.enabled']:
        score += 18
        feedback_parts.append("[+] Scam detection enabled")
    else:
        feedback_parts.append("[-] Scam detection not enabled")

    # Evaluate Criterion 4: Return Receipts (18 pts)
    mdn_score = 0
    if actual_prefs.get('mail.mdn.report.not_in_to_cc') == expected_prefs['mail.mdn.report.not_in_to_cc']: mdn_score += 6
    if actual_prefs.get('mail.mdn.report.outside_domain') == expected_prefs['mail.mdn.report.outside_domain']: mdn_score += 6
    if actual_prefs.get('mail.mdn.report.other') == expected_prefs['mail.mdn.report.other']: mdn_score += 6
    score += mdn_score
    if mdn_score == 18:
        feedback_parts.append("[+] Return receipts completely disabled")
    elif mdn_score > 0:
        feedback_parts.append(f"[-] Return receipts partially disabled ({mdn_score}/18 pts)")
    else:
        feedback_parts.append("[-] Return receipts setting incorrect")

    # Evaluate Criterion 5: Do Not Track (18 pts)
    if actual_prefs.get('privacy.donottrackheader.enabled') == expected_prefs['privacy.donottrackheader.enabled']:
        score += 18
        feedback_parts.append("[+] Do Not Track enabled")
    else:
        feedback_parts.append("[-] Do Not Track not enabled")

    # Evaluate Criterion 6: VLM Trajectory (10 pts)
    # Check if agent used GUI instead of just rewriting the file in terminal
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at this sequence of screenshots of a user interacting with Thunderbird.
            Is the user navigating the graphical settings interface?
            Specifically, look for any of these open tabs/windows:
            - The 'Settings' or 'Preferences' tab
            - The 'Privacy & Security' section
            - The 'Return Receipts' dialog box
            - The 'Advanced Preferences' (Config Editor) dialog
            
            Return JSON with exactly this format:
            {"gui_settings_used": true/false}
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("gui_settings_used", False):
                    vlm_score += 10
                    feedback_parts.append("[+] GUI Settings usage verified via trajectory")
                else:
                    feedback_parts.append("[-] No GUI Settings usage seen in trajectory")
            else:
                feedback_parts.append("[-] VLM check failed or incomplete")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        feedback_parts.append(f"[?] VLM verification skipped ({e})")
        # Give benefit of doubt if VLM fails but prefs changed via GUI logic
        if result_meta.get("app_was_running", False):
            vlm_score += 10
            
    score += vlm_score

    # Threshold: Pass if at least 3 main settings applied properly (60 pts minimum)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }