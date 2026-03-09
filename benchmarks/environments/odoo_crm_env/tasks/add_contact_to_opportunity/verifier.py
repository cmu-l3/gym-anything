#!/usr/bin/env python3
"""
Verifier for add_contact_to_opportunity task.

Verifies:
1. Contact "Patricia Williams" exists (15 pts)
2. Contact is linked to "Gemini Furniture" (15 pts)
3. Contact details (email, phone, job) are correct (10 pts each)
4. Opportunity is linked to "Patricia Williams" (25 pts)
5. Anti-gaming: records modified after task start (15 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_contact_to_opportunity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load scoring weights from metadata
    scoring = task_info.get('metadata', {}).get('scoring', {})
    score_contact_exists = scoring.get('contact_exists', 15)
    score_company_linkage = scoring.get('company_linkage', 15)
    score_correct_email = scoring.get('correct_email', 10)
    score_correct_phone = scoring.get('correct_phone', 10)
    score_correct_job = scoring.get('correct_job', 10)
    score_opp_updated = scoring.get('opportunity_updated', 25)
    score_timing = scoring.get('timing', 15)

    pass_threshold = 65

    # Retrieve result JSON
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
    feedback_parts = []
    
    task_start_ts = result.get('task_start_ts', 0)
    gemini_id_setup = result.get('gemini_id_setup', 0)
    
    # --- Criterion 1: Contact Exists ---
    contact = result.get('contact', {})
    if result.get('contact_found', False):
        score += score_contact_exists
        feedback_parts.append("✅ Contact 'Patricia Williams' found")
    else:
        feedback_parts.append("❌ Contact 'Patricia Williams' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Company Linkage ---
    parent_id = contact.get('parent_id')
    parent_name = contact.get('parent_name', '')
    
    # Accept if ID matches Setup ID OR Name matches "Gemini Furniture"
    if (gemini_id_setup and parent_id == gemini_id_setup) or "Gemini Furniture" in str(parent_name):
        score += score_company_linkage
        feedback_parts.append("✅ Linked to Gemini Furniture")
    else:
        feedback_parts.append(f"❌ Not linked to Gemini Furniture (Parent: {parent_name})")

    # --- Criterion 3: Contact Details ---
    # Email
    expected_email = "p.williams@geminifurniture.example.com"
    if contact.get('email') == expected_email:
        score += score_correct_email
        feedback_parts.append("✅ Email correct")
    else:
        feedback_parts.append(f"❌ Email mismatch (Got: {contact.get('email')})")

    # Phone (flexible check)
    phone = contact.get('phone', '').replace(' ', '').replace('-', '').replace('(', '').replace(')', '')
    if "5550192" in phone:
        score += score_correct_phone
        feedback_parts.append("✅ Phone correct")
    else:
        feedback_parts.append(f"❌ Phone mismatch (Got: {contact.get('phone')})")

    # Job Position
    job = contact.get('job_position', '').lower()
    if "procurement" in job and "manager" in job:
        score += score_correct_job
        feedback_parts.append("✅ Job position correct")
    else:
        feedback_parts.append(f"❌ Job position mismatch (Got: {contact.get('job_position')})")

    # --- Criterion 4: Opportunity Updated ---
    opp = result.get('opportunity', {})
    opp_partner_id = opp.get('partner_id')
    contact_id = contact.get('id')
    
    if result.get('opportunity_found', False):
        # Check if opportunity partner is the new contact
        if contact_id and opp_partner_id == contact_id:
            score += score_opp_updated
            feedback_parts.append("✅ Opportunity customer updated")
        else:
            feedback_parts.append(f"❌ Opportunity customer NOT updated (Current: {opp.get('partner_name')})")
    else:
        feedback_parts.append("❌ Opportunity not found (System Error?)")

    # --- Criterion 5: Anti-Gaming (Timing) ---
    # Check if contact creation and opportunity write happened after task start
    contact_ts = contact.get('create_ts', 0)
    opp_ts = opp.get('write_ts', 0)
    
    # Allow some buffer (e.g., system clock skew), usually task_start is strictly less
    timing_ok = True
    if contact_ts < task_start_ts:
        timing_ok = False
        feedback_parts.append("⚠️ Contact created before task start")
    
    if opp_ts < task_start_ts:
        timing_ok = False
        feedback_parts.append("⚠️ Opportunity modified before task start")
        
    if timing_ok:
        score += score_timing
        feedback_parts.append("✅ Timing validation passed")
    else:
        feedback_parts.append("❌ Timing validation failed")

    # Final Check
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }