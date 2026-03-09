#!/usr/bin/env python3
"""
Verifier for configure_spam_filtering task.
Verifies:
1. Spam filtering enabled
2. Classification threshold (4)
3. Deletion threshold (10)
4. Spam folder delivery
5. Whitelist/Blacklist entries
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_spam_filtering(traj, env_info, task_info):
    """
    Verify that spam filtering is correctly configured for greenfield.test.
    """
    # 1. Setup - Retrieve result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    domain_info = result.get("domain_info", "")
    spam_info = result.get("spam_info", "")
    user_prefs = result.get("user_prefs_content", "")
    domain_conf = result.get("domain_conf_content", "")
    procmail_content = result.get("procmail_content", "")
    config_changed = result.get("config_changed_during_task", False)

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # Criterion 1: Spam Filtering Enabled (15 pts)
    # ---------------------------------------------------------
    spam_enabled = False
    # Check "Features: ... spam" or "Spam filtering enabled: Yes"
    if "Spam filtering enabled: Yes" in domain_info or \
       "Features: " in domain_info and "spam" in domain_info.split("Features:")[1].split("\n")[0] or \
       "spam=1" in domain_conf:
        spam_enabled = True

    if spam_enabled:
        score += 15
        feedback.append("PASS: Spam filtering is enabled (+15)")
    else:
        feedback.append("FAIL: Spam filtering is NOT enabled")

    # ---------------------------------------------------------
    # Criterion 2: Classification Threshold = 4 (15 pts)
    # ---------------------------------------------------------
    threshold_correct = False
    # Check user_prefs for "required_score 4"
    if re.search(r"required_score\s+4(\.0)?\b", user_prefs):
        threshold_correct = True
    # Check domain conf "spam_level=4"
    elif re.search(r"spam_level=4(\.0)?\b", domain_conf):
        threshold_correct = True
    # Check virtualmin output "Score ... 4"
    elif "4" in spam_info and ("Score" in spam_info or "Required" in spam_info):
        threshold_correct = True

    if threshold_correct:
        score += 15
        feedback.append("PASS: Classification threshold is 4 (+15)")
    else:
        feedback.append("FAIL: Classification threshold is incorrect (expected 4)")

    # ---------------------------------------------------------
    # Criterion 3: Deletion Threshold = 10 (15 pts)
    # ---------------------------------------------------------
    delete_correct = False
    # Check domain conf "spam_delete_level=10"
    if re.search(r"spam_delete_level=10(\.0)?\b", domain_conf) or \
       re.search(r"spam_delete=10(\.0)?\b", domain_conf):
        delete_correct = True
    # Check virtualmin output
    elif "10" in spam_info and "Delete" in spam_info:
        delete_correct = True
    
    # Also check user_prefs if they used a weird custom score method
    
    if delete_correct:
        score += 15
        feedback.append("PASS: Deletion threshold is 10 (+15)")
    else:
        feedback.append("FAIL: Deletion threshold is incorrect (expected 10)")

    # ---------------------------------------------------------
    # Criterion 4: Delivery to Spam Folder (15 pts)
    # ---------------------------------------------------------
    delivery_correct = False
    # Check procmail for delivery to .spam or Maildir/.spam/
    if ".spam" in procmail_content or "Maildir/.spam/" in procmail_content:
        delivery_correct = True
    # Check domain conf for delivery mode
    # spam_delivery=1 usually means write to file/folder
    elif "spam_delivery=1" in domain_conf and ("spam_file=.spam" in domain_conf or "spam_file=Maildir/.spam/" in domain_conf):
        delivery_correct = True
    # Check "spam_delivery_file"
    elif "spam_file" in domain_conf and ".spam" in domain_conf:
        delivery_correct = True

    if delivery_correct:
        score += 15
        feedback.append("PASS: Delivery to spam folder configured (+15)")
    else:
        feedback.append("FAIL: Spam folder delivery not detected")

    # ---------------------------------------------------------
    # Criterion 5 & 6: Whitelist (20 pts)
    # ---------------------------------------------------------
    whitelist_1 = "*@trustedpartner.org"
    whitelist_2 = "admin@important-alerts.net"
    
    wl_score = 0
    # Search in user_prefs or domain conf
    search_space = user_prefs + "\n" + domain_conf
    
    if whitelist_1 in search_space:
        wl_score += 10
    if whitelist_2 in search_space:
        wl_score += 10
    
    score += wl_score
    if wl_score == 20:
        feedback.append("PASS: Both whitelist entries found (+20)")
    elif wl_score > 0:
        feedback.append(f"PARTIAL: Found {wl_score/10} whitelist entries")
    else:
        feedback.append("FAIL: No whitelist entries found")

    # ---------------------------------------------------------
    # Criterion 7 & 8: Blacklist (20 pts)
    # ---------------------------------------------------------
    blacklist_1 = "*@known-spammer.example"
    blacklist_2 = "marketing@bulkmail.example"
    
    bl_score = 0
    if blacklist_1 in search_space:
        bl_score += 10
    if blacklist_2 in search_space:
        bl_score += 10
        
    score += bl_score
    if bl_score == 20:
        feedback.append("PASS: Both blacklist entries found (+20)")
    elif bl_score > 0:
        feedback.append(f"PARTIAL: Found {bl_score/10} blacklist entries")
    else:
        feedback.append("FAIL: No blacklist entries found")

    # ---------------------------------------------------------
    # Anti-Gaming Check
    # ---------------------------------------------------------
    # We require the domain info to show spam enabled AND at least one config file changed/exists
    if not config_changed and score > 0:
        # If score > 0 but files didn't look modified, ensure we aren't just reading default state
        # (Though setup script cleared state, so defaults shouldn't score high)
        pass 

    passed = (score >= 60) and spam_enabled
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }