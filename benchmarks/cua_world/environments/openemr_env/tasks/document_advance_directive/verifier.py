#!/usr/bin/env python3
"""
Verifier for Document Advance Directive task in OpenEMR

Verifies that advance directive status was properly documented for patient Jenna Ledner.

Scoring (100 points total):
- Patient located: 15 points
- AD status updated: 25 points
- Proxy name recorded: 20 points
- Proxy contact saved: 15 points
- Document types noted: 10 points
- Notes added: 15 points

Pass threshold: 60 points with AD Status Updated achieved
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone_str):
    """Remove all non-digit characters from phone string."""
    if not phone_str:
        return ""
    return ''.join(c for c in str(phone_str) if c.isdigit())


def search_text_for_keywords(text, keywords, case_sensitive=False):
    """Search text for any of the given keywords."""
    if not text:
        return False
    search_text = text if case_sensitive else text.lower()
    for keyword in keywords:
        search_keyword = keyword if case_sensitive else keyword.lower()
        if search_keyword in search_text:
            return True
    return False


def verify_advance_directive(traj, env_info, task_info):
    """
    Verify that advance directive was properly documented.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', and 'subscores'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Jenna')
    expected_lname = metadata.get('patient_lname', 'Ledner')
    expected_proxy_name = metadata.get('healthcare_proxy_name', 'Margaret Ledner')
    expected_proxy_phone = metadata.get('healthcare_proxy_phone', '5551234567')
    pass_threshold = metadata.get('pass_threshold', 60)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "patient_located": 0,
        "ad_status_updated": 0,
        "proxy_name_recorded": 0,
        "proxy_contact_saved": 0,
        "document_types_noted": 0,
        "notes_added": 0
    }
    
    # Copy result JSON from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/advance_directive_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}",
            "subscores": subscores
        }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_state = result.get('initial_state', {})
    current_state = result.get('current_state', {})
    verification_flags = result.get('verification_flags', {})
    task_start = result.get('task_start_timestamp', 0)
    task_end = result.get('task_end_timestamp', 0)
    
    logger.info(f"Verifying AD documentation for patient PID={patient_pid}")
    logger.info(f"Initial state: {initial_state}")
    logger.info(f"Current state: {current_state}")
    logger.info(f"Verification flags: {verification_flags}")
    
    # CRITERION 1: Patient Located (15 points)
    # Verify we're checking the correct patient
    if patient_pid == expected_pid:
        subscores["patient_located"] = 15
        score += 15
        feedback_parts.append(f"✅ Correct patient identified (PID={expected_pid}, {expected_fname} {expected_lname})")
    else:
        feedback_parts.append(f"❌ Wrong patient! Expected PID={expected_pid}, got PID={patient_pid}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: AD Status Updated (25 points)
    # Check if ad_reviewed field was updated or new notes/history added
    ad_updated = verification_flags.get('ad_status_updated', False)
    new_notes = verification_flags.get('new_notes_added', False)
    
    # Also check if usertext fields changed (compare initial vs current)
    initial_notes_count = initial_state.get('notes_count', 0)
    current_notes_count = current_state.get('notes_count', 0)
    
    # Combine all current text for content analysis
    all_current_text = " ".join([
        current_state.get('usertext1', ''),
        current_state.get('usertext2', ''),
        current_state.get('usertext3', ''),
        current_state.get('usertext4', ''),
        current_state.get('recent_notes', ''),
        current_state.get('history_data', '')
    ]).lower()
    
    # Check for any AD-related content
    ad_keywords = ['advance directive', 'healthcare proxy', 'molst', 'polst', 
                   'living will', 'dnr', 'dni', 'power of attorney', 'proxy']
    ad_content_found = search_text_for_keywords(all_current_text, ad_keywords)
    
    if ad_updated:
        subscores["ad_status_updated"] = 25
        score += 25
        ad_reviewed = current_state.get('ad_reviewed', '')
        feedback_parts.append(f"✅ AD reviewed date updated: {ad_reviewed}")
    elif new_notes or current_notes_count > initial_notes_count:
        # Give partial credit if notes were added with AD content
        if ad_content_found:
            subscores["ad_status_updated"] = 25
            score += 25
            feedback_parts.append("✅ AD documentation added via notes")
        else:
            subscores["ad_status_updated"] = 10
            score += 10
            feedback_parts.append("⚠️ Notes added but AD keywords not clearly found")
    elif ad_content_found:
        # Give partial credit if AD content exists but ad_reviewed not updated
        subscores["ad_status_updated"] = 15
        score += 15
        feedback_parts.append("⚠️ AD content found in record (ad_reviewed date not updated)")
    else:
        feedback_parts.append("❌ No advance directive documentation found")
    
    # CRITERION 3: Proxy Name Recorded (20 points)
    # Look for "Margaret" or "Ledner" (the proxy name)
    proxy_name_found = verification_flags.get('proxy_name_found', False)
    
    # Also do our own check
    proxy_keywords = ['margaret', 'ledner', 'daughter']
    proxy_in_text = search_text_for_keywords(all_current_text, proxy_keywords)
    
    if proxy_name_found or proxy_in_text:
        subscores["proxy_name_recorded"] = 20
        score += 20
        feedback_parts.append("✅ Healthcare proxy name (Margaret Ledner) documented")
    else:
        feedback_parts.append("❌ Healthcare proxy name not found in record")
    
    # CRITERION 4: Proxy Contact Saved (15 points)
    # Look for phone number 555-123-4567 in any format
    proxy_phone_found = verification_flags.get('proxy_phone_found', False)
    
    # Also do our own check - look for the digits
    all_text_digits = normalize_phone(all_current_text)
    phone_in_text = expected_proxy_phone in all_text_digits
    
    if proxy_phone_found or phone_in_text:
        subscores["proxy_contact_saved"] = 15
        score += 15
        feedback_parts.append("✅ Healthcare proxy phone number documented")
    else:
        feedback_parts.append("❌ Healthcare proxy phone not found")
    
    # CRITERION 5: Document Types Noted (10 points)
    # Look for MOLST, Healthcare Proxy, etc.
    doc_types_found = verification_flags.get('document_types_found', False)
    
    doc_keywords = ['molst', 'polst', 'healthcare proxy', 'living will']
    docs_in_text = search_text_for_keywords(all_current_text, doc_keywords)
    
    if doc_types_found or docs_in_text:
        subscores["document_types_noted"] = 10
        score += 10
        feedback_parts.append("✅ Document types (Healthcare Proxy/MOLST) mentioned")
    else:
        feedback_parts.append("❌ Document types not specified")
    
    # CRITERION 6: Notes Added (15 points)
    # Check if clinical notes were added
    clinical_prefs_found = verification_flags.get('clinical_prefs_found', False)
    
    # Look for clinical preference keywords
    clinical_keywords = ['dnr', 'dni', 'do not resuscitate', 'do not intubate', 
                        'comfort measures', 'comfort care', 'wishes', 'preferences']
    clinical_in_text = search_text_for_keywords(all_current_text, clinical_keywords)
    
    if new_notes or current_notes_count > initial_notes_count:
        if clinical_prefs_found or clinical_in_text:
            subscores["notes_added"] = 15
            score += 15
            feedback_parts.append("✅ Clinical notes with preferences documented")
        else:
            subscores["notes_added"] = 10
            score += 10
            feedback_parts.append("⚠️ Notes added (clinical preferences not detailed)")
    elif clinical_prefs_found or clinical_in_text:
        subscores["notes_added"] = 10
        score += 10
        feedback_parts.append("⚠️ Clinical preferences found in record fields")
    else:
        feedback_parts.append("❌ No clinical notes about patient wishes")
    
    # Anti-gaming check: Verify task took reasonable time
    if task_end > 0 and task_start > 0:
        task_duration = task_end - task_start
        if task_duration < 10:
            # Suspiciously fast - might be gaming
            feedback_parts.append(f"⚠️ Task completed very quickly ({task_duration}s)")
            logger.warning(f"Suspiciously short task duration: {task_duration} seconds")
    
    # Calculate pass/fail
    # Must have at least partial AD documentation to pass
    ad_documented = subscores["ad_status_updated"] > 0
    passed = score >= pass_threshold and ad_documented
    
    # Compile final feedback
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100 - {'PASS' if passed else 'FAIL'}")
    logger.info(f"Subscores: {subscores}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "ad_reviewed": current_state.get('ad_reviewed', ''),
            "notes_count_change": current_notes_count - initial_notes_count,
            "proxy_name_found": proxy_name_found or proxy_in_text,
            "proxy_phone_found": proxy_phone_found or phone_in_text
        }
    }


if __name__ == "__main__":
    # Test mode - for local debugging
    print("Verifier module loaded. Use verify_advance_directive(traj, env_info, task_info) to verify.")