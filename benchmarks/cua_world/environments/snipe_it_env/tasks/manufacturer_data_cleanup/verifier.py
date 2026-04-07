#!/usr/bin/env python3
"""
Verifier for manufacturer_data_cleanup task.

Scoring breakdown (100 points):
- C1 (12 pts): OptiPlex 7090 reassigned to Dell
- C2 (12 pts): Latitude 5520 reassigned to Dell
- C3 (8 pts): Dell Inc. deleted
- C4 (12 pts): ProBook 450 G8 reassigned to HP Inc.
- C5 (8 pts): EliteDisplay E243 reassigned to HP Inc.
- C6 (8 pts): Hewlett-Packard deleted
- C7 (8 pts): ThinkPad X1 Carbon Gen 9 reassigned to Lenovo
- C8 (8 pts): Lenovo Group deleted
- C9 (8 pts): Cisco Systems created with contact details
- C10 (8 pts): Catalyst 9300 created under Cisco Networking
- C11 (8 pts): All 5 test assets remain intact
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/manufacturer_cleanup_result.json"

def verify_manufacturer_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.path.exists(temp_file.name) and os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    refs = result.get("reference_ids", {})
    models = result.get("models_mfr_ids", {})
    deletions = result.get("deletions", {})
    cisco = result.get("cisco_systems", {})
    catalyst = result.get("catalyst_9300", {})

    # DO-NOTHING CHECK
    if (models.get("optiplex_7090") == refs.get("dup_dell") and 
        not cisco.get("found") and 
        not deletions.get("dup_dell_deleted")):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No models reassigned and no new manufacturers created."}

    # C1: OptiPlex 7090 -> Dell
    if models.get("optiplex_7090") == refs.get("canon_dell") and refs.get("canon_dell") > 0:
        score += 12
        feedback.append("C1: OptiPlex 7090 reassigned to Dell (+12)")
    else:
        feedback.append("C1: OptiPlex 7090 not reassigned to canonical Dell (+0)")

    # C2: Latitude 5520 -> Dell
    if models.get("latitude_5520") == refs.get("canon_dell") and refs.get("canon_dell") > 0:
        score += 12
        feedback.append("C2: Latitude 5520 reassigned to Dell (+12)")
    else:
        feedback.append("C2: Latitude 5520 not reassigned to canonical Dell (+0)")

    # C3: Dell Inc. deleted
    if deletions.get("dup_dell_deleted"):
        score += 8
        feedback.append("C3: 'Dell Inc.' duplicate deleted (+8)")
    else:
        feedback.append("C3: 'Dell Inc.' duplicate was not deleted (+0)")

    # C4: ProBook 450 G8 -> HP Inc.
    if models.get("probook_450") == refs.get("canon_hp") and refs.get("canon_hp") > 0:
        score += 12
        feedback.append("C4: ProBook 450 G8 reassigned to HP Inc. (+12)")
    else:
        feedback.append("C4: ProBook 450 G8 not reassigned to canonical HP Inc. (+0)")

    # C5: EliteDisplay E243 -> HP Inc.
    if models.get("elitedisplay_e243") == refs.get("canon_hp") and refs.get("canon_hp") > 0:
        score += 8
        feedback.append("C5: EliteDisplay E243 reassigned to HP Inc. (+8)")
    else:
        feedback.append("C5: EliteDisplay E243 not reassigned to canonical HP Inc. (+0)")

    # C6: Hewlett-Packard deleted
    if deletions.get("dup_hp_deleted"):
        score += 8
        feedback.append("C6: 'Hewlett-Packard' duplicate deleted (+8)")
    else:
        feedback.append("C6: 'Hewlett-Packard' duplicate was not deleted (+0)")

    # C7: ThinkPad X1 Carbon -> Lenovo
    if models.get("thinkpad_x1") == refs.get("canon_lenovo") and refs.get("canon_lenovo") > 0:
        score += 8
        feedback.append("C7: ThinkPad X1 Carbon Gen 9 reassigned to Lenovo (+8)")
    else:
        feedback.append("C7: ThinkPad X1 Carbon Gen 9 not reassigned to canonical Lenovo (+0)")

    # C8: Lenovo Group deleted
    if deletions.get("dup_lenovo_deleted"):
        score += 8
        feedback.append("C8: 'Lenovo Group' duplicate deleted (+8)")
    else:
        feedback.append("C8: 'Lenovo Group' duplicate was not deleted (+0)")

    # C9: Cisco Systems created
    if cisco.get("found"):
        cisco_score = 4
        feedback_notes = ["C9: Cisco Systems created (+4)"]
        
        # Check details with tolerance
        if "cisco.com" in cisco.get("url", "").lower():
            cisco_score += 1
            feedback_notes.append("URL correct (+1)")
        if "support" in cisco.get("support_url", "").lower():
            cisco_score += 1
            feedback_notes.append("Support URL correct (+1)")
        
        phone_digits = ''.join(filter(str.isdigit, cisco.get("support_phone", "")))
        if "8005532447" in phone_digits:
            cisco_score += 1
            feedback_notes.append("Phone correct (+1)")
            
        if "tac@cisco.com" in cisco.get("support_email", "").lower():
            cisco_score += 1
            feedback_notes.append("Email correct (+1)")
            
        score += cisco_score
        feedback.append(", ".join(feedback_notes))
    else:
        feedback.append("C9: 'Cisco Systems' manufacturer not found (+0)")

    # C10: Catalyst 9300 model created
    if catalyst.get("found"):
        cat_score = 0
        if catalyst.get("mfr_id") == cisco.get("id") and cisco.get("id") > 0:
            cat_score += 4
        if "network" in catalyst.get("category_name", "").lower():
            cat_score += 4
            
        if cat_score == 8:
            score += 8
            feedback.append("C10: Catalyst 9300 correctly created under Cisco/Networking (+8)")
        else:
            score += cat_score
            feedback.append(f"C10: Catalyst 9300 created but parent mapping imperfect (+{cat_score})")
    else:
        feedback.append("C10: 'Catalyst 9300' model not found (+0)")

    # C11: Assets intact
    if result.get("assets_intact"):
        score += 8
        feedback.append("C11: All 5 test assets remained intact (+8)")
    else:
        missing = 5 - int(result.get("assets_intact_count", 0))
        feedback.append(f"C11: FAILURE - {missing} test assets were wrongfully deleted or orphaned (+0)")

    passed = score >= 60 and result.get("assets_intact", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }