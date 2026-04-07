#!/usr/bin/env python3
"""
Verifier for the generate_daily_schedule task.
Performs programmatic validation on file timestamps and PDF text content,
supplemented by VLM trajectory analysis.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_daily_schedule(traj, env_info, task_info):
    """
    Verifies that the daily schedule was successfully exported as a PDF.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/daily_schedule.pdf')
    expected_patients = metadata.get('expected_patients', ["Robert Chen", "Maria Santos", "David Washington"])

    score = 0
    feedback_parts = []
    
    # 1. Fetch metadata result from export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/daily_schedule_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence and Timestamps
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    if output_exists:
        score += 20
        feedback_parts.append("PDF output exists")
        
        if file_created_during_task:
            score += 20
            feedback_parts.append("File was created during task execution")
        else:
            feedback_parts.append("File exists but timestamp indicates it was pre-existing (Gaming attempt?)")
    else:
        feedback_parts.append("PDF output file NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Analyze PDF Content (Text extraction)
    pdf_text = ""
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(expected_output_path, temp_pdf.name)
        if os.path.getsize(temp_pdf.name) > 0:
            # pdfminer is included in the base Python execution environment
            from pdfminer.high_level import extract_text
            pdf_text = extract_text(temp_pdf.name).lower()
    except Exception as e:
        logger.warning(f"Failed to extract PDF text or file empty: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    if pdf_text:
        # Check for pre-seeded patients (10 pts per patient)
        patients_found = 0
        for patient in expected_patients:
            # Split names to robustly handle formats like "Chen, Robert"
            parts = patient.lower().split()
            if all(part in pdf_text for part in parts):
                patients_found += 1
                feedback_parts.append(f"Found patient: {patient}")
            else:
                feedback_parts.append(f"Missing patient: {patient}")
        
        score += (patients_found * 10)

        # Check for today's date presence
        iso_date = result.get('container_date_iso', 'unknown')
        us_date = result.get('container_date_us', 'unknown')
        if iso_date in pdf_text or us_date in pdf_text:
            score += 10
            feedback_parts.append("Confirmed today's date in PDF content")
        else:
            feedback_parts.append("Today's date not found in PDF content")
    else:
        feedback_parts.append("PDF text extraction failed or file is empty")

    # 4. VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = (
                    "Examine these screenshots from an agent interacting with an Electronic Medical Record system. "
                    "Did the agent navigate to the scheduling/reports screen and attempt to print or export a daily schedule? "
                    "Respond with a JSON object containing a single boolean key 'attempted'."
                )
                vlm_res = query_vlm(images=images, prompt=prompt)
                
                vlm_passed = False
                if isinstance(vlm_res, dict) and 'parsed' in vlm_res:
                    vlm_passed = vlm_res['parsed'].get('attempted', False)
                elif isinstance(vlm_res, dict) and 'attempted' in str(vlm_res.get('response', '')).lower():
                    # Fallback string matching just in case JSON parsing failed
                    vlm_passed = "true" in str(vlm_res.get('response', '')).lower()
                
                if vlm_passed:
                    score += 20
                    feedback_parts.append("VLM visually confirmed print/export workflow")
                else:
                    feedback_parts.append("VLM did not detect correct workflow in trajectory")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped (error)")
    else:
        # Give full credit for VLM step if VLM isn't available but file passed textual checks
        if score >= 60:
            score += 20
            feedback_parts.append("VLM unavailable - awarded points due to accurate textual extraction")

    # Final Evaluation (Needs at least 70/100 to pass)
    # Must have the file created during task AND at least one patient name found
    key_criteria_met = file_created_during_task and (score >= 50)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }