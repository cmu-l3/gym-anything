#!/usr/bin/env python3
"""
Verifier for dailymed_medication_research task.

Verifies:
1. Browser history for DailyMed visits.
2. Bookmark creation and organization.
3. PDF downloads of drug labels.
4. JSON file content correctness (NDC, boxed warnings, etc.).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth Data
REQUIRED_DRUGS = ["metformin", "lisinopril", "atorvastatin", "omeprazole", "sertraline"]

GROUND_TRUTH_WARNINGS = {
    "metformin": True,      # Lactic Acidosis
    "lisinopril": True,     # Fetal Toxicity
    "atorvastatin": False,  # None
    "omeprazole": False,    # None
    "sertraline": True      # Suicidality
}

# Regex for NDC format: XXXXX-XXXX-XX or XXXXX-XXXX-X (4-5 digits, 3-4 digits, 1-2 digits)
NDC_PATTERN = re.compile(r'^\d{4,5}-\d{3,4}-\d{1,2}$')

def verify_dailymed_medication_research(traj, env_info, task_info):
    """
    Verify the DailyMed research task using the exported result JSON 
    and the user's output file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Retrieve the metadata result file
    task_result_path = "/tmp/task_result.json"
    with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp_meta:
        local_meta_path = tmp_meta.name

    try:
        copy_from_env(task_result_path, local_meta_path)
        with open(local_meta_path, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}
    finally:
        if os.path.exists(local_meta_path):
            os.unlink(local_meta_path)

    # 2. Retrieve the user's JSON output file
    user_json_path = "/home/ga/Documents/medication_reference.json"
    user_data = {}
    json_load_error = None
    
    if meta.get("json_exists") and meta.get("json_fresh"):
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp_user:
            local_user_path = tmp_user.name
        
        try:
            copy_from_env(user_json_path, local_user_path)
            with open(local_user_path, 'r') as f:
                user_data = json.load(f)
        except Exception as e:
            json_load_error = str(e)
        finally:
            if os.path.exists(local_user_path):
                os.unlink(local_user_path)

    # === SCORING LOGIC ===
    score = 0
    feedback = []

    # Criterion 1: Browser History (15 pts)
    visits = meta.get("dailymed_visits", 0)
    if visits >= 5:
        score += 15
        feedback.append(f"Visited DailyMed {visits} times (15/15)")
    elif visits >= 1:
        score += 5
        feedback.append(f"Visited DailyMed {visits} times, expected >=5 (5/15)")
    else:
        feedback.append("No history of visiting DailyMed (0/15)")

    # Criterion 2: Bookmarks (20 pts total)
    # Folder exists (10 pts)
    if meta.get("bookmark_folder_exists"):
        score += 10
        feedback.append("'Medication Reference' bookmark folder created (10/10)")
        
        # Count (10 pts)
        count = meta.get("bookmark_count", 0)
        urls = meta.get("bookmark_urls", "")
        
        # Check if URLs look like DailyMed
        valid_bm_count = 0
        if urls:
            valid_bm_count = len([u for u in urls.split(',') if 'dailymed' in u.lower()])
            
        if valid_bm_count >= 5:
            score += 10
            feedback.append(f"Found {valid_bm_count} DailyMed bookmarks (10/10)")
        elif valid_bm_count >= 1:
            score += 5
            feedback.append(f"Found {valid_bm_count} DailyMed bookmarks, expected 5 (5/10)")
        else:
            feedback.append(f"Found {count} bookmarks, but none matched DailyMed (0/10)")
    else:
        feedback.append("Bookmark folder 'Medication Reference' not found (0/20)")

    # Criterion 3: PDF Downloads (15 pts)
    pdf_count = meta.get("pdf_download_count", 0)
    if pdf_count >= 2:
        score += 15
        feedback.append(f"Downloaded {pdf_count} PDF label files (15/15)")
    elif pdf_count == 1:
        score += 7
        feedback.append("Downloaded 1 PDF label file, expected 2 (7/15)")
    else:
        feedback.append("No valid PDF downloads detected (0/15)")

    # Criterion 4: JSON File Existence & Structure (10 pts)
    if meta.get("json_exists") and meta.get("json_fresh") and not json_load_error:
        score += 10
        feedback.append("JSON output file exists, is valid, and created during task (10/10)")
        
        # Criterion 5: Content Verification (40 pts total)
        # Check all drug keys exist
        drugs_found = [d for d in REQUIRED_DRUGS if d in user_data]
        if len(drugs_found) == 5:
            score += 10
            feedback.append("All 5 required drugs present in JSON (10/10)")
        else:
            partial = len(drugs_found) * 2
            score += partial
            feedback.append(f"Found {len(drugs_found)}/5 drugs in JSON ({partial}/10)")
        
        # Check NDC Format (10 pts)
        ndc_valid_count = 0
        warning_correct_count = 0
        
        for drug in drugs_found:
            entry = user_data[drug]
            
            # NDC Check
            ndc = str(entry.get("ndc", "")).strip()
            if NDC_PATTERN.match(ndc):
                ndc_valid_count += 1
            
            # Warning Check
            # Allow lenient truthy/falsy check
            user_warning = entry.get("boxed_warning")
            expected_warning = GROUND_TRUTH_WARNINGS[drug]
            
            if bool(user_warning) == expected_warning:
                warning_correct_count += 1
        
        # Score NDC
        if ndc_valid_count >= 4:
            score += 10
            feedback.append(f"Valid NDC formats for {ndc_valid_count} drugs (10/10)")
        elif ndc_valid_count > 0:
            score += 5
            feedback.append(f"Valid NDC formats for {ndc_valid_count} drugs (5/10)")
        else:
            feedback.append("No valid NDC formats found (e.g. 12345-678-90) (0/10)")
            
        # Score Warnings
        # 5 correct = 20 pts, 4 = 15, 3 = 10, <3 = 0
        if warning_correct_count == 5:
            score += 20
            feedback.append("All boxed warning statuses correct (20/20)")
        elif warning_correct_count == 4:
            score += 15
            feedback.append("4/5 boxed warning statuses correct (15/20)")
        elif warning_correct_count == 3:
            score += 10
            feedback.append("3/5 boxed warning statuses correct (10/20)")
        else:
            feedback.append(f"Only {warning_correct_count}/5 boxed warning statuses correct (0/20)")

    elif json_load_error:
        feedback.append(f"JSON file exists but failed to parse: {json_load_error} (0/50)")
    else:
        feedback.append("JSON output file missing or not created during task (0/50)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }