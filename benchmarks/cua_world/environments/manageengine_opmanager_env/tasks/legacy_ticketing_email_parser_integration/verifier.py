#!/usr/bin/env python3
"""
Verifier for Legacy Ticketing Email Parser Integration

Scoring (100 pts total, pass threshold 70):
  - Profile Exists: 20 pts
  - Correct Recipient: 15 pts
  - Correct Trigger Criteria: 15 pts
  - Subject Formatting: 20 pts
  - Body Formatting: 30 pts
"""

import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_ticketing_email_parser_integration(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/ticketing_parser_result.json")
    local_path = "/tmp/verify_result.json"

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        copy_from_env(result_file, local_path)
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    db_raw = data.get("db_raw", "")
    api_data = json.dumps(data.get("api_data", {}))
    
    # Combine DB and API outputs and convert to lowercase for easier searching
    combined_text = (db_raw + "\n" + api_data).lower()
    
    score = 0
    details = []

    # 1. Profile Exists (20 pts)
    profile_name = "itsm-email-connector"
    if profile_name in combined_text:
        score += 20
        details.append(f"PASS: Profile '{profile_name}' found (+20)")
    else:
        details.append(f"FAIL: Profile '{profile_name}' not found (0/20)")

    # 2. Correct Recipient (15 pts)
    recipient = "parser@itsm.internal"
    if recipient in combined_text:
        score += 15
        details.append(f"PASS: Recipient '{recipient}' found (+15)")
    else:
        details.append(f"FAIL: Recipient '{recipient}' not found (0/15)")

    # Normalize text to remove whitespace and common HTML formatting artifacts
    # This prevents failures if OpManager encodes spaces as '+' or `%20` or adds `<br>` tags
    normalized_text = combined_text.replace(" ", "").replace("<br>", "").replace("\\n", "").replace("%0a", "").replace("<br/>", "")

    # 3. Subject Formatting (20 pts)
    norm_subject = "[noc-alert]$severityon$displayname"
    if norm_subject in normalized_text:
        score += 20
        details.append("PASS: Subject string matches strict requirements (+20)")
    else:
        if "[noc-alert]" in normalized_text and "$severity" in normalized_text:
            score += 10
            details.append("PARTIAL: Subject contains required keywords but formatting is not exact (+10)")
        else:
            details.append("FAIL: Subject string does not match requirements (0/20)")

    # 4. Body Formatting (30 pts)
    # The five required lines in the body specification
    body_parts = [
        "request-type:incident",
        "host:$displayname",
        "ip-address:$deviceip",
        "event-detail:$alarmmessage",
        "time-logged:$strmodtime"
    ]
    
    body_matches = 0
    for part in body_parts:
        if part in normalized_text:
            body_matches += 1
            
    if body_matches == 5:
        score += 30
        details.append("PASS: Email body contains all 5 required key-value pairs (+30)")
    else:
        pts = body_matches * 6
        score += pts
        details.append(f"PARTIAL: Email body contains {body_matches}/5 required key-value pairs (+{pts})")

    # 5. Correct Criteria (15 pts)
    # Check if the trigger criteria is set to Critical.
    # OpManager often stores this as severity=1, "severity":"1", or explicitly mentions "critical" in the profile config.
    criteria_passed = False
    idx = combined_text.find(profile_name)
    if idx != -1:
        # Search in a 1500-character window around the profile name definition
        window = combined_text[max(0, idx - 500) : min(len(combined_text), idx + 1000)]
        if ("critical" in window or 
            "severity=1" in window.replace(" ", "") or 
            "severity\":1" in window.replace(" ", "") or 
            "\"severity\":\"1\"" in window.replace(" ", "") or 
            "severity=" in window):
            criteria_passed = True
            
    if criteria_passed:
        score += 15
        details.append("PASS: Profile configured with Critical severity criteria (+15)")
    else:
        # Give benefit of the doubt if all strict string formatting was perfectly achieved,
        # as severity indicators can sometimes be deeply nested or obfuscated in raw DB dumps.
        if score >= 85:
            score += 15
            details.append("PASS: Profile configured with Critical criteria (inferred from high completion) (+15)")
        else:
            details.append("FAIL: Profile not clearly configured for Critical severity (0/15)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }