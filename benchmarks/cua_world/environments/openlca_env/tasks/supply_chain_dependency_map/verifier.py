#!/usr/bin/env python3
"""
Verifier for Supply Chain Dependency Mapping task.

Criteria:
1. Database Import: USLCI database must be imported (Process count > 100).
2. Report Existence: CSV file must exist and be created during the task.
3. Report Structure: CSV must have headers (Process, Amount, Unit).
4. Report Content: At least 5 data rows with numeric amounts.
5. VLM: Visual confirmation of search/navigation/export workflow.
"""

import json
import os
import tempfile
import csv
import logging

logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_supply_chain_dependency_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Database Import (20 pts) ---
    process_count = result_data.get("db_process_count", 0)
    if process_count > 100:
        score += 20
        feedback.append(f"Database imported successfully ({process_count} processes).")
    elif process_count > 0:
        score += 5
        feedback.append("Database created but seems empty or incomplete.")
    else:
        feedback.append("No processes found in database.")

    # --- Criterion 2: File Existence & Timestamp (20 pts) ---
    file_exists = result_data.get("file_exists", False)
    file_fresh = result_data.get("file_created_during_task", False)
    file_size = result_data.get("file_size", 0)

    csv_content = []
    if file_exists and file_fresh and file_size > 10:
        score += 20
        feedback.append("Dependency report file created during task.")
        
        # Load CSV content for further verification
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(result_data.get("file_path"), temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Read using csv reader to handle quoting
                reader = csv.reader(f)
                csv_content = list(reader)
        except Exception as e:
            feedback.append(f"Could not read CSV content: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    elif file_exists:
        score += 5
        feedback.append("File exists but timestamp verification failed (pre-existing?).")
    else:
        feedback.append("No output file found.")

    # --- Criterion 3: CSV Structure & Content (40 pts) ---
    valid_structure = False
    valid_data_rows = 0
    
    if csv_content:
        # Check Header
        header = csv_content[0]
        header_str = " ".join(header).lower()
        if any(x in header_str for x in ["process", "name", "flow"]) and \
           any(x in header_str for x in ["amount", "value", "quantity"]) and \
           any(x in header_str for x in ["unit"]):
            score += 10
            valid_structure = True
            feedback.append("CSV header structure looks correct.")
        else:
            feedback.append(f"CSV header missing required columns. Found: {header}")

        # Check Data Rows
        # Skip header
        data_rows = csv_content[1:]
        
        # Heuristic check for numeric amounts and valid text
        for row in data_rows:
            if len(row) >= 2:
                # Try to find a number in the row
                has_number = False
                for cell in row:
                    try:
                        float(cell.replace(',',''))
                        has_number = True
                        break
                    except ValueError:
                        continue
                if has_number:
                    valid_data_rows += 1
        
        if valid_data_rows >= 5:
            score += 30
            feedback.append(f"Found {valid_data_rows} valid data rows.")
        elif valid_data_rows >= 1:
            score += 10
            feedback.append(f"Found only {valid_data_rows} valid data rows (expected 5+).")
        else:
            feedback.append("CSV contains no valid numeric data rows.")

    # --- Criterion 4: VLM Verification (20 pts) ---
    # Check if agent actually searched or browsed for "natural gas"
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        # We use trajectory sampling provided by framework (passed in 'traj')
        # But we need to define the prompt
        
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            prompt = """You are auditing a user session in OpenLCA software.
The user goal is to find processes that use 'Natural gas'.
Look at these screenshots.
1. Do you see a database import dialog or progress bar?
2. Do you see a search for 'Natural gas' or 'gas' in the navigation or search bar?
3. Do you see a list of processes or 'Usage' view?
4. Do you see an export dialog or spreadsheet view?

Respond JSON: {"database_import": bool, "search_performed": bool, "list_view_seen": bool, "export_seen": bool}"""
            
            res = _vlm_query(query_vlm, prompt, images=frames)
            if res:
                if res.get("database_import"): vlm_score += 5
                if res.get("search_performed"): vlm_score += 5
                if res.get("list_view_seen"): vlm_score += 5
                if res.get("export_seen"): vlm_score += 5
                
                if vlm_score > 0:
                    feedback.append(f"VLM verified workflow steps ({vlm_score} pts).")
            else:
                feedback.append("VLM analysis failed.")
    
    # If VLM unavailable or failed, fallback to trust file evidence slightly more if strong
    if vlm_score == 0 and valid_data_rows >= 5 and process_count > 100:
        score += 20
        feedback.append("VLM skipped, awarding full points based on strong output evidence.")
    else:
        score += vlm_score

    # Final Score Calculation
    passed = score >= 60 and valid_data_rows >= 1
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }