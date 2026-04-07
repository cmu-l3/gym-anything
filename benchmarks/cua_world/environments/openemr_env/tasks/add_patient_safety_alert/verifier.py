#!/usr/bin/env python3
"""
Verifier for Add Patient Safety Alert task in OpenEMR

Verifies that a safety alert for "Difficult Venipuncture" was added to
patient Faye Conn's (pid=4) chart with appropriate clinical details.

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_patient_safety_alert(traj, env_info, task_info):
    """
    Verify that a patient safety alert was correctly added.

    Scoring (100 points total):
    - Alert record exists for correct patient: 30 points
    - Alert created during task (anti-gaming): 10 points
    - Alert type/title contains venipuncture keywords: 20 points
    - Clinical details present in comments: 15 points
    - Alert is marked as active: 10 points
    - VLM verification of alert visibility: 15 points

    Passing threshold: 65 points with alert_exists and correct_type both satisfied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    alert_keywords = metadata.get('alert_keywords', ['venipuncture', 'iv', 'access', 'needle', 'vein'])
    clinical_keywords = metadata.get('clinical_keywords', ['scar', 'butterfly', 'hand', 'arm', 'dorsum'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/patient_alert_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "alert_exists": False,
            "correct_patient": False,
            "created_during_task": False,
            "alert_type_correct": False,
            "clinical_details": False,
            "alert_active": False,
            "vlm_verified": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_alert_count = result.get('initial_alert_count', 0)
        current_alert_count = result.get('current_alert_count', 0)
        initial_lists_count = result.get('initial_lists_count', 0)
        current_lists_count = result.get('current_lists_count', 0)
        existing_venipuncture = result.get('existing_venipuncture_alert', '')
        alert_found = result.get('alert_found', False)
        alert_data = result.get('alert', {})
        validation = result.get('validation', {})

        logger.info(f"Result: pid={patient_pid}, initial_alerts={initial_alert_count}, "
                   f"current_alerts={current_alert_count}, found={alert_found}")
        logger.info(f"Alert data: {alert_data}")

        # CRITERION 1: Correct patient (included in alert_exists check)
        if patient_pid == expected_pid:
            subscores["correct_patient"] = True
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Alert verification failed: wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Alert exists (30 points)
        if alert_found:
            score += 30
            subscores["alert_exists"] = True
            feedback_parts.append(f"✓ Alert entry found for patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ No alert found for patient pid={expected_pid}")
            # Check if any new entries were added at all
            if current_lists_count > initial_lists_count:
                feedback_parts.append(f"Note: {current_lists_count - initial_lists_count} new list entries added, but none match alert criteria")
            else:
                feedback_parts.append("No new entries were added to patient's record")
            
            # Attempt VLM verification as fallback
            vlm_result = _verify_via_vlm(traj, env_info)
            if vlm_result.get('alert_visible', False):
                score += 15
                subscores["vlm_verified"] = True
                feedback_parts.append("✓ VLM detected alert in UI (partial credit)")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Alert created during task - anti-gaming (10 points)
        # Check if new entries were added
        new_entries_added = validation.get('new_entry_added', False)
        if new_entries_added or current_lists_count > initial_lists_count:
            # Also check if there was a pre-existing venipuncture alert (gaming detection)
            if existing_venipuncture and existing_venipuncture.strip():
                feedback_parts.append("⚠ Pre-existing venipuncture alert detected - may not be newly created")
                score += 5  # Partial credit
            else:
                score += 10
                subscores["created_during_task"] = True
                feedback_parts.append("✓ Alert was created during task execution")
        else:
            feedback_parts.append("⚠ Could not confirm alert was newly created")

        # CRITERION 4: Alert type/title contains venipuncture keywords (20 points)
        alert_title = alert_data.get('title', '').lower()
        alert_comments = alert_data.get('comments', '').lower()
        alert_type = alert_data.get('type', '').lower()
        combined_text = f"{alert_title} {alert_comments} {alert_type}"

        has_venipuncture_keyword = validation.get('has_venipuncture_keyword', False)
        if not has_venipuncture_keyword:
            # Double-check with our own keyword matching
            for keyword in alert_keywords:
                if keyword.lower() in combined_text:
                    has_venipuncture_keyword = True
                    break

        if has_venipuncture_keyword:
            score += 20
            subscores["alert_type_correct"] = True
            feedback_parts.append(f"✓ Alert contains venipuncture-related keyword")
        else:
            # Check for partial matches
            partial_match = any(kw[:4].lower() in combined_text for kw in alert_keywords if len(kw) >= 4)
            if partial_match:
                score += 10
                feedback_parts.append("~ Alert has partial keyword match (partial credit)")
            else:
                feedback_parts.append(f"✗ Alert title/comments missing venipuncture keywords")
                feedback_parts.append(f"  Title: '{alert_data.get('title', 'N/A')}'")

        # CRITERION 5: Clinical details present (15 points)
        has_clinical_detail = validation.get('has_clinical_detail', False)
        if not has_clinical_detail:
            # Double-check with our own keyword matching
            for keyword in clinical_keywords:
                if keyword.lower() in combined_text:
                    has_clinical_detail = True
                    break

        if has_clinical_detail:
            score += 15
            subscores["clinical_details"] = True
            feedback_parts.append("✓ Clinical details present in alert")
        else:
            # Check if comments have any substantive content
            comments = alert_data.get('comments', '')
            if len(comments) > 20:
                score += 7
                feedback_parts.append("~ Some clinical details present (partial credit)")
            else:
                feedback_parts.append("✗ Clinical details missing or insufficient")

        # CRITERION 6: Alert is active (10 points)
        is_active = validation.get('is_active', False)
        activity = alert_data.get('activity', '')
        if is_active or activity == '1' or activity == '' or activity is None:
            score += 10
            subscores["alert_active"] = True
            feedback_parts.append("✓ Alert is marked as active")
        else:
            feedback_parts.append(f"✗ Alert may not be active (activity={activity})")

        # CRITERION 7: VLM verification (15 points)
        vlm_result = _verify_via_vlm(traj, env_info)
        if vlm_result.get('alert_visible', False):
            score += 15
            subscores["vlm_verified"] = True
            feedback_parts.append("✓ VLM confirmed alert visible in UI")
        elif vlm_result.get('patient_chart_visible', False):
            score += 5
            feedback_parts.append("~ Patient chart visible in UI (partial VLM credit)")
        else:
            feedback_parts.append("~ VLM could not confirm alert visibility")

        # Determine pass/fail
        # Must have: alert exists AND (correct type OR clinical details)
        key_criteria = subscores["alert_exists"] and (subscores["alert_type_correct"] or subscores["clinical_details"])
        passed = score >= 65 and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "alert_title": alert_data.get('title', ''),
                "alert_type": alert_data.get('type', ''),
                "has_venipuncture_keyword": has_venipuncture_keyword,
                "has_clinical_detail": has_clinical_detail
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        # Attempt VLM-only verification
        vlm_result = _verify_via_vlm(traj, env_info)
        if vlm_result.get('alert_visible', False):
            return {
                "passed": False,
                "score": 25,
                "feedback": "Database verification failed, but VLM detected alert in UI",
                "subscores": {"vlm_verified": True}
            }
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - could not verify alert creation"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse verification data: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def _verify_via_vlm(traj, env_info):
    """
    Use VLM to verify alert visibility in trajectory screenshots.
    
    Returns dict with verification results.
    """
    result = {
        "alert_visible": False,
        "patient_chart_visible": False,
        "confidence": "low",
        "reasoning": ""
    }
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return result
    
    try:
        # Import trajectory utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames and final screenshot
        frames = sample_trajectory_frames(traj, n=4) if traj else []
        final_screenshot = get_final_screenshot(traj) if traj else None
        
        if not frames and not final_screenshot:
            logger.warning("No screenshots available for VLM verification")
            return result
        
        # Combine frames for comprehensive verification
        images_to_check = frames + ([final_screenshot] if final_screenshot else [])
        
        prompt = """You are verifying if a computer agent successfully added a patient safety alert in OpenEMR (Electronic Health Records system).

TASK: Add a "Difficult Venipuncture" safety alert to patient Faye Conn's chart.

Examine these screenshots and determine:
1. Is this OpenEMR or a similar Electronic Health Records interface?
2. Is a patient chart visible (showing patient name, demographics, or medical information)?
3. Can you see any indication of an alert, warning, or flag being added or displayed?
   - Look for: Alert icons, warning banners, flag indicators
   - Look for: Text mentioning "venipuncture", "IV access", "difficult", "alert", "warning"
   - Look for: Success messages indicating something was saved/added
4. Is the patient name "Faye Conn" visible anywhere?

Respond in JSON format:
{
    "is_ehr_interface": true/false,
    "patient_chart_visible": true/false,
    "patient_name_visible": true/false,
    "alert_or_warning_visible": true/false,
    "success_message_visible": true/false,
    "venipuncture_text_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observe"
}
"""
        
        vlm_response = query_vlm(
            prompt=prompt,
            images=images_to_check
        )
        
        if vlm_response and vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            
            # Determine if alert was visible
            alert_visible = (
                parsed.get('alert_or_warning_visible', False) or
                parsed.get('venipuncture_text_visible', False) or
                (parsed.get('success_message_visible', False) and parsed.get('patient_chart_visible', False))
            )
            
            result["alert_visible"] = alert_visible
            result["patient_chart_visible"] = parsed.get('patient_chart_visible', False)
            result["confidence"] = parsed.get('confidence', 'low')
            result["reasoning"] = parsed.get('reasoning', '')
            
            logger.info(f"VLM result: alert_visible={alert_visible}, chart_visible={result['patient_chart_visible']}")
        else:
            logger.warning(f"VLM query failed: {vlm_response.get('error', 'Unknown error')}")
            
    except ImportError:
        logger.warning("Could not import VLM utilities")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
    
    return result


# For standalone testing
if __name__ == "__main__":
    # Test with mock data
    test_result = {
        "patient_pid": 4,
        "alert_found": True,
        "alert": {
            "id": "123",
            "type": "alert",
            "title": "Difficult Venipuncture",
            "comments": "Multiple scars on arms, use butterfly needle",
            "activity": "1"
        },
        "validation": {
            "has_venipuncture_keyword": True,
            "has_clinical_detail": True,
            "is_active": True,
            "new_entry_added": True
        },
        "initial_lists_count": 5,
        "current_lists_count": 6
    }
    
    print("Test result structure:")
    print(json.dumps(test_result, indent=2))