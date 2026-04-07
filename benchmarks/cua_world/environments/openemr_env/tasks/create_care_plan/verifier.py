#!/usr/bin/env python3
"""
Verifier for Create Care Plan task in OpenEMR

Verifies that a care plan was created for patient Jayme Kunze (pid=5)
with appropriate health concern, goal, and intervention for diabetes management.

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


def verify_create_care_plan(traj, env_info, task_info):
    """
    Verify that a care plan was created for the diabetic patient.

    Scoring (100 points total):
    - Care plan record exists: 25 points
    - Newly created (anti-gaming): 15 points
    - Health concern documented (diabetes): 15 points
    - Goal with HbA1c target: 20 points
    - Intervention documented: 15 points
    - Target date set: 10 points

    Passing threshold: 70 points with care plan existing
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Jayme')
    expected_lname = metadata.get('patient_lname', 'Kunze')
    goal_keywords = metadata.get('expected_goal_keywords', ['hba1c', 'a1c', '7', 'glucose', 'diabetes'])
    intervention_keywords = metadata.get('expected_intervention_keywords', ['adherence', 'monitor', 'counsel', 'glucose', 'medication'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_careplan_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "careplan_exists": False,
            "newly_created": False,
            "health_concern": False,
            "goal_documented": False,
            "intervention_documented": False,
            "target_date_set": False
        }

        # Extract data from export
        patient_pid = result.get('patient_pid', 0)
        initial_state = result.get('initial_state', {})
        current_state = result.get('current_state', {})
        detection = result.get('detection', {})
        content = result.get('content', {})
        task_start = result.get('task_start_time', 0)
        task_end = result.get('task_end_time', 0)

        logger.info(f"Verifying care plan for patient pid={patient_pid}")
        logger.info(f"Initial state: {initial_state}")
        logger.info(f"Current state: {current_state}")
        logger.info(f"Detection: {detection}")

        # Verify correct patient
        if patient_pid != expected_pid:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong patient! Expected pid={expected_pid}, got {patient_pid}",
                "subscores": subscores
            }

        # CRITERION 1: Care plan record exists (25 points)
        initial_forms = initial_state.get('forms_count', 0)
        current_forms = current_state.get('forms_count', 0)
        initial_lists = initial_state.get('careplan_lists_count', 0)
        current_lists = current_state.get('careplan_lists_count', 0)
        initial_all_lists = initial_state.get('total_lists_count', 0)
        current_all_lists = current_state.get('total_lists_count', 0)
        form_careplan_count = current_state.get('form_careplan_table_count', 0)

        careplan_found = detection.get('careplan_found', False)

        # Check multiple indicators
        forms_increased = current_forms > initial_forms
        lists_increased = current_lists > initial_lists
        all_lists_increased = current_all_lists > initial_all_lists
        has_form_careplan = form_careplan_count > 0

        if careplan_found or forms_increased or lists_increased or has_form_careplan:
            score += 25
            subscores["careplan_exists"] = True
            feedback_parts.append(f"✓ Care plan record found (forms: {initial_forms}→{current_forms}, lists: {initial_lists}→{current_lists})")
        elif all_lists_increased:
            # Partial credit if any new list entries were added
            score += 15
            subscores["careplan_exists"] = True
            feedback_parts.append(f"⚠ New list entries added (total: {initial_all_lists}→{current_all_lists}), may be care plan related")
        else:
            feedback_parts.append(f"✗ No care plan record detected (forms: {initial_forms}→{current_forms}, lists: {initial_lists}→{current_lists})")

        # CRITERION 2: Newly created - anti-gaming check (15 points)
        if forms_increased or lists_increased or all_lists_increased:
            score += 15
            subscores["newly_created"] = True
            feedback_parts.append("✓ New entries created during task (anti-gaming check passed)")
        else:
            feedback_parts.append("✗ No new entries detected during task execution")

        # CRITERION 3: Health concern documented - diabetes (15 points)
        health_concern_found = detection.get('health_concern_found', False)
        if health_concern_found:
            score += 15
            subscores["health_concern"] = True
            feedback_parts.append("✓ Diabetes health concern documented")
        else:
            # Check if goal text mentions diabetes
            goal_text = content.get('goal_text', '').lower()
            if 'diabetes' in goal_text or 'diabetic' in goal_text:
                score += 10
                subscores["health_concern"] = True
                feedback_parts.append("⚠ Diabetes mentioned in goal (partial credit)")
            else:
                feedback_parts.append("✗ Diabetes health concern not explicitly documented")

        # CRITERION 4: Goal with HbA1c target (20 points)
        goal_found = detection.get('goal_found', False)
        goal_text = content.get('goal_text', '').lower()

        # Check for HbA1c-related keywords
        has_hba1c = any(kw in goal_text for kw in ['hba1c', 'a1c', 'hemoglobin'])
        has_target = any(char.isdigit() for char in goal_text) and ('7' in goal_text or '%' in goal_text)

        if goal_found and has_hba1c:
            score += 20
            subscores["goal_documented"] = True
            feedback_parts.append(f"✓ Goal with HbA1c target documented: '{goal_text[:50]}...'")
        elif goal_found:
            score += 10
            subscores["goal_documented"] = True
            feedback_parts.append(f"⚠ Goal documented but HbA1c not explicitly mentioned: '{goal_text[:50]}...'")
        elif has_hba1c or has_target:
            score += 10
            subscores["goal_documented"] = True
            feedback_parts.append("⚠ HbA1c-related content found (partial credit)")
        else:
            feedback_parts.append("✗ No goal with HbA1c target found")

        # CRITERION 5: Intervention documented (15 points)
        intervention_found = detection.get('intervention_found', False)
        intervention_text = content.get('intervention_text', '').lower()

        # Check for intervention keywords
        has_intervention_keywords = any(kw in intervention_text for kw in intervention_keywords)

        if intervention_found and has_intervention_keywords:
            score += 15
            subscores["intervention_documented"] = True
            feedback_parts.append(f"✓ Intervention documented: '{intervention_text[:50]}...'")
        elif intervention_found:
            score += 10
            subscores["intervention_documented"] = True
            feedback_parts.append(f"⚠ Intervention documented: '{intervention_text[:50]}...'")
        elif has_intervention_keywords:
            score += 7
            feedback_parts.append("⚠ Intervention keywords found (partial credit)")
        else:
            feedback_parts.append("✗ No intervention documented")

        # CRITERION 6: Target date set (10 points)
        target_date_set = detection.get('target_date_set', False)
        if target_date_set:
            score += 10
            subscores["target_date_set"] = True
            feedback_parts.append("✓ Target date set for goal")
        else:
            feedback_parts.append("✗ No target date set")

        # VLM verification for additional context (if available)
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Sample frames from trajectory to verify workflow
                frames = sample_trajectory_frames(traj, n=5)
                final = get_final_screenshot(traj)
                
                if frames or final:
                    images = (frames or []) + ([final] if final else [])
                    vlm_prompt = """Analyze these screenshots from an OpenEMR task.

The agent was asked to create a care plan for a diabetic patient.

Look for evidence of:
1. Patient Jayme Kunze being selected/viewed
2. Navigation to care plan or clinical forms
3. Entry of goal related to HbA1c or diabetes
4. Entry of intervention related to medication adherence or monitoring
5. Successful save/submission

Respond in JSON:
{
    "patient_chart_accessed": true/false,
    "care_plan_form_visible": true/false,
    "goal_entry_visible": true/false,
    "save_action_visible": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        # Bonus points for VLM verification
                        if parsed.get('care_plan_form_visible') and parsed.get('goal_entry_visible'):
                            if score < 100:
                                bonus = min(5, 100 - score)
                                score += bonus
                                feedback_parts.append(f"✓ VLM verified care plan form interaction (+{bonus} bonus)")
                        
                        logger.info(f"VLM verification: {parsed}")
                        
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        # Determine pass/fail
        # Must have care plan existing and score >= 70
        key_criteria_met = subscores["careplan_exists"]
        passed = score >= 70 and key_criteria_met

        # Build final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\nTotal Score: {score}/100"
        feedback += f"\nPassed: {passed}"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "initial_state": initial_state,
                "current_state": current_state,
                "detection": detection,
                "task_duration_seconds": task_end - task_start if task_end and task_start else 0
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed",
            "subscores": {
                "careplan_exists": False,
                "newly_created": False,
                "health_concern": False,
                "goal_documented": False,
                "intervention_documented": False,
                "target_date_set": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


if __name__ == "__main__":
    # For testing
    print("Care Plan Verifier - run via task framework")
    print("Expected: Patient Jayme Kunze (pid=5)")
    print("Expected: Care plan with HbA1c goal and intervention")