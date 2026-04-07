#!/usr/bin/env python3
"""
Verifier for configure_company_branding_and_smtp task.
Evaluates settings persisted to the database and config.inc.php.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Read output
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/config_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =======================================================
    # SECTION 1: Company Details (Total 35 pts)
    # =======================================================
    org_name = result.get("org_name", "")
    org_web = result.get("org_website", "")
    
    if metadata["expected_company_name"].lower() in org_name.lower():
        if metadata["expected_website"].lower() in org_web.lower():
            score += 15
            feedback_parts.append("✅ Company Name & Website match")
        else:
            score += 10
            feedback_parts.append("⚠️ Company Name matches but Website incorrect")
    else:
        feedback_parts.append("❌ Company Name incorrect")
        
    org_addr = result.get("org_address", "")
    org_city = result.get("org_city", "")
    org_state = result.get("org_state", "")
    org_code = result.get("org_code", "")
    org_country = result.get("org_country", "")
    
    addr_valid = (
        metadata["expected_address"].lower() in org_addr.lower() and
        metadata["expected_city"].lower() in org_city.lower() and
        metadata["expected_state"].lower() in org_state.lower() and
        metadata["expected_code"] in org_code and
        metadata["expected_country"].lower() in org_country.lower()
    )
    if addr_valid:
        score += 15
        feedback_parts.append("✅ Company Address Block complete")
    else:
        feedback_parts.append("❌ Company Address Block incomplete/incorrect")
        
    org_phone = result.get("org_phone", "")
    if metadata["expected_phone"] in org_phone or "3125550144" in org_phone.replace("-", ""):
        score += 5
        feedback_parts.append("✅ Company Phone matches")

    # =======================================================
    # SECTION 2: SMTP Outgoing Server (Total 25 pts)
    # =======================================================
    smtp_server = result.get("smtp_server", "")
    smtp_user = result.get("smtp_user", "")
    smtp_pass = result.get("smtp_pass", "")
    smtp_from = result.get("smtp_from", "")
    
    if (metadata["expected_smtp_server"].lower() in smtp_server.lower() and 
        metadata["expected_smtp_user"] == smtp_user and
        metadata["expected_smtp_pass"] == smtp_pass):
        score += 15
        feedback_parts.append("✅ SMTP Server and Auth match")
    else:
        feedback_parts.append("❌ SMTP Server/Auth incorrect")

    if metadata["expected_smtp_from"].lower() == smtp_from.lower():
        score += 10
        feedback_parts.append("✅ SMTP From Email matches")
    else:
        feedback_parts.append("❌ SMTP From Email incorrect")

    # =======================================================
    # SECTION 3: Configuration Editor (Total 40 pts)
    # =======================================================
    config_php = result.get("config_php", {})
    helpdesk_email = config_php.get("helpdesk_email", "")
    default_module = config_php.get("default_module", "")
    upload_maxsize = str(config_php.get("upload_maxsize", ""))
    
    if metadata["expected_helpdesk_email"].lower() == helpdesk_email.lower():
        score += 15
        feedback_parts.append("✅ Config Help Desk Email matches")
    else:
        feedback_parts.append("❌ Config Help Desk Email incorrect")
        
    if metadata["expected_default_module"].lower() == default_module.lower() or "opportunities" in default_module.lower():
        score += 15
        feedback_parts.append("✅ Config Default Module matches")
    else:
        feedback_parts.append("❌ Config Default Module incorrect")

    # Vtiger translates 5MB into bytes (e.g., 5242880 or 5000000) inside config.inc.php
    # We accept "5" (if raw string stored) or anything ~ 5,000,000
    try:
        size_val = int(upload_maxsize)
        if size_val == 5 or (4500000 <= size_val <= 6000000):
            score += 10
            feedback_parts.append("✅ Config Upload Size correct")
        else:
            feedback_parts.append(f"❌ Config Upload Size incorrect ({size_val})")
    except ValueError:
        feedback_parts.append("❌ Config Upload Size invalid")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }