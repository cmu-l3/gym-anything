#!/usr/bin/env python3
"""
Verifier for Document Tobacco Cessation Counseling task in OpenEMR

Verifies that the agent properly documented a tobacco cessation counseling
intervention for patient Edgar Parker Sr. (pid=2).

Verification Strategy:
1. Database verification via exported JSON (primary)
2. VLM trajectory verification (secondary)
3. Anti-gaming checks (timestamp verification)
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Keywords to search for in documentation
TOBACCO_KEYWORDS = ['tobacco', 'smoking', 'cessation', 'nicotine', 'cigarette', 'quit']
COUNSELING_KEYWORDS = ['counseling', 'counsel', 'intervention', 'education', 'advice', 'discussed']
TIME_PATTERNS = [r'\d+\s*min', r'\d+\s*minute', r'minutes']
FOLLOWUP_KEYWORDS = ['follow-up', 'follow up', 'followup', 'callback', 'call back', 
                     'patch', 'prescription', 'rx', '2 week', 'two week', 'return']


def check_keywords(text, keywords):
    """Check if any keywords are present in text (case-insensitive)."""
    if not text:
        return False
    text_lower = text.lower()
    return any(kw.lower() in text_lower for kw in keywords)


def check_patterns(text, patterns):
    """Check if any regex patterns match in text."""
    if not text:
        return False
    for pattern in patterns:
        if re.search(pattern, text, re.IGNORECASE):
            return True
    return False


def verify_tobacco_counseling(traj, env_info, task_info):
    """
    Verify that tobacco cessation counseling was properly documented.

    Scoring (100 points total):
    - Correct patient accessed (pid=2): 15 points
    - Encounter exists for today: 15 points
    - Tobacco reference found: 20 points
    - Counseling documented: 20 points
    - Time documented: 10 points
    - Follow-up plan documented: 10 points
    - VLM trajectory verification: 10 points

    Passing threshold: 70 points with tobacco reference required
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_fname = metadata.get('patient_fname', 'Edgar')
    expected_lname = metadata.get('patient_lname', 'Parker Sr.')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/tobacco_counseling_result.json", temp_result.name)
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
            "tobacco_reference": False,
            "counseling_documented": False,
            "time_documented": False,
            "followup_documented": False,
            "vlm_verification": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start', 0)
        task_end = result.get('task_end', 0)
        task_date = result.get('task_date', '')
        
        initial_encounter_count = result.get('initial_encounter_count', 0)
        current_encounter_count = result.get('current_encounter_count', 0)
        initial_forms_count = result.get('initial_forms_count', 0)
        current_forms_count = result.get('current_forms_count', 0)
        
        encounter_found = result.get('encounter_found', False)
        encounter = result.get('encounter', {})
        
        tobacco_found = result.get('tobacco_reference_found', False)
        tobacco_content = result.get('tobacco_content', '')
        newest_note = result.get('newest_note_content', '')
        
        time_documented = result.get('time_documented', False)
        followup_documented = result.get('followup_documented', False)
        
        new_forms = result.get('new_forms_count', 0)
        new_encounters = result.get('new_encounters_count', 0)

        logger.info(f"Result data: pid={patient_pid}, encounter_found={encounter_found}")
        logger.info(f"Tobacco found: {tobacco_found}, Time: {time_documented}, Followup: {followup_documented}")
        logger.info(f"New encounters: {new_encounters}, New forms: {new_forms}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Documentation was for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Encounter exists (15 points)
        # Check if new encounter was created or existing encounter was used
        if encounter_found or new_encounters > 0:
            score += 15
            subscores["encounter_exists"] = True
            enc_date = encounter.get('date', 'unknown')
            enc_reason = encounter.get('reason', '')[:50]
            feedback_parts.append(f"✅ Encounter found (date: {enc_date})")
        elif current_forms_count > initial_forms_count:
            # Forms added without new encounter might use existing encounter
            score += 10  # Partial credit
            subscores["encounter_exists"] = True
            feedback_parts.append("✅ Forms added (using existing encounter)")
        else:
            feedback_parts.append("❌ No encounter found for today")

        # CRITERION 3: Tobacco reference found (20 points)
        # Check multiple sources for tobacco-related content
        all_content = f"{tobacco_content} {newest_note} {encounter.get('reason', '')}"
        
        if tobacco_found or check_keywords(all_content, TOBACCO_KEYWORDS):
            score += 20
            subscores["tobacco_reference"] = True
            feedback_parts.append("✅ Tobacco/smoking reference found in documentation")
        else:
            feedback_parts.append("❌ No tobacco/smoking reference found")

        # CRITERION 4: Counseling documented (20 points)
        if check_keywords(all_content, COUNSELING_KEYWORDS):
            score += 20
            subscores["counseling_documented"] = True
            feedback_parts.append("✅ Counseling intervention documented")
        elif tobacco_found:
            # Partial credit if tobacco is mentioned but counseling keywords missing
            score += 10
            feedback_parts.append("⚠️ Tobacco mentioned but counseling not explicitly documented")
        else:
            feedback_parts.append("❌ Counseling not documented")

        # CRITERION 5: Time documented (10 points)
        if time_documented or check_patterns(all_content, TIME_PATTERNS):
            score += 10
            subscores["time_documented"] = True
            feedback_parts.append("✅ Counseling time documented")
        else:
            feedback_parts.append("⚠️ Counseling time not explicitly documented")

        # CRITERION 6: Follow-up plan documented (10 points)
        if followup_documented or check_keywords(all_content, FOLLOWUP_KEYWORDS):
            score += 10
            subscores["followup_documented"] = True
            feedback_parts.append("✅ Follow-up plan documented")
        else:
            feedback_parts.append("⚠️ Follow-up plan not explicitly documented")

        # CRITERION 7: VLM trajectory verification (10 points)
        vlm_score = 0
        if query_vlm and traj:
            try:
                vlm_score = perform_vlm_verification(traj, query_vlm)
                if vlm_score >= 7:
                    score += 10
                    subscores["vlm_verification"] = True
                    feedback_parts.append("✅ VLM verified agent workflow")
                elif vlm_score >= 4:
                    score += 5
                    feedback_parts.append("⚠️ VLM partially verified workflow")
                else:
                    feedback_parts.append("⚠️ VLM could not verify workflow")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append("⚠️ VLM verification unavailable")
        else:
            feedback_parts.append("⚠️ VLM verification skipped")

        # Anti-gaming check: verify something was actually done
        if new_forms == 0 and new_encounters == 0 and not tobacco_found:
            feedback_parts.append("⚠️ Warning: No new forms or encounters detected")
            # Reduce score if nothing was done
            score = min(score, 20)

        # Determine pass/fail
        # Must have tobacco reference AND either encounter or forms added
        key_criteria_met = (
            subscores["correct_patient"] and 
            subscores["tobacco_reference"] and
            (subscores["encounter_exists"] or new_forms > 0)
        )
        
        passed = score >= 70 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "new_encounters": new_encounters,
                "new_forms": new_forms,
                "tobacco_found": tobacco_found,
                "vlm_score": vlm_score
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


def perform_vlm_verification(traj, query_vlm):
    """
    Use VLM to verify agent workflow through trajectory frames.
    
    Returns a score from 0-10 based on VLM analysis.
    """
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("gym_anything.vlm not available")
        return 0

    # Sample frames across the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    if not frames and not final_frame:
        return 0
    
    all_frames = frames + ([final_frame] if final_frame else [])
    
    if not all_frames:
        return 0

    verification_prompt = """You are verifying if a computer agent completed a clinical documentation task in OpenEMR.

TASK: Document tobacco cessation counseling for patient Edgar Parker Sr.

Analyze these screenshots from the agent's session and determine:
1. Did the agent log into OpenEMR?
2. Did the agent access a patient chart (look for patient name, demographics)?
3. Did the agent open an encounter or clinical documentation form?
4. Did the agent enter text related to tobacco/smoking/cessation counseling?
5. Did the agent save or submit the documentation?

Look for evidence of:
- OpenEMR interface (login page, dashboard, patient chart)
- Patient name "Edgar Parker" visible
- Documentation forms or note entry screens
- Text being typed about tobacco, smoking, counseling
- Save/submit buttons being clicked

Respond in JSON format:
{
    "logged_in": true/false,
    "patient_chart_accessed": true/false,
    "documentation_form_opened": true/false,
    "tobacco_content_entered": true/false,
    "documentation_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

    try:
        vlm_result = query_vlm(
            prompt=verification_prompt,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate score based on VLM findings
        vlm_score = 0
        if parsed.get("logged_in"):
            vlm_score += 2
        if parsed.get("patient_chart_accessed"):
            vlm_score += 2
        if parsed.get("documentation_form_opened"):
            vlm_score += 2
        if parsed.get("tobacco_content_entered"):
            vlm_score += 2
        if parsed.get("documentation_saved"):
            vlm_score += 2
        
        # Adjust based on confidence
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            vlm_score = vlm_score * 0.5
        elif confidence == "medium":
            vlm_score = vlm_score * 0.75
        
        return int(vlm_score)
        
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return 0


if __name__ == "__main__":
    # Test with mock data
    print("Tobacco Counseling Verifier - Test Mode")
    result = verify_tobacco_counseling(
        traj={},
        env_info={'copy_from_env': None},
        task_info={'metadata': {'patient_pid': 2}}
    )
    print(f"Result: {result}")