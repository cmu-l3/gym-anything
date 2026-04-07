#!/usr/bin/env python3
"""
Verifier for Document Assessment and Plan task in OpenEMR

Verifies that the agent documented an Assessment and Plan for patient Jayson Fadel's
hypertension follow-up encounter.

Scoring (100 points total):
- Correct patient context: 15 points
- Encounter exists/accessed: 15 points
- SOAP form created: 20 points
- Assessment documented with content: 20 points
- Plan documented with content: 20 points
- Newly created during task: 10 points

Pass threshold: 70 points (must have SOAP form with assessment OR plan content)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_assessment_plan(traj, env_info, task_info):
    """
    Verify that Assessment and Plan was documented for the patient encounter.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    assessment_keywords = metadata.get('required_assessment_keywords', 
                                       ['hypertension', 'controlled', 'blood pressure'])
    plan_keywords = metadata.get('required_plan_keywords', 
                                 ['continue', 'medication', 'follow-up', 'return', 'lifestyle'])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/assessment_plan_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "encounter_exists": False,
            "soap_form_created": False,
            "assessment_documented": False,
            "plan_documented": False,
            "newly_created": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        soap_form = result.get('soap_form', {})
        encounter = result.get('encounter', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result data: pid={patient_pid}")
        logger.info(f"Initial counts: {initial_counts}")
        logger.info(f"Current counts: {current_counts}")
        logger.info(f"SOAP form: {soap_form}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✓ Correct patient context (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient context (expected pid={expected_pid})")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Task verified for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: Encounter exists (15 points)
        encounter_id = encounter.get('id', '')
        if encounter_id:
            score += 15
            subscores["encounter_exists"] = True
            feedback_parts.append(f"✓ Encounter exists (id={encounter_id})")
        else:
            # Check if encounter count increased
            initial_enc = initial_counts.get('encounter', 0)
            current_enc = current_counts.get('encounter', 0)
            if current_enc > 0:
                score += 10  # Partial credit
                feedback_parts.append(f"✓ Encounter(s) exist for patient")
            else:
                feedback_parts.append("✗ No encounter found for patient")
        
        # CRITERION 3: SOAP form created (20 points)
        soap_found = soap_form.get('found', False)
        soap_id = soap_form.get('id', '')
        
        if soap_found and soap_id:
            score += 20
            subscores["soap_form_created"] = True
            feedback_parts.append(f"✓ SOAP form exists (id={soap_id})")
        else:
            # Check if SOAP count increased
            initial_soap = initial_counts.get('soap', 0)
            current_soap = current_counts.get('soap', 0)
            if current_soap > initial_soap:
                score += 15  # Partial credit
                subscores["soap_form_created"] = True
                feedback_parts.append(f"✓ New SOAP form created (count: {initial_soap} -> {current_soap})")
            elif current_soap > 0:
                score += 10  # Some credit for accessing existing form
                feedback_parts.append(f"~ SOAP form(s) exist but may not be new")
            else:
                feedback_parts.append("✗ No SOAP form found for patient")
        
        # CRITERION 4: Assessment documented (20 points)
        assessment_content = soap_form.get('assessment', '')
        assessment_has_content = validation.get('assessment_has_content', False)
        assessment_keywords_valid = validation.get('assessment_keywords_valid', False)
        
        if assessment_has_content:
            # Base credit for having content
            score += 10
            subscores["assessment_documented"] = True
            feedback_parts.append("✓ Assessment has content")
            
            # Additional credit for relevant keywords
            if assessment_keywords_valid:
                score += 10
                feedback_parts.append("✓ Assessment mentions hypertension/BP status")
            else:
                # Check manually for partial keyword matches
                assessment_lower = assessment_content.lower()
                keyword_count = sum(1 for kw in assessment_keywords if kw.lower() in assessment_lower)
                if keyword_count > 0:
                    score += 5
                    feedback_parts.append(f"~ Assessment has {keyword_count}/{len(assessment_keywords)} expected keywords")
                else:
                    feedback_parts.append("~ Assessment missing hypertension-related keywords")
        else:
            feedback_parts.append("✗ Assessment field is empty or too short")
        
        # CRITERION 5: Plan documented (20 points)
        plan_content = soap_form.get('plan', '')
        plan_has_content = validation.get('plan_has_content', False)
        plan_keywords_valid = validation.get('plan_keywords_valid', False)
        
        if plan_has_content:
            # Base credit for having content
            score += 10
            subscores["plan_documented"] = True
            feedback_parts.append("✓ Plan has content")
            
            # Additional credit for relevant keywords
            if plan_keywords_valid:
                score += 10
                feedback_parts.append("✓ Plan includes treatment plan elements")
            else:
                # Check manually for partial keyword matches
                plan_lower = plan_content.lower()
                keyword_count = sum(1 for kw in plan_keywords if kw.lower() in plan_lower)
                if keyword_count > 0:
                    score += 5
                    feedback_parts.append(f"~ Plan has {keyword_count}/{len(plan_keywords)} expected keywords")
                else:
                    feedback_parts.append("~ Plan missing expected treatment elements")
        else:
            feedback_parts.append("✗ Plan field is empty or too short")
        
        # CRITERION 6: Newly created during task (10 points)
        new_soap_created = validation.get('new_soap_created', False)
        new_encounter_created = validation.get('new_encounter_created', False)
        
        if new_soap_created:
            score += 10
            subscores["newly_created"] = True
            feedback_parts.append("✓ SOAP form newly created during task")
        elif new_encounter_created:
            score += 5  # Partial credit
            feedback_parts.append("~ New encounter created (SOAP may be existing)")
        else:
            # Check if any forms count increased
            initial_forms = initial_counts.get('forms', 0)
            current_forms = current_counts.get('forms', 0)
            if current_forms > initial_forms:
                score += 5
                feedback_parts.append("~ New form activity detected")
            else:
                feedback_parts.append("~ No new documentation detected (may have used existing)")
        
        # VLM verification for trajectory (if available)
        vlm_bonus = 0
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                vlm_result = verify_via_vlm(traj, query_vlm)
                if vlm_result.get('success', False):
                    vlm_bonus = vlm_result.get('bonus_points', 0)
                    feedback_parts.append(f"VLM verification: {vlm_result.get('feedback', 'OK')}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
        
        # Calculate final score (cap at 100)
        final_score = min(100, score + vlm_bonus)
        
        # Determine pass/fail
        # Must have at least SOAP form with some content
        key_criteria = subscores["soap_form_created"] and (
            subscores["assessment_documented"] or subscores["plan_documented"]
        )
        passed = final_score >= 70 and key_criteria
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "assessment_content_length": len(assessment_content),
                "plan_content_length": len(plan_content),
                "soap_id": soap_id,
                "encounter_id": encounter_id
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


def verify_via_vlm(traj, query_vlm):
    """
    Use VLM to verify trajectory shows proper A&P documentation workflow.
    
    Checks trajectory frames (not just final screenshot) to verify work was done.
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "feedback": "No screenshots available"}
        
        # Combine frames for analysis
        images_to_analyze = frames + ([final] if final else [])
        
        prompt = """Analyze these screenshots from an OpenEMR session and determine if the user documented an Assessment and Plan for a patient encounter.

Look for evidence of:
1. Patient Jayson Fadel selected/displayed
2. Navigation to clinical documentation or SOAP form
3. Text entry in Assessment and/or Plan fields
4. Form being saved (confirmation or navigation away)

Respond in JSON format:
{
    "patient_visible": true/false,
    "soap_form_visible": true/false,
    "text_entry_observed": true/false,
    "workflow_complete": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description"
}"""
        
        vlm_response = query_vlm(prompt=prompt, images=images_to_analyze)
        
        if not vlm_response.get('success'):
            return {"success": False, "feedback": "VLM query failed"}
        
        parsed = vlm_response.get('parsed', {})
        
        # Award bonus points based on VLM verification
        bonus = 0
        feedback_parts = []
        
        if parsed.get('patient_visible'):
            bonus += 2
            feedback_parts.append("Patient visible")
        
        if parsed.get('soap_form_visible'):
            bonus += 3
            feedback_parts.append("SOAP form accessed")
        
        if parsed.get('text_entry_observed'):
            bonus += 3
            feedback_parts.append("Text entry observed")
        
        if parsed.get('workflow_complete'):
            bonus += 2
            feedback_parts.append("Workflow appears complete")
        
        return {
            "success": True,
            "bonus_points": bonus,
            "feedback": ", ".join(feedback_parts) if feedback_parts else "No clear evidence",
            "details": parsed
        }
        
    except ImportError:
        logger.warning("VLM utilities not available")
        return {"success": False, "feedback": "VLM utilities not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "feedback": str(e)}


if __name__ == "__main__":
    # Test mode - run with mock data
    print("Document Assessment Plan Verifier")
    print("Run via gym-anything framework for actual verification")