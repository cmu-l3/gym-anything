#!/usr/bin/env python3
"""
Verifier for Generate Accounts Receivable Aging Report task in OpenEMR.

Verification Strategy:
1. PRIMARY: VLM analysis of trajectory frames to verify workflow progression
2. SECONDARY: VLM analysis of final screenshot to verify report is displayed
3. TERTIARY: Check exported state data for indicators of success

Scoring Criteria (100 points total):
- Successfully logged in (not on login page): 15 points
- Navigated to Reports section: 20 points
- Found correct report type (Collections/Aging): 20 points
- Report generated and displayed: 25 points
- Aging columns visible in report: 15 points
- Patient/balance data displayed: 5 points

Pass Threshold: 60 points with report_generated criterion met
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# VLM prompts for verification
TRAJECTORY_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully navigated OpenEMR to generate an Accounts Receivable Aging Report.

Analyze this sequence of screenshots showing the agent's workflow progression.

Look for evidence of these steps:
1. LOGGED IN: Did the agent get past the login page? (OpenEMR dashboard or any internal page visible)
2. REPORTS NAVIGATION: Did the agent click on "Reports" menu or navigate to a reports section?
3. BILLING/FINANCIAL: Did the agent access billing or financial reports specifically?
4. AGING REPORT: Is there a report displayed showing patient balances organized by aging periods (0-30, 31-60, 61-90, 91-120, 120+ days)?

Answer in JSON format:
{
    "logged_in": true/false,
    "navigated_to_reports": true/false,
    "accessed_billing_reports": true/false,
    "aging_report_visible": true/false,
    "workflow_progression_seen": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the workflow"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying if an Accounts Receivable Aging Report is displayed in OpenEMR.

Analyze this screenshot and determine:

1. Is this OpenEMR (electronic health records system interface)?
2. Is the user logged in (NOT on login page)?
3. Is this showing a REPORT view (any kind of report, not patient chart)?
4. Specifically, is this an AGING or COLLECTIONS report showing:
   - Patient names and/or account information
   - Dollar amounts ($) representing balances
   - Columns for aging periods (like "0-30", "31-60", "61-90", "91-120", "120+" days OR "Current", "30 Days", "60 Days", etc.)
   - Financial/billing data organized in a table format

5. Can you see actual financial data (not just an empty report or menu)?

Answer in JSON format:
{
    "is_openemr": true/false,
    "is_logged_in": true/false,
    "is_report_view": true/false,
    "is_aging_collections_report": true/false,
    "has_aging_columns": true/false,
    "has_financial_data": true/false,
    "has_patient_info": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


def verify_aging_report(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully generated an Accounts Receivable Aging Report.
    
    Uses trajectory-based VLM verification to ensure actual work was done,
    not just final screenshot spoofing.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info with copy_from_env and query_vlm functions
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    score = 0
    feedback_parts = []
    subscores = {
        "logged_in": False,
        "navigated_to_reports": False,
        "correct_report_type": False,
        "report_generated": False,
        "aging_columns_visible": False,
        "patient_data_displayed": False
    }
    result_details = {}
    
    # Get scoring weights from metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {
        "logged_in": 15,
        "navigated_to_reports": 20,
        "correct_report_type": 20,
        "report_generated": 25,
        "aging_columns_visible": 15,
        "patient_data_displayed": 5
    })
    
    # =========================================================================
    # STEP 1: Load exported result data
    # =========================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/aging_report_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                export_result = json.load(f)
            result_details['export_result'] = export_result
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}
    
    # Basic anti-gaming checks from export data
    firefox_running = export_result.get('firefox_running', False)
    past_login = export_result.get('past_login_page', False)
    title_indicates_report = export_result.get('title_indicates_report', False)
    task_duration = export_result.get('task_duration_seconds', 0)
    
    # If Firefox isn't running, agent likely did nothing
    if not firefox_running:
        feedback_parts.append("❌ Firefox not running - task not attempted")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": result_details
        }
    
    # If task completed in < 5 seconds, likely didn't do anything meaningful
    if task_duration < 5:
        feedback_parts.append(f"⚠️ Task completed too quickly ({task_duration}s) - suspicious")
    
    # =========================================================================
    # STEP 2: VLM Trajectory Verification (PRIMARY)
    # =========================================================================
    trajectory_result = None
    if query_vlm:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames across the trajectory to verify workflow
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) > 0:
                trajectory_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                result_details['trajectory_vlm'] = trajectory_result
                
                if trajectory_result.get('success'):
                    parsed = trajectory_result.get('parsed', {})
                    
                    # Check workflow progression
                    if parsed.get('logged_in', False):
                        score += weights.get('logged_in', 15)
                        subscores['logged_in'] = True
                        feedback_parts.append("✅ Successfully logged in")
                    
                    if parsed.get('navigated_to_reports', False):
                        score += weights.get('navigated_to_reports', 20)
                        subscores['navigated_to_reports'] = True
                        feedback_parts.append("✅ Navigated to Reports section")
                    
                    if parsed.get('accessed_billing_reports', False):
                        score += int(weights.get('correct_report_type', 20) * 0.5)
                        feedback_parts.append("✅ Accessed billing/financial reports")
                    
                    if parsed.get('aging_report_visible', False):
                        score += int(weights.get('report_generated', 25) * 0.5)
                        feedback_parts.append("✅ Aging report visible in trajectory")
                    
                    if parsed.get('workflow_progression_seen', False):
                        feedback_parts.append("✅ Workflow progression verified")
                    
                    logger.info(f"Trajectory VLM result: {parsed}")
            else:
                logger.warning("No trajectory frames available")
                feedback_parts.append("⚠️ No trajectory frames for verification")
                
        except ImportError:
            logger.warning("Could not import trajectory sampling utilities")
        except Exception as e:
            logger.warning(f"Trajectory VLM verification failed: {e}")
    
    # =========================================================================
    # STEP 3: VLM Final Screenshot Verification (SECONDARY)
    # =========================================================================
    final_screenshot_result = None
    if query_vlm:
        try:
            # Get final screenshot
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                final_screenshot_result = query_vlm(
                    prompt=FINAL_SCREENSHOT_PROMPT,
                    image=final_screenshot
                )
                result_details['final_screenshot_vlm'] = final_screenshot_result
                
                if final_screenshot_result.get('success'):
                    parsed = final_screenshot_result.get('parsed', {})
                    confidence = parsed.get('confidence', 'low')
                    
                    # Apply confidence multiplier
                    conf_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.5}.get(confidence, 0.5)
                    
                    # Check final state criteria
                    if parsed.get('is_openemr', False) and parsed.get('is_logged_in', False):
                        if not subscores['logged_in']:
                            score += int(weights.get('logged_in', 15) * conf_mult)
                            subscores['logged_in'] = True
                            feedback_parts.append("✅ Logged into OpenEMR (final)")
                    
                    if parsed.get('is_report_view', False):
                        if not subscores['navigated_to_reports']:
                            score += int(weights.get('navigated_to_reports', 20) * conf_mult * 0.5)
                            feedback_parts.append("✅ Report view visible")
                    
                    if parsed.get('is_aging_collections_report', False):
                        subscores['correct_report_type'] = True
                        subscores['report_generated'] = True
                        # Add remaining points for correct report
                        if not subscores.get('correct_report_partial'):
                            score += int(weights.get('correct_report_type', 20) * conf_mult)
                            score += int(weights.get('report_generated', 25) * conf_mult)
                        feedback_parts.append("✅ Aging/Collections report displayed")
                    
                    if parsed.get('has_aging_columns', False):
                        subscores['aging_columns_visible'] = True
                        score += int(weights.get('aging_columns_visible', 15) * conf_mult)
                        feedback_parts.append("✅ Aging columns visible (0-30, 31-60, etc.)")
                    
                    if parsed.get('has_financial_data', False) or parsed.get('has_patient_info', False):
                        subscores['patient_data_displayed'] = True
                        score += int(weights.get('patient_data_displayed', 5) * conf_mult)
                        feedback_parts.append("✅ Financial/patient data displayed")
                    
                    reasoning = parsed.get('reasoning', '')
                    if reasoning:
                        feedback_parts.append(f"VLM: {reasoning}")
                    
                    logger.info(f"Final screenshot VLM result: {parsed}")
                else:
                    feedback_parts.append(f"⚠️ VLM analysis failed: {final_screenshot_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No final screenshot available")
                
        except ImportError:
            logger.warning("Could not import VLM utilities")
        except Exception as e:
            logger.warning(f"Final screenshot VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ Screenshot analysis error: {str(e)}")
    
    # =========================================================================
    # STEP 4: Fallback checks from export data
    # =========================================================================
    if not query_vlm or (not trajectory_result and not final_screenshot_result):
        # No VLM available - use heuristics from export data
        feedback_parts.append("⚠️ VLM not available - using heuristic verification")
        
        if past_login:
            if not subscores['logged_in']:
                score += weights.get('logged_in', 15)
                subscores['logged_in'] = True
                feedback_parts.append("✅ Past login page (heuristic)")
        
        if title_indicates_report:
            score += int(weights.get('navigated_to_reports', 20) * 0.5)
            subscores['navigated_to_reports'] = True
            feedback_parts.append("✅ Window title indicates report view")
        
        report_activity = export_result.get('report_activity_detected', False)
        if report_activity:
            score += int(weights.get('report_generated', 25) * 0.3)
            feedback_parts.append("✅ Report activity detected in logs")
    
    # =========================================================================
    # STEP 5: Calculate final result
    # =========================================================================
    # Cap score at 100
    score = min(100, score)
    
    # Determine pass/fail
    # Must have report_generated OR (correct_report_type AND aging_columns_visible)
    key_criteria_met = (
        subscores['report_generated'] or 
        (subscores['correct_report_type'] and subscores['aging_columns_visible'])
    )
    passed = score >= 60 and key_criteria_met
    
    # If nothing was verified, ensure failure
    if not any(subscores.values()):
        passed = False
        score = 0
        feedback_parts.append("❌ No verification criteria met - task not completed")
    
    # Build final feedback
    if passed:
        feedback_parts.insert(0, f"✅ PASSED (Score: {score}/100)")
    else:
        feedback_parts.insert(0, f"❌ FAILED (Score: {score}/100)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": result_details
    }