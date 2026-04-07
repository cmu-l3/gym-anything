#!/usr/bin/env python3
"""
Verifier for Review and Acknowledge Lab Results task in OpenEMR

Verification Strategy:
1. PRIMARY: Check database for results marked as reviewed/final
2. SECONDARY: Check for follow-up notes with appropriate content
3. ANTI-GAMING: Timestamp validation to ensure work was done during task
4. VLM: Trajectory verification to confirm proper workflow

Scoring (100 points):
- Correct patient found: 15 points
- Lab results accessed: 20 points
- Results marked reviewed: 30 points
- Follow-up note added: 25 points
- Timestamp valid: 10 points

Pass threshold: 65 points with results_marked_reviewed achieved
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_review_lab_results(traj, env_info, task_info):
    """
    Verify that lab results were reviewed and acknowledged properly.
    
    Uses copy_from_env to read exported result data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    expected_fname = metadata.get('patient_fname', 'Abraham')
    expected_lname = metadata.get('patient_lname', 'Gutmann')
    expected_keywords = metadata.get('expected_note_keywords', 
        ['results', 'reviewed', 'lipid', 'acceptable', 'continue', 'statin', 'recheck'])
    scoring_weights = metadata.get('scoring_weights', {
        'correct_patient_found': 15,
        'lab_results_accessed': 20,
        'results_marked_reviewed': 30,
        'followup_note_added': 25,
        'timestamp_valid': 10
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/review_lab_results_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not read result file: {e}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient_found": False,
            "lab_results_accessed": False,
            "results_marked_reviewed": False,
            "followup_note_added": False,
            "timestamp_valid": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        order_status = result.get('order_status', 'pending')
        total_results = result.get('total_results', 0)
        reviewed_count = result.get('reviewed_results_count', 0)
        all_reviewed = result.get('all_results_reviewed', False)
        results_accessed = result.get('results_accessed', False)
        new_note_added = result.get('new_note_added', False)
        followup_note = result.get('followup_note', '')
        result_comments = result.get('result_comments', '')
        note_has_keywords = result.get('note_has_keywords', False)
        firefox_running = result.get('firefox_running', False)
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)

        logger.info(f"Verification data: pid={patient_pid}, order_status={order_status}, "
                   f"reviewed={reviewed_count}/{total_results}, all_reviewed={all_reviewed}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += scoring_weights.get('correct_patient_found', 15)
            subscores["correct_patient_found"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient - expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Lab results accessed (20 points)
        if results_accessed or order_status != 'pending' or reviewed_count > 0:
            score += scoring_weights.get('lab_results_accessed', 20)
            subscores["lab_results_accessed"] = True
            feedback_parts.append(f"✅ Lab results accessed (order status: {order_status})")
        else:
            feedback_parts.append("❌ Lab results do not appear to have been accessed")

        # CRITERION 3: Results marked as reviewed (30 points) - PRIMARY CRITERION
        if all_reviewed and total_results > 0:
            score += scoring_weights.get('results_marked_reviewed', 30)
            subscores["results_marked_reviewed"] = True
            feedback_parts.append(f"✅ All {total_results} results marked as reviewed")
        elif reviewed_count > 0:
            # Partial credit for partial review
            partial_score = int((reviewed_count / max(total_results, 1)) * 
                               scoring_weights.get('results_marked_reviewed', 30))
            score += partial_score
            if reviewed_count >= total_results / 2:
                subscores["results_marked_reviewed"] = True  # At least half reviewed
            feedback_parts.append(f"⚠️ Partial review: {reviewed_count}/{total_results} results reviewed (+{partial_score})")
        elif order_status in ['complete', 'reviewed', 'reported', 'final']:
            # Order status change indicates review even if individual results not updated
            score += scoring_weights.get('results_marked_reviewed', 30) // 2
            subscores["results_marked_reviewed"] = True
            feedback_parts.append(f"⚠️ Order status changed to '{order_status}' (partial credit)")
        else:
            feedback_parts.append(f"❌ Results not marked as reviewed (status: {order_status}, reviewed: {reviewed_count}/{total_results})")

        # CRITERION 4: Follow-up note added (25 points)
        note_content = (followup_note + " " + result_comments).lower()
        
        if new_note_added and note_has_keywords:
            score += scoring_weights.get('followup_note_added', 25)
            subscores["followup_note_added"] = True
            feedback_parts.append("✅ Follow-up note added with appropriate clinical content")
        elif new_note_added:
            # Note added but may not have all keywords - partial credit
            score += scoring_weights.get('followup_note_added', 25) // 2
            feedback_parts.append("⚠️ Follow-up note added but missing some expected keywords")
        elif note_has_keywords and result_comments:
            # Keywords found in result comments instead of separate note
            score += scoring_weights.get('followup_note_added', 25) * 3 // 4
            subscores["followup_note_added"] = True
            feedback_parts.append("✅ Clinical notes found in result comments")
        elif note_content.strip():
            # Some text present - minimal credit
            keywords_found = sum(1 for kw in expected_keywords if kw.lower() in note_content)
            if keywords_found >= 2:
                score += scoring_weights.get('followup_note_added', 25) // 2
                feedback_parts.append(f"⚠️ Some clinical content found ({keywords_found} keywords)")
            else:
                feedback_parts.append("❌ Note/comment present but lacks clinical content")
        else:
            feedback_parts.append("❌ No follow-up note or clinical comment added")

        # CRITERION 5: Timestamp validation - anti-gaming (10 points)
        if task_start > 0 and task_end > 0:
            task_duration = task_end - task_start
            if task_duration >= 10:  # At least 10 seconds of work
                score += scoring_weights.get('timestamp_valid', 10)
                subscores["timestamp_valid"] = True
                feedback_parts.append(f"✅ Task completed in valid timeframe ({task_duration}s)")
            else:
                feedback_parts.append(f"⚠️ Task completed suspiciously fast ({task_duration}s)")
        else:
            feedback_parts.append("⚠️ Could not validate task timestamps")

        # Calculate final result
        pass_threshold = 65
        key_criterion_met = subscores["results_marked_reviewed"]
        
        passed = score >= pass_threshold and key_criterion_met

        # VLM verification for trajectory (additional validation)
        vlm_feedback = ""
        query_vlm = env_info.get('query_vlm')
        if query_vlm and not passed:
            # Only use VLM if task appears to have failed - might catch edge cases
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                frames = sample_trajectory_frames(traj, n=5)
                final_screenshot = get_final_screenshot(traj)
                
                if frames or final_screenshot:
                    vlm_prompt = """You are verifying if an agent reviewed lab results in OpenEMR (medical records system).

Look at these screenshots and determine:
1. Did the agent navigate to a lab results or procedures section?
2. Did the agent view/open specific lab values (cholesterol, HDL, LDL, etc.)?
3. Did the agent mark results as reviewed or add any notes?
4. Was the patient Abraham Gutmann selected?

Respond in JSON format:
{
    "navigated_to_results": true/false,
    "viewed_lab_values": true/false,
    "took_review_action": true/false,
    "correct_patient": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
                    images = (frames or []) + ([final_screenshot] if final_screenshot else [])
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images[:6])
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('took_review_action') and parsed.get('confidence') in ['medium', 'high']:
                            # VLM suggests task was completed even if database doesn't show it
                            score += 10
                            vlm_feedback = " | VLM verification suggests task completion"
                            if score >= pass_threshold:
                                passed = True
                        logger.info(f"VLM result: {parsed}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        # Build final feedback
        feedback = " | ".join(feedback_parts) + vlm_feedback
        
        if passed:
            feedback = f"✅ Task PASSED (score: {score}/100) | " + feedback
        else:
            if not key_criterion_met:
                feedback = f"❌ Task FAILED - results not marked as reviewed (score: {score}/100) | " + feedback
            else:
                feedback = f"❌ Task FAILED - score below threshold (score: {score}/100, need {pass_threshold}) | " + feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "order_status": order_status,
                "reviewed_count": reviewed_count,
                "total_results": total_results,
                "note_added": new_note_added,
                "firefox_running": firefox_running
            }
        }

    except Exception as e:
        logger.exception(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


# For testing
if __name__ == "__main__":
    # Mock test
    print("Verifier module loaded successfully")
    print("Function: verify_review_lab_results")