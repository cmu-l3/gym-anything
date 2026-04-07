#!/usr/bin/env python3
"""
Verifier for export_process_jsonld task.

Checks:
1. Did the agent import the database? (DB check)
2. Did the agent create the requested export file? (File check)
3. Is the file a valid JSON-LD zip? (Zip/JSON check)
4. Does the content match the "natural gas electricity" requirement? (Keyword check)
5. Did the agent follow the workflow? (VLM check)
"""

import json
import os
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using openLCA.
The goal is to import a database, find a 'natural gas electricity' process, and export it as JSON-LD.

Look for these steps in the image sequence:
1. **Import**: Dialogs showing "Import", selecting "JSON-LD", or file selection of a zip file.
2. **Navigation**: Browsing the "Processes" folder in the left navigation tree.
3. **Selection**: Selecting/highlighting a process named "Electricity" or "Natural gas".
4. **Export**: Right-clicking a process and choosing "Export", or using File > Export.
5. **Save**: A file save dialog naming the file "natural_gas_electricity.zip".

JSON Response:
{
    "import_attempted": true/false,
    "process_search_visible": true/false,
    "export_dialog_visible": true/false,
    "save_dialog_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "..."
}
"""

FINAL_STATE_PROMPT = """Analyze this final screenshot of openLCA.
Does it show successful completion of an export task?
- Is the application open and healthy (not crashed)?
- Is a database visible in the navigation panel (indicating import success)?
- Are there any visible confirmation messages (e.g. "Export finished")?
- Is the "Processes" list expanded?

JSON Response:
{
    "app_healthy": true/false,
    "database_visible": true/false,
    "export_confirmation": true/false,
    "processes_expanded": true/false,
    "reasoning": "..."
}
"""

def verify_export_process_jsonld(traj, env_info, task_info):
    """
    Verify the export_process_jsonld task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract metrics
    output_exists = result.get("output_exists", False)
    valid_zip = result.get("is_valid_zip", False)
    has_process_folder = result.get("has_process_folder", False)
    keywords_found = result.get("keywords_found", False)
    db_imported = result.get("db_imported", False)
    created_during_task = result.get("file_created_during_task", False)
    
    score = 0
    feedback = []

    # 3. Scoring Logic
    
    # Criterion 1: Database Import (15 pts)
    if db_imported:
        score += 15
        feedback.append("USLCI database imported successfully.")
    else:
        feedback.append("Failed to import USLCI database.")

    # Criterion 2: File Existence & Validity (40 pts)
    if output_exists:
        if created_during_task:
            score += 20 # Exists and fresh
            feedback.append("Export file created.")
            
            if valid_zip:
                score += 10
                feedback.append("File is a valid zip archive.")
                
                if has_process_folder:
                    score += 10
                    feedback.append("Zip structure contains 'processes' folder (JSON-LD format).")
                else:
                    feedback.append("Zip structure incorrect (missing 'processes' folder).")
            else:
                feedback.append("File is not a valid zip archive.")
        else:
            feedback.append("File exists but was not created during this task (stale).")
    else:
        feedback.append("No export file found at expected path.")

    # Criterion 3: Content Verification (25 pts)
    if keywords_found:
        score += 25
        feedback.append("Exported content matches 'natural gas'/'electricity' requirement.")
    elif valid_zip:
        feedback.append("Exported content does NOT contain required keywords (wrong process?).")

    # Criterion 4: VLM Verification (20 pts)
    # Only run if we have some programmatic success to verify process
    vlm_score = 0
    if output_exists or db_imported:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=TRAJECTORY_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("import_attempted"): vlm_score += 5
                if parsed.get("process_search_visible"): vlm_score += 5
                if parsed.get("export_dialog_visible"): vlm_score += 5
                if parsed.get("save_dialog_visible"): vlm_score += 5
                
                if vlm_score > 0:
                    feedback.append(f"VLM verification passed ({vlm_score}/20 pts).")
            else:
                # Fallback if VLM fails but file is perfect
                if keywords_found: vlm_score = 20
                feedback.append("VLM analysis failed (awarding points based on file quality).")
        else:
            feedback.append("No frames available for VLM.")
    
    score += vlm_score

    # Final Pass Determination
    # Must have created a valid zip file with content to pass
    passed = (output_exists and valid_zip and keywords_found and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }