#!/usr/bin/env python3
import json
import os
import csv
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_export_patient_audit_log(traj, env_info, task_info):
    """
    Verifies the export_patient_audit_log task.
    
    Criteria:
    1. CSV file exists at expected path.
    2. CSV file contains valid audit data (Patient Name, User Admin).
    3. CSV file created during task window.
    4. VLM verification of UI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Criterion 1: File Existence (20 pts)
    if result_data.get("file_exists"):
        score += 20
        feedback.append("Audit log CSV file created.")
    else:
        feedback.append("Audit log CSV file NOT found at expected path.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Anti-Gaming / Timestamp (10 pts)
    if result_data.get("file_created_during_task"):
        score += 10
        feedback.append("File created during task window.")
    else:
        feedback.append("File timestamp indicates it was not created during the task.")

    # Criterion 3: Content Analysis (40 pts)
    # We need to pull the CSV content
    content_valid = False
    try:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env("/tmp/audit_log_export.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r', errors='replace') as f:
            content = f.read()
            
        # Basic string checks (robust against CSV formatting differences)
        has_patient = "Brandie" in content and "Sammet" in content
        has_admin = "admin" in content
        # Check for date (using the ISO date recorded in setup)
        task_date = result_data.get("task_date", "")
        has_date = task_date in content
        
        # Check specific points
        if has_patient:
            score += 15
            feedback.append("Log contains target patient name.")
        else:
            feedback.append("Log missing patient name 'Brandie Sammet'.")
            
        if has_admin:
            score += 10
            feedback.append("Log contains admin user activity.")
        else:
            feedback.append("Log missing 'admin' user activity.")
            
        if has_date:
            score += 15
            feedback.append(f"Log contains today's date ({task_date}).")
        else:
            feedback.append(f"Log missing today's date ({task_date}).")
            
        if has_patient and has_admin:
            content_valid = True
            
    except Exception as e:
        feedback.append(f"Failed to analyze CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Criterion 4: VLM Verification (30 pts)
    # We want to ensure they didn't just type a CSV by hand using a text editor.
    # We look for the "Reports" or "Logs" interface in the trajectory.
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images = frames + [final_img] if final_img else frames
    
    vlm_prompt = (
        "Analyze these screenshots of a user performing a task in LibreHealth EHR (an OpenEMR fork). "
        "The goal is to export an audit log.\n"
        "Look for:\n"
        "1. A screen showing 'Administration' menu or 'Reports' menu opened.\n"
        "2. A screen showing a Log Viewer or Audit Log search form.\n"
        "3. Evidence of searching for patient 'Brandie Sammet'.\n"
        "4. A download or export action.\n\n"
        "Did the agent navigate to the log/report section and generate the report using the UI?"
    )
    
    vlm_result = query_vlm(images=images, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        # We rely on the model's boolean judgment or sentiment, 
        # but here we'll assume a positive response indicates success.
        # A more robust implementation would parse JSON output from VLM.
        analysis = vlm_result.get("answer", "").lower()
        if "yes" in analysis or "navigated" in analysis or "generated" in analysis:
            vlm_score = 30
            feedback.append("VLM confirms UI navigation to Logs module.")
        else:
            vlm_score = 10  # Partial credit if ambiguous
            feedback.append("VLM could not clearly confirm UI navigation.")
    else:
        feedback.append("VLM verification failed to run.")
    
    score += vlm_score

    # Final Pass Determination
    # Must have file, correct content, and decent score
    passed = (result_data.get("file_exists") and 
              content_valid and 
              score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }