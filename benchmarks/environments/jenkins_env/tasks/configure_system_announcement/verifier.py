#!/usr/bin/env python3
"""
Verifier for configure_system_announcement task.
Checks that:
1. Markup formatter has been changed to Safe HTML
2. System message contains the required announcement content
3. Anti-gaming: state actually changed from initial state
"""

import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_system_announcement(traj, env_info, task_info):
    """
    Verify the configure_system_announcement task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_system_announcement_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "score": 0,
            "passed": False,
            "feedback": f"Failed to load result file: {e}. Task may not have been attempted.",
            "details": str(e)
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    score = 0
    details = []
    
    # ============================================
    # CRITERION 1: Markup Formatter (25 points)
    # ============================================
    markup = result.get("markup_formatter", {})
    is_safe_html = markup.get("is_safe_html", False)
    formatter_type = markup.get("type", "unknown")
    formatter_class = markup.get("class_name", "unknown")
    
    if is_safe_html:
        score += 25
        details.append(f"[PASS +25] Markup formatter changed to Safe HTML ({formatter_class})")
    else:
        details.append(f"[FAIL  0] Markup formatter NOT Safe HTML. Current: {formatter_type} ({formatter_class})")
    
    # ============================================
    # CRITERION 2: System Message Non-Empty (15 points)
    # ============================================
    sys_msg = result.get("system_message", {})
    is_non_empty = sys_msg.get("is_non_empty", False)
    msg_length = sys_msg.get("length", 0)
    has_html_tags = sys_msg.get("has_html_tags", False)
    
    if is_non_empty:
        score += 15
        details.append(f"[PASS +15] System message is configured ({msg_length} chars)")
    else:
        details.append(f"[FAIL  0] System message is empty or too short ({msg_length} chars)")
        
    if not has_html_tags and is_non_empty:
        details.append("[WARNING] System message does not appear to contain HTML tags")
    
    # ============================================
    # CRITERION 3: Maintenance Heading (15 points)
    # ============================================
    content = sys_msg.get("content_checks", {})
    
    if content.get("has_maintenance_heading", False):
        score += 15
        details.append("[PASS +15] System message contains 'Scheduled Maintenance Notice' heading")
    else:
        details.append("[FAIL  0] System message missing 'Scheduled Maintenance Notice' heading")
    
    # ============================================
    # CRITERION 4: Maintenance Date (10 points)
    # ============================================
    if content.get("has_date_jan25", False):
        score += 10
        details.append("[PASS +10] System message contains maintenance date (January 25, 2025)")
    else:
        details.append("[FAIL  0] System message missing maintenance date")
    
    # ============================================
    # CRITERION 5: Time Window (10 points)
    # ============================================
    if content.get("has_time_window", False):
        score += 10
        details.append("[PASS +10] System message contains time window (02:00 to 06:00 UTC)")
    else:
        details.append("[FAIL  0] System message missing time window")
    
    # ============================================
    # CRITERION 6: List Items (15 points - 5 each)
    # ============================================
    list_score = 0
    list_items_found = 0
    
    if content.get("has_builds_suspended", False):
        list_score += 5
        list_items_found += 1
    
    if content.get("has_pipelines_paused", False):
        list_score += 5
        list_items_found += 1
    
    if content.get("has_plan_accordingly", False):
        list_score += 5
        list_items_found += 1
    
    score += list_score
    if list_score == 15:
        details.append(f"[PASS +15] All 3 list items present")
    elif list_score > 0:
        details.append(f"[PARTIAL +{list_score}] {list_items_found}/3 list items present")
    else:
        details.append("[FAIL  0] No list items found in system message")
    
    # ============================================
    # CRITERION 7: Contact Email (10 points)
    # ============================================
    if content.get("has_contact_email", False):
        score += 10
        details.append("[PASS +10] System message contains contact email (devops-team@company.com)")
    else:
        details.append("[FAIL  0] System message missing contact email")
    
    # ============================================
    # ANTI-GAMING CHECKS
    # ============================================
    initial = result.get("initial_state", {})
    initial_formatter = initial.get("formatter", "")
    initial_msg_length = initial.get("message_length", 0)
    
    # Check that state actually changed
    state_changed = False
    if is_safe_html and "EscapedMarkupFormatter" in initial_formatter:
        state_changed = True
    elif msg_length > 10 and initial_msg_length < 5:
        state_changed = True
    
    if not state_changed and score > 0:
        details.append("[WARNING] Could not confirm state changed from initial (possible gaming)")
        # Penalize if score is high but no change detected (unlikely given setup script, but possible)
        if score > 50:
            score = 0
            details.append("[FAIL 0] Score reset because no state change detected")
    
    # ============================================
    # FINAL RESULT
    # ============================================
    # Pass requires at minimum: markup formatter changed AND some message content
    passed = score >= 70 and is_safe_html
    
    result_details = "\n".join(details)
    summary = f"Score: {score}/100 | {'PASSED' if passed else 'FAILED'}"
    
    logger.info(f"Verification complete: {summary}")
    
    return {
        "score": score,
        "passed": passed,
        "feedback": summary,
        "details": result_details
    }