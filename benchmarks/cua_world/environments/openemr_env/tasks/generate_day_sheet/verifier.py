#!/usr/bin/env python3
"""
Verifier for Generate Day Sheet Financial Report task in OpenEMR

Verification Strategy:
1. Check audit logs for login activity (user authenticated)
2. Check for navigation to reports area
3. Check for financial/billing report access
4. VLM verification of trajectory to confirm report display
5. Anti-gaming: timestamps must show activity during task window

Uses copy_from_env to read pre-exported verification data.
Uses trajectory frames for VLM verification (not just final screenshot).
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_day_sheet(traj, env_info, task_info):
    """
    Verify that the agent generated a day sheet financial report.

    Scoring (100 points total):
    - Login successful: 15 points
    - Navigated to Reports menu: 20 points
    - Accessed Financial/Billing reports: 20 points
    - Report generated/displayed: 25 points
    - VLM trajectory verification: 20 points

    Passing threshold: 60 points with report evidence
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata for expected values
    metadata = task_info.get('metadata', {})
    scoring_weights = metadata.get('scoring_weights', {
        'login_success': 15,
        'navigated_reports': 20,
        'accessed_financial': 20,
        'report_generated': 25,
        'vlm_verification': 20
    })

    score = 0
    feedback_parts = []
    subscores = {
        "login_success": False,
        "navigated_reports": False,
        "accessed_financial": False,
        "report_generated": False,
        "vlm_verification": False
    }

    # ==================================================================
    # STEP 1: Load exported result data
    # ==================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/day_sheet_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load verification data: {str(e)}",
            "subscores": subscores
        }

    # Extract result data
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    task_date = result.get('task_date', '')
    initial_log_count = result.get('initial_log_count', 0)
    current_log_count = result.get('current_log_count', 0)
    login_detected = result.get('login_detected', False)
    report_activity = result.get('report_activity_count', 0)
    financial_activity = result.get('financial_activity_count', 0)
    report_generated = result.get('report_generated', False)
    export_file_found = result.get('export_file_found', False)
    window_title = result.get('window_title', '')
    title_indicates_report = result.get('title_indicates_report', False)

    logger.info(f"Result: login={login_detected}, report_activity={report_activity}, "
                f"financial_activity={financial_activity}, title_indicates={title_indicates_report}")

    # ==================================================================
    # STEP 2: Anti-gaming check - must have activity during task
    # ==================================================================
    if current_log_count <= initial_log_count:
        feedback_parts.append("WARNING: No activity detected during task window")
        # Don't fail immediately, but this is suspicious

    task_duration = task_end - task_start
    if task_duration < 10:
        feedback_parts.append("WARNING: Task completed suspiciously quickly")

    # ==================================================================
    # CRITERION 1: Login successful (15 points)
    # ==================================================================
    if login_detected:
        score += scoring_weights.get('login_success', 15)
        subscores["login_success"] = True
        feedback_parts.append("✅ Login successful")
    else:
        # Check if already logged in (activity without explicit login event)
        if current_log_count > initial_log_count:
            # Some activity occurred, likely already logged in
            score += scoring_weights.get('login_success', 15) // 2
            feedback_parts.append("⚠️ Activity detected (may have been pre-logged in)")
        else:
            feedback_parts.append("❌ No login detected")

    # ==================================================================
    # CRITERION 2: Navigated to Reports menu (20 points)
    # ==================================================================
    # Check window title and activity logs for reports navigation
    reports_navigated = False
    
    if report_activity > 0:
        reports_navigated = True
    elif 'report' in window_title.lower():
        reports_navigated = True
    elif current_log_count > initial_log_count + 2:
        # Multiple activities suggest navigation occurred
        reports_navigated = True
    
    if reports_navigated:
        score += scoring_weights.get('navigated_reports', 20)
        subscores["navigated_reports"] = True
        feedback_parts.append("✅ Navigated to Reports area")
    else:
        feedback_parts.append("❌ Reports navigation not confirmed")

    # ==================================================================
    # CRITERION 3: Accessed Financial/Billing reports (20 points)
    # ==================================================================
    financial_accessed = False
    
    if financial_activity > 0:
        financial_accessed = True
    elif any(term in window_title.lower() for term in ['financial', 'billing', 'fee', 'day sheet', 'daily']):
        financial_accessed = True
    
    if financial_accessed:
        score += scoring_weights.get('accessed_financial', 20)
        subscores["accessed_financial"] = True
        feedback_parts.append("✅ Accessed Financial/Billing reports section")
    else:
        feedback_parts.append("❌ Financial reports access not confirmed")

    # ==================================================================
    # CRITERION 4: Report generated/displayed (25 points)
    # ==================================================================
    report_displayed = False
    
    if report_generated:
        report_displayed = True
    elif title_indicates_report:
        report_displayed = True
    elif export_file_found:
        report_displayed = True
        feedback_parts.append("✅ Report file was exported")
    
    if report_displayed:
        score += scoring_weights.get('report_generated', 25)
        subscores["report_generated"] = True
        feedback_parts.append("✅ Day sheet report generated")
    else:
        feedback_parts.append("❌ Report generation not confirmed from logs")

    # ==================================================================
    # CRITERION 5: VLM trajectory verification (20 points)
    # ==================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (not just final screenshot!)
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            all_frames = frames + ([final_frame] if final_frame else [])
            
            if all_frames:
                vlm_prompt = """You are verifying if a computer agent generated a Day Sheet financial report in OpenEMR (Electronic Health Records system).

Examine these screenshots from the agent's work session and determine:

1. Did the agent log in to OpenEMR? (login page → dashboard transition)
2. Did the agent navigate to a Reports menu or section?
3. Did the agent access Financial, Billing, or Fee reports?
4. Is a Day Sheet or Daily Summary report displayed?
5. Does the final view show a financial report with columns like charges, payments, adjustments?

A Day Sheet report typically shows:
- Date or date range at the top
- Financial columns (Charges, Payments, Adjustments, Balance)
- Transaction summaries or line items
- Totals at the bottom

Respond in JSON format:
{
    "login_visible": true/false,
    "reports_menu_accessed": true/false,
    "financial_section_visible": true/false,
    "day_sheet_displayed": true/false,
    "financial_columns_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the workflow"
}
"""
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_day_sheet = parsed.get('day_sheet_displayed', False)
                    vlm_financial = parsed.get('financial_columns_visible', False)
                    vlm_reports = parsed.get('reports_menu_accessed', False)
                    vlm_confidence = parsed.get('confidence', 'low')
                    vlm_reasoning = parsed.get('reasoning', '')
                    
                    logger.info(f"VLM result: day_sheet={vlm_day_sheet}, financial={vlm_financial}, "
                               f"reports={vlm_reports}, confidence={vlm_confidence}")
                    
                    # Score based on VLM findings
                    if vlm_day_sheet and vlm_financial:
                        vlm_score = scoring_weights.get('vlm_verification', 20)
                        subscores["vlm_verification"] = True
                        feedback_parts.append(f"✅ VLM confirms report displayed ({vlm_confidence} confidence)")
                    elif vlm_day_sheet or vlm_financial:
                        vlm_score = scoring_weights.get('vlm_verification', 20) // 2
                        feedback_parts.append(f"⚠️ VLM partial confirmation: {vlm_reasoning[:100]}")
                    elif vlm_reports:
                        vlm_score = scoring_weights.get('vlm_verification', 20) // 4
                        feedback_parts.append(f"⚠️ VLM saw reports navigation but not day sheet")
                    else:
                        feedback_parts.append(f"❌ VLM did not confirm report: {vlm_reasoning[:100]}")
                    
                    # Bonus: if VLM strongly confirms, boost other criteria
                    if vlm_day_sheet and vlm_confidence == 'high':
                        if not subscores["report_generated"]:
                            score += scoring_weights.get('report_generated', 25) // 2
                            feedback_parts.append("⚠️ VLM evidence boosted report score")
                else:
                    feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
                
        except ImportError as e:
            logger.warning(f"VLM utilities not available: {e}")
            feedback_parts.append("⚠️ VLM verification skipped (utilities not available)")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for verification")
    
    score += vlm_score

    # ==================================================================
    # FINAL SCORING
    # ==================================================================
    # Cap score at 100
    score = min(100, score)
    
    # Determine pass/fail
    # Must have at least 60 points AND some evidence of report access
    key_criteria_met = (
        subscores["report_generated"] or 
        subscores["vlm_verification"] or
        (subscores["navigated_reports"] and subscores["accessed_financial"])
    )
    
    passed = score >= 60 and key_criteria_met

    # If no activity at all, definitely fail
    if current_log_count <= initial_log_count and not subscores["vlm_verification"]:
        passed = False
        feedback_parts.insert(0, "❌ FAIL: No system activity detected")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "task_duration_seconds": task_end - task_start,
            "log_entries_added": current_log_count - initial_log_count,
            "window_title": window_title,
            "task_date": task_date
        }
    }