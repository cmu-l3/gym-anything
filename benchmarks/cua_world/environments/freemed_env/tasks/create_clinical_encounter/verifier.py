#!/usr/bin/env python3
"""
Verifier for create_clinical_encounter task.

HYBRID VERIFICATION: 
1. Database State: Checks `pnotes`, `procrec`, and `encounter` tables for Elena Vasquez.
2. Content Validation: Ensures date (2025-01-15) and clinical concepts were recorded.
3. VLM Trajectory Check: Confirms the agent used the UI workflow rather than raw API injects.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_clinical_encounter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load export results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Database State Check
    db_data = result.get('db_data', {})
    if not db_data.get('patient_found', False):
        return {"passed": False, "score": 0, "feedback": "Patient Elena Vasquez not found in the DB. Setup failed or patient deleted."}

    all_records = db_data.get('pnotes', []) + db_data.get('procrec', []) + db_data.get('encounters', [])
    record_created = len(all_records) > 0

    score = 0
    feedback = []

    if record_created:
        score += 40
        feedback.append("Encounter/note record found in database.")

        # 2. Content Validation Check
        has_date = False
        has_clinical_content = False

        for record in all_records:
            record_str = json.dumps(record).lower()
            
            # Check for requested date
            if "2025-01-15" in record_str:
                has_date = True
                
            # Check for clinical terms associated with task description
            clinical_terms = ["hypertension", "blood pressure", "401.1", "i10", "99214"]
            if any(term in record_str for term in clinical_terms):
                has_clinical_content = True

        if has_date:
            score += 15
            feedback.append("Date of service (2025-01-15) successfully recorded.")
        else:
            feedback.append("Target date of service (2025-01-15) missing from clinical records.")

        if has_clinical_content:
            score += 15
            feedback.append("Clinical data (diagnosis/procedure/notes) successfully recorded.")
        else:
            feedback.append("Expected clinical text/codes missing from clinical records.")
            
    else:
        feedback.append("No clinical encounter or progress note was found in database for Elena Vasquez.")

    # 3. VLM Trajectory Verification
    vlm_passed = False
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            # Extract trajectory frames defensively
            images = []
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                images = frames + ([final] if final else [])
            except ImportError:
                import numpy as np
                if traj and hasattr(traj, 'steps') and len(traj.steps) > 0:
                    steps = traj.steps
                    indices = np.linspace(0, len(steps)-1, min(5, len(steps)), dtype=int)
                    for idx in indices:
                        obs = steps[idx].observation
                        if obs and 'rgb_screen' in obs:
                            images.append(obs['rgb_screen'])

            if images:
                prompt = (
                    "Review these sequential screenshots of an agent operating the FreeMED EMR system.\n"
                    "Did the agent successfully complete this clinical workflow?\n"
                    "1. Search for and open the chart of patient 'Elena Vasquez'.\n"
                    "2. Navigate to an encounter, procedure record, or progress note creation screen.\n"
                    "3. Enter the target date '2025-01-15' and clinical details about hypertension.\n"
                    "4. Save the record without persistent error dialogues.\n\n"
                    "Respond with ONLY a JSON object: {'workflow_completed': true/false, 'reason': '...'}"
                )
                
                vlm_resp = query_vlm(images=images, prompt=prompt)
                if vlm_resp and 'parsed' in vlm_resp:
                    vlm_passed = vlm_resp['parsed'].get('workflow_completed', False)

                if vlm_passed:
                    score += 30
                    feedback.append("VLM visual verification confirmed correct workflow completion.")
                else:
                    feedback.append("VLM visual verification failed to confirm the clinical workflow.")
            else:
                feedback.append("No visual frames available for VLM verification.")
        else:
            feedback.append("VLM capability not available in env_info; skipping visual check.")
    except Exception as e:
        logger.error(f"VLM verification exception: {e}")
        feedback.append(f"VLM verification failed to run: {str(e)}")

    # Check for overall success (requires database records and key attributes)
    passed = (score >= 70) and record_created

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }