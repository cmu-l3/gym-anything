#!/usr/bin/env python3
"""
Verifier for fema_disaster_history@1

Criteria:
1. Navigation: Visited fema.gov/disaster (10 pts)
2. Data Extraction: JSON file exists, is valid, and contains correct data (45 pts)
   - File exists/valid (15)
   - 3 entries present (10)
   - Correct filtering (CA + Fire + Major Disaster check) (10)
   - Valid data format (DR-####) (10)
3. Document Retrieval: PDF downloaded from FEMA (25 pts)
4. Bookmarks: Folder created with bookmarks (20 pts)
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fema_disaster_history(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Navigation (10 pts) ---
    visits = result.get('history_fema_visits', 0)
    if visits > 0:
        score += 10
        feedback.append("Navigation: Visited FEMA disaster pages.")
    else:
        feedback.append("Navigation: No history of visiting fema.gov/disaster.")

    # --- Criterion 2: Data Extraction (45 pts) ---
    json_exists = result.get('json_exists', False)
    json_valid = result.get('json_valid', False)
    content = result.get('json_content', None)

    if json_exists and json_valid and isinstance(content, list):
        score += 15 # Base points for valid file
        
        # Check count
        if len(content) == 3:
            score += 10
            feedback.append("Data: Correctly extracted 3 entries.")
        else:
            feedback.append(f"Data: Extracted {len(content)} entries (expected 3).")

        # Check content accuracy
        valid_entries = 0
        correct_context = 0
        
        for entry in content:
            # Check ID format (DR-####)
            d_num = entry.get('disaster_number', '')
            if re.match(r'^DR-\d{4}$', d_num):
                valid_entries += 1
            
            # Check context (Fire/Wildfire in title)
            title = entry.get('title', '').lower()
            if 'fire' in title or 'wildfire' in title:
                correct_context += 1
        
        if valid_entries == len(content) and len(content) > 0:
            score += 10
            feedback.append("Data: Disaster IDs valid.")
        
        if correct_context == len(content) and len(content) > 0:
            score += 10
            feedback.append("Data: Titles match 'Fire' incident type.")
        else:
            feedback.append("Data: Some titles do not mention 'Fire'. Check filtering.")

    else:
        feedback.append("Data: Output JSON missing or invalid.")

    # --- Criterion 3: Document Retrieval (25 pts) ---
    pdf_exists = result.get('downloaded_pdf_exists', False)
    pdf_size = result.get('downloaded_pdf_size', 0)
    
    if pdf_exists and pdf_size > 1000: # > 1KB
        score += 25
        feedback.append("Download: PDF document retrieved successfully.")
    elif pdf_exists:
        score += 5
        feedback.append("Download: PDF file found but is empty or too small.")
    else:
        feedback.append("Download: No PDF document found in Downloads.")

    # --- Criterion 4: Bookmarks (20 pts) ---
    folder_exists = result.get('bookmark_folder_exists', False)
    bm_count = result.get('bookmark_count_in_folder', 0)
    
    if folder_exists:
        if bm_count >= 2:
            score += 20
            feedback.append("Bookmarks: Folder created with required bookmarks.")
        elif bm_count > 0:
            score += 10
            feedback.append("Bookmarks: Folder created but missing some bookmarks.")
        else:
            score += 5
            feedback.append("Bookmarks: Folder created but empty.")
    else:
        feedback.append("Bookmarks: 'FEMA Research' folder not found.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }