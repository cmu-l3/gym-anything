#!/usr/bin/env python3
"""
Verifier for Record Historical Immunization task in OpenEMR

Verifies that a historical DTaP immunization was correctly recorded for patient
Jayson Fadel (pid=3) with the specified details.

Key verification points:
1. Immunization record exists for correct patient
2. Record was newly created (not pre-existing)
3. Administered date is historical (2019-03-15), not today
4. Vaccine type is DTaP
5. Manufacturer and lot number are documented
6. Administration site is documented
7. Notes are present

Uses copy_from_env to read exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, date

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_historical_immunization(traj, env_info, task_info):
    """
    Verify that a historical immunization was correctly recorded.

    Scoring (100 points total):
    - Immunization record exists: 25 points
    - Correct patient (pid=3): 15 points
    - Correct vaccine type (DTaP): 15 points
    - Correct historical date (2019-03-15): 15 points
    - Manufacturer documented: 10 points
    - Lot number documented: 10 points
    - Administration site noted: 5 points
    - Notes added: 5 points

    Passing threshold: 70 points with immunization_exists and correct_patient
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_date = metadata.get('administered_date', '2019-03-15')
    expected_vaccine = metadata.get('vaccine_name', 'DTaP')
    expected_cvx = metadata.get('vaccine_cvx', '20')
    expected_manufacturer = metadata.get('manufacturer', 'Sanofi Pasteur')
    expected_lot = metadata.get('lot_number', 'D2894AA')
    expected_site = metadata.get('administration_site', 'Left Deltoid')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/historical_immunization_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "immunization_exists": False,
            "correct_patient": False,
            "correct_vaccine": False,
            "correct_date": False,
            "manufacturer_documented": False,
            "lot_documented": False,
            "site_documented": False,
            "notes_present": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_imm_count', 0)
        current_count = result.get('current_imm_count', 0)
        imm_found = result.get('immunization_found', False)
        immunization = result.get('immunization', {})
        validation = result.get('validation', {})
        today_date = result.get('today_date', '')

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={imm_found}")
        logger.info(f"Immunization: {immunization}")
        logger.info(f"Validation: {validation}")

        # CRITERION 1: Immunization record exists (25 points)
        if imm_found and current_count > initial_count:
            score += 25
            subscores["immunization_exists"] = True
            feedback_parts.append(f"✅ New immunization record created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"❌ No new immunization record found (count: {initial_count} -> {current_count})")
            # Early return - without a record, nothing else to verify
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Correct patient (15 points)
        imm_patient_id = immunization.get('patient_id', '')
        try:
            imm_patient_id_int = int(imm_patient_id) if imm_patient_id else 0
        except ValueError:
            imm_patient_id_int = 0

        if imm_patient_id_int == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {imm_patient_id}")
            # This is critical - wrong patient means the task was not completed correctly
            # But we continue to give feedback on other criteria

        # CRITERION 3: Correct vaccine type - DTaP (15 points)
        cvx_code = immunization.get('cvx_code', '')
        vaccine_name = immunization.get('vaccine_name', '')
        vaccine_is_dtap = validation.get('vaccine_is_dtap', False)

        # Check CVX code (20 = DTaP) or vaccine name contains DTaP/related terms
        if vaccine_is_dtap or cvx_code == expected_cvx:
            score += 15
            subscores["correct_vaccine"] = True
            feedback_parts.append(f"✅ Correct vaccine type (DTaP, CVX={cvx_code})")
        elif any(term in vaccine_name.lower() for term in ['dtap', 'diphtheria', 'tetanus', 'pertussis']):
            score += 15
            subscores["correct_vaccine"] = True
            feedback_parts.append(f"✅ Correct vaccine type ({vaccine_name})")
        else:
            feedback_parts.append(f"❌ Vaccine type not DTaP: CVX={cvx_code}, name={vaccine_name}")

        # CRITERION 4: Correct historical date (15 points)
        # This is crucial - must be 2019-03-15, NOT today's date
        administered_date = immunization.get('administered_date', '')
        date_is_historical = validation.get('date_is_historical', False)

        if administered_date == expected_date:
            score += 15
            subscores["correct_date"] = True
            feedback_parts.append(f"✅ Correct historical date ({expected_date})")
        elif administered_date == today_date:
            # Agent entered today's date instead of historical date - partial credit
            score += 5
            feedback_parts.append(f"⚠️ Date is today ({today_date}) instead of historical ({expected_date})")
        else:
            feedback_parts.append(f"❌ Wrong date: expected {expected_date}, got {administered_date}")

        # CRITERION 5: Manufacturer documented (10 points)
        manufacturer = immunization.get('manufacturer', '')
        manufacturer_correct = validation.get('manufacturer_correct', False)

        if manufacturer_correct or 'sanofi' in manufacturer.lower():
            score += 10
            subscores["manufacturer_documented"] = True
            feedback_parts.append(f"✅ Manufacturer documented ({manufacturer})")
        elif manufacturer and manufacturer.strip():
            # Some manufacturer entered, partial credit
            score += 5
            subscores["manufacturer_documented"] = True
            feedback_parts.append(f"⚠️ Manufacturer entered but not Sanofi Pasteur: {manufacturer}")
        else:
            feedback_parts.append("❌ Manufacturer not documented")

        # CRITERION 6: Lot number documented (10 points)
        lot_number = immunization.get('lot_number', '')
        lot_correct = validation.get('lot_correct', False)

        if lot_correct or lot_number == expected_lot:
            score += 10
            subscores["lot_documented"] = True
            feedback_parts.append(f"✅ Lot number correct ({expected_lot})")
        elif lot_number and lot_number.strip():
            # Some lot number entered, partial credit
            score += 5
            subscores["lot_documented"] = True
            feedback_parts.append(f"⚠️ Lot number entered but not {expected_lot}: {lot_number}")
        else:
            feedback_parts.append("❌ Lot number not documented")

        # CRITERION 7: Administration site documented (5 points)
        site = immunization.get('administration_site', '')
        site_correct = validation.get('site_correct', False)

        if site_correct or any(term in site.lower() for term in ['left', 'deltoid', 'arm']):
            score += 5
            subscores["site_documented"] = True
            feedback_parts.append(f"✅ Administration site documented ({site})")
        elif site and site.strip():
            # Some site entered, partial credit
            score += 3
            subscores["site_documented"] = True
            feedback_parts.append(f"⚠️ Administration site entered: {site}")
        else:
            feedback_parts.append("❌ Administration site not documented")

        # CRITERION 8: Notes present (5 points)
        note = immunization.get('note', '')
        notes_present = validation.get('notes_present', False)

        if notes_present or (note and note.strip() and note != 'NULL'):
            score += 5
            subscores["notes_present"] = True
            feedback_parts.append("✅ Notes added to immunization record")
        else:
            feedback_parts.append("❌ No notes added")

        # Determine pass/fail
        # Must have: immunization exists AND correct patient AND score >= 70
        key_criteria_met = (
            subscores["immunization_exists"] and 
            subscores["correct_patient"]
        )
        passed = score >= 70 and key_criteria_met

        # Final feedback
        final_feedback = " | ".join(feedback_parts)
        if passed:
            final_feedback = f"✅ PASSED (Score: {score}/100) | " + final_feedback
        else:
            if not key_criteria_met:
                final_feedback = f"❌ FAILED - Key criteria not met (Score: {score}/100) | " + final_feedback
            else:
                final_feedback = f"❌ FAILED - Score below threshold (Score: {score}/100) | " + final_feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback,
            "subscores": subscores,
            "details": {
                "expected_patient_pid": expected_pid,
                "expected_date": expected_date,
                "expected_vaccine": expected_vaccine,
                "expected_lot": expected_lot,
                "actual_immunization": immunization,
                "validation_flags": validation
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - task may not have been completed",
            "subscores": {
                "immunization_exists": False,
                "correct_patient": False,
                "correct_vaccine": False,
                "correct_date": False,
                "manufacturer_documented": False,
                "lot_documented": False,
                "site_documented": False,
                "notes_present": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result data: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {}
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Optional VLM-based verification as fallback.
    Uses trajectory frames to verify the agent actually performed the task.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return None

    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return None
        
        all_images = frames + ([final] if final else [])
        
        vlm_prompt = """You are verifying if a computer agent successfully recorded a historical immunization in OpenEMR.

TASK: Record a historical DTaP immunization for patient Jayson Fadel with date 2019-03-15.

Look at these screenshots from the agent's work session and determine:
1. Did the agent navigate to a patient named Jayson Fadel?
2. Did the agent access the immunizations section?
3. Did the agent fill out an immunization form?
4. Was DTaP or a similar vaccine selected?
5. Was a historical date (2019-03-15) entered?
6. Was the form saved/submitted?

Respond in JSON format:
{
    "patient_accessed": true/false,
    "immunization_section_accessed": true/false,
    "form_filled": true/false,
    "vaccine_selected": true/false,
    "date_entered": true/false,
    "form_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            return {
                "vlm_verification": parsed,
                "confidence": parsed.get("confidence", "low")
            }
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return None