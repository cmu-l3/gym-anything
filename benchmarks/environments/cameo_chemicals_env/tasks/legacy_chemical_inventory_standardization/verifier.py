#!/usr/bin/env python3
import json
import os
import csv
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for flexible comparison."""
    if not text:
        return ""
    # Remove special chars, lower case, strip
    return re.sub(r'[^a-zA-Z0-9]', '', str(text)).lower()

def verify_legacy_inventory(traj, env_info, task_info):
    """
    Verifies the legacy chemical inventory task.
    
    Scoring Criteria:
    1. CSV File Creation (10 pts) - Must be created *during* task
    2. CSV Structure (10 pts) - Headers present
    3. Content Accuracy (80 pts) - Correct CAS/UN for 6 chemicals (~13 pts each)
    4. VLM Validation - Penalty if agent didn't seemingly use the app
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load export result
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # Load the CSV file
    csv_content = []
    temp_csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/Documents/standardized_inventory.csv", temp_csv_file.name)
        with open(temp_csv_file.name, 'r', encoding='utf-8', errors='replace') as f:
            # Handle potential BOM or weird encoding
            content = f.read()
            # If file is empty
            if not content.strip():
                raise ValueError("File is empty")
            
            f.seek(0)
            reader = csv.DictReader(f)
            # Normalize headers
            reader.fieldnames = [h.strip() for h in reader.fieldnames] if reader.fieldnames else []
            csv_content = list(reader)
    except Exception as e:
        logger.warning(f"Failed to read CSV: {e}")
        csv_content = [] # Treat as empty
    finally:
        if os.path.exists(temp_csv_file.name):
            os.unlink(temp_csv_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criteria A: File Existence & Anti-Gaming (10 pts)
    if task_result.get("output_exists") and task_result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("CSV file created successfully.")
    elif task_result.get("output_exists"):
        score += 5
        feedback_parts.append("CSV file exists but timestamp check failed (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}

    # Criteria B: CSV Structure (10 pts)
    required_cols = ["Input Name", "Standard Name", "CAS Number", "UN Number"]
    if csv_content:
        headers = csv_content[0].keys()
        # fuzzy match headers
        header_map = {normalize_text(h): h for h in headers}
        missing = [col for col in required_cols if normalize_text(col) not in header_map]
        
        if not missing:
            score += 10
            feedback_parts.append("CSV structure correct.")
        else:
            feedback_parts.append(f"Missing columns: {missing}")
    else:
        feedback_parts.append("CSV file is empty or invalid.")

    # Criteria C: Content Accuracy (Max 80 pts)
    ground_truth = task_info.get("metadata", {}).get("ground_truth", {})
    
    # We allow some flexibility in matching the input name row
    correct_entries = 0
    total_entries = len(ground_truth)
    points_per_entry = 80.0 / total_entries
    
    for input_key, truth in ground_truth.items():
        # Find matching row
        row = None
        for r in csv_content:
            # Check Input Name column
            # Try to find the column that likely contains the input name
            input_val = ""
            for k, v in r.items():
                if "input" in k.lower():
                    input_val = v
                    break
            
            if normalize_text(input_key) in normalize_text(input_val):
                row = r
                break
        
        if row:
            # Extract agent values
            agent_cas = ""
            agent_un = ""
            
            # Find CAS and UN columns flexibly
            for k, v in row.items():
                if "cas" in k.lower():
                    agent_cas = normalize_text(v)
                if "un" in k.lower():
                    agent_un = normalize_text(v)
            
            truth_cas = normalize_text(truth["cas"])
            truth_un = normalize_text(truth["un"])
            
            # Check match (CAS is strict, UN is strict)
            if truth_cas in agent_cas and truth_un in agent_un:
                correct_entries += 1
                score += points_per_entry
            else:
                feedback_parts.append(f"Incorrect data for {input_key} (Exp: CAS {truth['cas']}, UN {truth['un']}).")
        else:
            feedback_parts.append(f"Missing entry for {input_key}.")

    score = round(score)
    feedback_parts.append(f"Content Accuracy: {correct_entries}/{total_entries} correct.")

    # 3. VLM Verification (Validation only - does not add points, but flags cheating)
    # If score is high, we want to ensure they actually looked it up.
    if score > 50:
        frames = sample_trajectory_frames(traj, n=5)
        # We don't verify strict steps, just that CAMEO was involved
        vlm_prompt = (
            "Does the user appear to be using the CAMEO Chemicals website? "
            "Look for blue/white NOAA pages, search bars, or chemical datasheets. "
            "Answer yes or no."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success") and "no" in vlm_res.get("response", "").lower():
                feedback_parts.append("Warning: Visual verification did not detect CAMEO Chemicals usage.")
                # We don't zero the score because VLM can be flaky, but we note it.
        except Exception:
            pass # Ignore VLM errors

    passed = score >= 60 and correct_entries >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }