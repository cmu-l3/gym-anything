#!/usr/bin/env python3
"""
Verifier for Document Fall Risk Assessment task in OpenEMR

This verifier checks that a fall risk assessment was properly documented
for patient Lavon Kuvalis (pid=4) using the Morse Fall Scale criteria.

Verification Strategy:
1. Primary: Check database for new forms/notes with fall risk content
2. Secondary: VLM verification of trajectory showing documentation workflow
3. Anti-gaming: Timestamp checks to ensure documentation was created during task
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fall_risk_assessment(traj, env_info, task_info):
    """
    Verify that fall risk assessment was properly documented.
    
    Scoring (100 points total):
    - Patient found/accessed: 15 points
    - New documentation created: 20 points
    - Fall risk content documented: 25 points
    - Score (90/High Risk) recorded: 15 points
    - Intervention noted: 10 points
    - VLM trajectory verification: 15 points
    
    Pass threshold: 70 points with fall content documented
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    expected_fname = metadata.get('patient_fname', 'Lavon')
    expected_lname = metadata.get('patient_lname', 'Kuvalis')
    expected_score = metadata.get('expected_score', 90)
    fall_keywords = metadata.get('fall_keywords', ['fall', 'risk', 'morse', 'gait', 'ambulatory', 'walker', 'impaired', 'precaution', 'high risk', '90', 'assessment'])
    intervention_keywords = metadata.get('intervention_keywords', ['precaution', 'intervention', 'education', 'protocol', 'prevention'])
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_accessed": False,
        "documentation_created": False,
        "fall_content_found": False,
        "score_recorded": False,
        "intervention_noted": False,
        "vlm_verified": False
    }
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fall_risk_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        new_entries = result.get('new_entries', {})
        content_analysis = result.get('content_analysis', {})
        newest_note = result.get('newest_note_body', '')
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        logger.info(f"Result data: pid={patient_pid}, new_entries={new_entries}")
        logger.info(f"Content analysis: {content_analysis}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["patient_accessed"] = True
            feedback_parts.append(f"✓ Correct patient accessed (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Documentation was for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: New documentation created (20 points)
        new_forms = new_entries.get('forms', 0)
        new_notes = new_entries.get('notes', 0)
        new_encounters = new_entries.get('encounters', 0)
        total_new = new_forms + new_notes + new_encounters
        
        if total_new > 0:
            score += 20
            subscores["documentation_created"] = True
            feedback_parts.append(f"✓ New documentation created (forms: {new_forms}, notes: {new_notes}, encounters: {new_encounters})")
        else:
            feedback_parts.append("✗ No new documentation detected in database")
            # Don't return early - check content analysis which may have found existing updated content
        
        # CRITERION 3: Fall risk content documented (25 points)
        fall_content_found = content_analysis.get('fall_content_found', False)
        keywords_found = content_analysis.get('keywords_found', '')
        
        # Also check the newest note body directly for keywords
        if newest_note:
            note_lower = newest_note.lower()
            for kw in fall_keywords:
                if kw.lower() in note_lower:
                    fall_content_found = True
                    if kw not in keywords_found:
                        keywords_found += f" {kw}"
        
        if fall_content_found:
            score += 25
            subscores["fall_content_found"] = True
            feedback_parts.append(f"✓ Fall risk content documented (keywords: {keywords_found.strip()})")
        else:
            feedback_parts.append("✗ No fall risk content found in documentation")
        
        # CRITERION 4: Score recorded (15 points)
        score_documented = content_analysis.get('score_documented', False)
        
        # Additional check for score in note body
        if newest_note:
            note_lower = newest_note.lower()
            if '90' in note_lower or 'high risk' in note_lower or 'high-risk' in note_lower:
                score_documented = True
        
        if score_documented:
            score += 15
            subscores["score_recorded"] = True
            feedback_parts.append(f"✓ Fall risk score (90/High Risk) recorded")
        else:
            feedback_parts.append("✗ Fall risk score not found in documentation")
        
        # CRITERION 5: Intervention noted (10 points)
        intervention_documented = content_analysis.get('intervention_documented', False)
        
        # Additional check for intervention in note body
        if newest_note:
            note_lower = newest_note.lower()
            for kw in intervention_keywords:
                if kw.lower() in note_lower:
                    intervention_documented = True
                    break
        
        if intervention_documented:
            score += 10
            subscores["intervention_noted"] = True
            feedback_parts.append("✓ Intervention/precautions documented")
        else:
            feedback_parts.append("✗ No intervention/precautions found")
        
        # CRITERION 6: VLM trajectory verification (15 points)
        vlm_score = 0
        if query_vlm and traj:
            try:
                vlm_score = verify_with_vlm(traj, query_vlm, expected_fname, expected_lname)
                if vlm_score > 0:
                    score += vlm_score
                    subscores["vlm_verified"] = True
                    feedback_parts.append(f"✓ VLM verification passed (+{vlm_score} pts)")
                else:
                    feedback_parts.append("✗ VLM verification did not confirm workflow")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append(f"⚠ VLM verification skipped: {e}")
        else:
            feedback_parts.append("⚠ VLM verification not available")
        
        # Anti-gaming check: Verify task duration is reasonable
        if task_start > 0 and task_end > 0:
            duration = task_end - task_start
            if duration < 10:  # Less than 10 seconds is suspicious
                feedback_parts.append(f"⚠ Suspicious task duration: {duration}s")
                score = max(0, score - 20)  # Penalty for gaming attempt
        
        # Determine pass/fail
        # Must have fall content documented and either new documentation or VLM confirmation
        key_criteria_met = fall_content_found and (total_new > 0 or subscores["vlm_verified"])
        passed = score >= 70 and key_criteria_met
        
        # Final message
        message = f"Score: {score}/100. "
        if passed:
            message += "Fall risk assessment successfully documented."
        elif fall_content_found:
            message += "Fall risk content found but incomplete documentation."
        elif total_new > 0:
            message += "Documentation created but fall risk content not found."
        else:
            message += "No fall risk assessment documentation found for patient."
        
        return {
            "passed": passed,
            "score": score,
            "feedback": message + " | " + " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": subscores
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": subscores
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": subscores
        }


def verify_with_vlm(traj, query_vlm, expected_fname, expected_lname):
    """
    Use VLM to verify the agent's workflow from trajectory screenshots.
    
    Returns points (0-15) based on VLM confidence in workflow completion.
    """
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback if import fails
        logger.warning("Could not import gym_anything.vlm")
        return 0
    
    # Sample frames across trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return 0
    
    all_images = frames + ([final] if final else [])
    
    VLM_PROMPT = f"""You are verifying if an agent successfully documented a fall risk assessment in OpenEMR (Electronic Health Records system).

The task was to:
1. Log into OpenEMR
2. Find patient {expected_fname} {expected_lname}
3. Document a fall risk assessment (Morse Fall Scale)
4. Save the documentation

Look at these screenshots from the agent's work session and determine:

1. Did the agent access OpenEMR/EHR system? (login screen or dashboard visible)
2. Did the agent search for or access a patient record? (patient name or chart visible)
3. Did the agent open a form, note, or documentation interface?
4. Is there any text entry showing fall-related content (fall, risk, gait, walker, etc.)?
5. Did the agent appear to save/submit documentation?

Respond in JSON format:
{{
    "accessed_ehr": true/false,
    "accessed_patient": true/false,
    "opened_documentation_form": true/false,
    "entered_fall_content": true/false,
    "saved_documentation": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}
"""
    
    try:
        vlm_result = query_vlm(
            prompt=VLM_PROMPT,
            images=all_images
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate points based on VLM findings
        points = 0
        
        if parsed.get("accessed_ehr"):
            points += 3
        if parsed.get("accessed_patient"):
            points += 3
        if parsed.get("opened_documentation_form"):
            points += 3
        if parsed.get("entered_fall_content"):
            points += 4
        if parsed.get("saved_documentation"):
            points += 2
        
        # Adjust based on confidence
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            points = points // 2
        elif confidence == "medium":
            points = int(points * 0.75)
        
        return min(points, 15)  # Cap at 15 points
        
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return 0


if __name__ == "__main__":
    # Test the verifier with mock data
    print("Fall Risk Assessment Verifier - Test Mode")
    
    # Mock test
    mock_result = {
        "patient_pid": 4,
        "task_start_timestamp": 1700000000,
        "task_end_timestamp": 1700000180,
        "new_entries": {"forms": 0, "notes": 1, "encounters": 1},
        "content_analysis": {
            "fall_content_found": True,
            "keywords_found": "fall risk gait walker",
            "score_documented": True,
            "intervention_documented": True
        },
        "newest_note_body": "Fall risk assessment: Morse Fall Scale score 90. High fall risk. Patient uses walker, impaired gait. Implement fall precautions protocol. Patient education provided."
    }
    
    print(f"Mock result would score well with fall content found and new documentation")