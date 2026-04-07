#!/usr/bin/env python3
"""
Verifier for the export_routine_pdf task.
Evaluates CRUD updates via DB and cross-application file downloading.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_routine_pdf(traj, env_info, task_info):
    """
    Verifies the routine was renamed and exported to a PDF document correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_new_name = metadata.get('expected_new_name', 'Push-Pull-Legs (Hypertrophy Phase)')

    # 1. Read exported execution data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start_time = result.get('task_start_time', 0)
    pdf_exists = result.get('pdf_exists', False)
    pdf_path = result.get('pdf_path', '')
    pdf_mtime = result.get('pdf_mtime', 0)
    old_routine_count = int(result.get('old_routine_count', 0))
    new_routine_count = int(result.get('new_routine_count', 0))

    score = 0
    feedback = []

    # Criterion 1: Database State Verification (20 points)
    db_renamed = False
    if old_routine_count == 0 and new_routine_count > 0:
        score += 20
        db_renamed = True
        feedback.append("✅ [20/20] Routine successfully renamed in the database.")
    elif new_routine_count > 0:
        score += 10
        db_renamed = True
        feedback.append("⚠️ [10/20] New routine name exists, but old one wasn't completely replaced.")
    else:
        feedback.append(f"❌ [0/20] Routine was not successfully renamed in the database.")

    # Criterion 2: PDF File Downloaded & Timed (20 points)
    pdf_valid = False
    pdf_text_correct = False
    
    if pdf_exists and pdf_path:
        if pdf_mtime >= task_start_time:
            score += 20
            pdf_valid = True
            feedback.append("✅ [20/20] PDF found in Downloads directory (created during task).")
        else:
            feedback.append("❌ [0/20] PDF found, but modification time predates the task (Anti-gaming triggered).")

        # Criterion 3: PDF Content Verification (30 points)
        if pdf_valid:
            temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
            try:
                copy_from_env(pdf_path, temp_pdf.name)
                
                # Use pdfminer to extract text 
                from pdfminer.high_level import extract_text
                pdf_text = extract_text(temp_pdf.name)
                
                if expected_new_name in pdf_text:
                    score += 30
                    pdf_text_correct = True
                    feedback.append(f"✅ [30/30] Exported PDF accurately contains text: '{expected_new_name}'.")
                else:
                    feedback.append(f"❌ [0/30] Exported PDF does NOT contain the required updated routine name.")
            except Exception as e:
                feedback.append(f"⚠️ [0/30] Could not parse text from PDF file: {str(e)}")
            finally:
                if os.path.exists(temp_pdf.name):
                    os.unlink(temp_pdf.name)
    else:
        feedback.append("❌ [0/50] No PDF found in the Downloads directory. PDF export failed.")

    # Criterion 4: VLM Trajectory Verification (30 points)
    vlm_score = 0
    if query_vlm:
        prompt = """You are verifying an agent's completion of a web application task.
TASK: Edit a workout routine's name and download it as a PDF.
Look at these trajectory frames. Determine:
1. Did the agent navigate to the routine editing view and edit the text?
2. Did the agent trigger a file download (e.g., clicking the PDF/download icon, handling a save dialog)?

Respond strictly in JSON format:
{
    "evidence_of_editing": true/false,
    "evidence_of_download": true/false
}"""
        
        frames = sample_trajectory_frames(traj, n=6)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_result = query_vlm(images=frames, prompt=prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("evidence_of_editing", False):
                vlm_score += 15
            if parsed.get("evidence_of_download", False):
                vlm_score += 15
                
            score += vlm_score
            feedback.append(f"✅ [{vlm_score}/30] VLM Trajectory Verification completed.")
        else:
            feedback.append("⚠️ [0/30] VLM Verification failed or returned an error.")
    else:
        feedback.append("⚠️ [0/30] VLM query function not available.")

    # Final Pass/Fail determination
    key_criteria_met = db_renamed and pdf_valid and pdf_text_correct
    passed = score >= 70 and key_criteria_met

    if passed:
        feedback.insert(0, "🎉 TASK PASSED")
    else:
        feedback.insert(0, "❌ TASK FAILED (Requires DB update, valid PDF download, and correct text content)")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }