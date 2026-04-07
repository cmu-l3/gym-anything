#!/usr/bin/env python3
"""
Verifier for Document Medication Administration task in OpenEMR

Verifies that a B12 injection was properly documented in the patient's record.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring Criteria (100 points):
- Patient correct (pid=3): 20 points
- New record created: 25 points
- Medication is B12/Cyanocobalamin: 20 points
- Route is Intramuscular (IM): 15 points
- Site is documented: 10 points
- Record was saved successfully: 10 points

Pass threshold: 60 points with record created
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_medication_administration(traj, env_info, task_info):
    """
    Verify that a vitamin B12 injection was documented for patient Jayson Fadel.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    medication_aliases = metadata.get('medication_aliases', ['B12', 'Vitamin B12', 'cyanocobalamin', 'Cyanocobalamin', 'B-12', 'cobalamin'])
    route_aliases = metadata.get('route_aliases', ['IM', 'intramuscular', 'Intramuscular', 'intra-muscular'])
    site_aliases = metadata.get('site_aliases', ['deltoid', 'left deltoid', 'right deltoid', 'arm', 'shoulder'])
    
    # Scoring weights
    weights = metadata.get('scoring_weights', {
        'patient_correct': 20,
        'record_created': 25,
        'medication_documented': 20,
        'route_documented': 15,
        'site_documented': 10,
        'record_saved': 10
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/medication_administration_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "patient_correct": False,
            "record_created": False,
            "medication_documented": False,
            "route_documented": False,
            "site_documented": False,
            "record_saved": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_immunization_count', 0)
        current_count = result.get('current_immunization_count', 0)
        new_imm_found = result.get('new_immunization_found', False)
        imm_record = result.get('immunization_record', {})
        validation = result.get('validation', {})

        logger.info(f"Result: patient_pid={patient_pid}, initial={initial_count}, current={current_count}, found={new_imm_found}")
        logger.info(f"Immunization record: {imm_record}")
        logger.info(f"Validation: {validation}")

        # CRITERION 1: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += weights['patient_correct']
            subscores['patient_correct'] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Documentation was for wrong patient",
                "subscores": subscores
            }

        # CRITERION 2: New record created (25 points)
        if new_imm_found and current_count > initial_count:
            score += weights['record_created']
            subscores['record_created'] = True
            feedback_parts.append(f"✅ New immunization record created (count: {initial_count} → {current_count})")
        else:
            feedback_parts.append(f"❌ No new immunization record detected (count: {initial_count} → {current_count})")
            # Without a record, we can't score much else
            # But check if maybe forms were added instead
            initial_forms = result.get('initial_forms_count', 0)
            current_forms = result.get('current_forms_count', 0)
            if current_forms > initial_forms:
                feedback_parts.append(f"Note: {current_forms - initial_forms} new form(s) detected - may have used different workflow")
                score += 10  # Partial credit for some documentation
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Medication is B12/Cyanocobalamin (20 points)
        imm_name = imm_record.get('immunization_name', '').lower()
        imm_note = imm_record.get('note', '').lower()
        combined_text = f"{imm_name} {imm_note}"
        
        medication_match = False
        for alias in medication_aliases:
            if alias.lower() in combined_text:
                medication_match = True
                break
        
        # Also check validation from export script
        if validation.get('medication_matches_b12', False):
            medication_match = True
        
        if medication_match:
            score += weights['medication_documented']
            subscores['medication_documented'] = True
            feedback_parts.append(f"✅ B12/Cyanocobalamin documented")
        else:
            feedback_parts.append(f"❌ Medication not identified as B12/Cyanocobalamin (found: {imm_record.get('immunization_name', 'none')})")

        # CRITERION 4: Route is Intramuscular (15 points)
        route = imm_record.get('route', '').lower()
        route_match = False
        for alias in route_aliases:
            if alias.lower() in route or route in alias.lower():
                route_match = True
                break
        
        # Also check validation from export
        if validation.get('route_matches_im', False):
            route_match = True
        
        if route_match:
            score += weights['route_documented']
            subscores['route_documented'] = True
            feedback_parts.append(f"✅ Route documented as Intramuscular")
        elif route:
            # Some route documented but not IM
            score += weights['route_documented'] // 2  # Partial credit
            feedback_parts.append(f"⚠️ Route documented as '{route}' (expected Intramuscular)")
        else:
            feedback_parts.append(f"❌ Route not documented")

        # CRITERION 5: Site is documented (10 points)
        site = imm_record.get('site', '').lower()
        site_validation = validation.get('site_documented', 'false')
        
        site_match = False
        for alias in site_aliases:
            if alias.lower() in site or site in alias.lower():
                site_match = True
                break
        
        if site_match or site_validation == 'true':
            score += weights['site_documented']
            subscores['site_documented'] = True
            feedback_parts.append(f"✅ Injection site documented (deltoid)")
        elif site or site_validation == 'partial':
            # Some site documented
            score += weights['site_documented'] // 2
            feedback_parts.append(f"⚠️ Site documented as '{site}' (expected deltoid)")
        else:
            feedback_parts.append(f"❌ Injection site not documented")

        # CRITERION 6: Record was saved (10 points)
        # If we got here and have a record ID, it was saved
        if imm_record.get('id'):
            score += weights['record_saved']
            subscores['record_saved'] = True
            feedback_parts.append(f"✅ Record saved successfully (ID: {imm_record.get('id')})")
        else:
            feedback_parts.append(f"❌ Record may not have been saved properly")

        # VLM verification as secondary check (if available)
        vlm_feedback = verify_via_vlm(traj, env_info)
        if vlm_feedback:
            feedback_parts.append(vlm_feedback)

        # Determine pass/fail
        # Must have: correct patient + record created + medication documented
        key_criteria = subscores['patient_correct'] and subscores['record_created']
        passed = score >= 60 and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "immunization_record": imm_record,
                "validation": validation
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Could not read result file - task may not have been attempted",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error parsing result data: {str(e)}",
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


def verify_via_vlm(traj, env_info):
    """
    Secondary verification using VLM on trajectory screenshots.
    
    Checks if the agent navigated through the correct workflow:
    1. Logged into OpenEMR
    2. Searched for/selected patient
    3. Navigated to immunizations section
    4. Filled out and saved injection form
    
    Returns:
        str: VLM feedback message or None if VLM unavailable
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return None
    
    try:
        # Import trajectory sampling utility
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory (not just final)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return None
        
        all_frames = frames + ([final] if final else [])
        
        vlm_prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Records) session.

The task was to document a vitamin B12 injection for a patient named Jayson Fadel.

Look for evidence that the agent:
1. Logged into OpenEMR (login page → dashboard)
2. Searched for and selected a patient
3. Navigated to immunizations or injection documentation
4. Filled out a form with medication details
5. Saved the record

Respond in JSON format:
{
    "login_completed": true/false,
    "patient_selected": true/false,
    "immunization_form_accessed": true/false,
    "form_filled": true/false,
    "workflow_correct": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""

        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get('success'):
            return None
        
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('workflow_correct') and parsed.get('confidence') in ['medium', 'high']:
            return "🔍 VLM: Workflow appears correct"
        elif not parsed.get('workflow_correct'):
            observations = parsed.get('observations', '')
            return f"🔍 VLM: Workflow may be incomplete ({observations[:100]})"
        
        return None
        
    except ImportError:
        logger.debug("VLM utilities not available")
        return None
    except Exception as e:
        logger.debug(f"VLM verification failed: {e}")
        return None


if __name__ == "__main__":
    # Test the verifier with mock data
    print("Medication Administration Verifier - Test Mode")
    print("=" * 50)
    
    # Create mock data
    mock_result = {
        "patient_pid": 3,
        "initial_immunization_count": 0,
        "current_immunization_count": 1,
        "new_immunization_found": True,
        "immunization_record": {
            "id": "1",
            "immunization_name": "Cyanocobalamin (B12)",
            "date_administered": "2024-01-15",
            "site": "Left deltoid",
            "route": "Intramuscular",
            "note": "Vitamin B12 injection for deficiency"
        },
        "validation": {
            "medication_matches_b12": True,
            "route_matches_im": True,
            "site_documented": "true"
        }
    }
    
    # Write mock result
    with open('/tmp/medication_administration_result.json', 'w') as f:
        json.dump(mock_result, f)
    
    print("Mock result file created")
    print("In production, this verifier uses copy_from_env to retrieve results from the container")