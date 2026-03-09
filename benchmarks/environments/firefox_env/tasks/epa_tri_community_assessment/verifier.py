#!/usr/bin/env python3
"""
Verifier for epa_tri_community_assessment task.

Scoring Criteria (100 points total):
1. [15 pts] History: Visits to epa.gov (Evidence of research)
2. [10 pts] Bookmarks: 'Community Health Research' folder exists
3. [10 pts] Bookmarks: Folder contains >= 4 bookmarks from epa.gov
4. [15 pts] Download: Valid data file (>10KB) downloaded during task
5. [5 pts] Report: File exists and is fresh
6. [10 pts] Report Content: Mentions both required locations (Harris, St. James)
7. [15 pts] Report Content: Chemicals (mentions >= 4 valid TRI chemicals)
8. [10 pts] Report Content: Facilities (mentions >= 2 named facilities)
9. [10 pts] Report Content: Quantitative data (numbers appearing near context)

Pass Threshold: 60/100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# List of common TRI chemicals for regex matching (case insensitive)
VALID_CHEMICALS = [
    "Benzene", "Ethylene", "Formaldehyde", "Toluene", "Xylene", "Styrene", 
    "Butadiene", "Ammonia", "Hydrogen cyanide", "Sulfuric acid", "Hydrochloric acid", 
    "Methanol", "Lead", "Mercury", "Dioxin", "Nitrate", "Zinc", "Copper", "Manganese",
    "Acetaldehyde", "Propylene", "Phenol", "Chlorine"
]

def verify_epa_tri_community_assessment(traj, env_info, task_info):
    """
    Verifies the EPA TRI research task.
    """
    # 1. Retrieve Result JSON from Container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    result_path = "/tmp/epa_task_result.json"
    
    # Use a temp file on host to store the copied json
    fd, temp_path = tempfile.mkstemp(suffix='.json')
    os.close(fd)
    
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from agent environment."
        }
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    # 2. Parse Data
    score = 0
    feedback = []
    
    # -- Criterion 1: History (15 pts) --
    epa_visits = data.get("epa_visits", 0)
    if epa_visits >= 3:
        score += 15
        feedback.append("History check passed (multiple EPA pages visited).")
    elif epa_visits > 0:
        score += 5
        feedback.append("History check partial (few EPA pages visited).")
    else:
        feedback.append("No EPA.gov history found.")

    # -- Criterion 2: Bookmark Folder (10 pts) --
    if data.get("bookmark_folder_exists", False):
        score += 10
        feedback.append("Bookmark folder 'Community Health Research' found.")
    else:
        feedback.append("Bookmark folder 'Community Health Research' NOT found.")

    # -- Criterion 3: Bookmark Count (10 pts) --
    epa_bms = data.get("epa_bookmarks_count", 0)
    if epa_bms >= 4:
        score += 10
        feedback.append(f"Bookmark count passed ({epa_bms} EPA bookmarks).")
    elif epa_bms >= 1:
        score += 5
        feedback.append(f"Bookmark count partial ({epa_bms}/4 found).")
    else:
        feedback.append("No EPA bookmarks found in the target folder.")

    # -- Criterion 4: Download (15 pts) --
    if data.get("download_found", False):
        score += 15
        fname = data.get("download_filename", "unknown")
        feedback.append(f"Valid data file downloaded: {fname}.")
    else:
        feedback.append("No valid data file (>10KB) downloaded.")

    # -- Criterion 5: Report Existence (5 pts) --
    report_exists = data.get("report_exists", False)
    report_fresh = data.get("report_fresh", False)
    
    report_content = ""
    if report_exists and report_fresh:
        score += 5
        feedback.append("Report file exists and was created during task.")
        report_content = data.get("report_content", "").lower()
    elif report_exists:
        feedback.append("Report file exists but is old (pre-task).")
        report_content = data.get("report_content", "").lower() # Check content anyway for partial credit logic if needed
    else:
        feedback.append("Report file not found.")

    # -- Content Analysis --
    if report_content:
        # -- Criterion 6: Locations (10 pts) --
        has_harris = "harris" in report_content
        has_st_james = "st. james" in report_content or "st james" in report_content or "cancer alley" in report_content
        
        if has_harris and has_st_james:
            score += 10
            feedback.append("Report covers both required locations.")
        elif has_harris or has_st_james:
            score += 5
            feedback.append("Report covers only one location.")
        else:
            feedback.append("Report missing required locations (Harris, St. James).")

        # -- Criterion 7: Chemicals (15 pts) --
        chem_count = 0
        found_chems = []
        for chem in VALID_CHEMICALS:
            if chem.lower() in report_content:
                chem_count += 1
                found_chems.append(chem)
        
        if chem_count >= 4:
            score += 15
            feedback.append(f"Report lists sufficient chemicals ({len(found_chems)} found).")
        elif chem_count >= 1:
            score += 5
            feedback.append(f"Report lists few chemicals ({len(found_chems)} found).")
        else:
            feedback.append("No recognized toxic chemical names found in report.")

        # -- Criterion 8: Facilities (10 pts) --
        # Simple heuristic: Look for keywords like "Inc", "LLC", "Plant", "Refinery", "Chemical" appearing with capital letters
        # Since we lowercased the content, we look for "refinery", "plant", "complex", "corp", "inc"
        # A better check is if the report contains specific known facilities, but generic is safer for stability.
        # We will assume if they found chemicals and locations, and there are words like "Refinery" or "Plant", they likely named facilities.
        
        facility_keywords = ["refinery", "plant", "chemical", "corp", "company", "inc.", "llc", "exxon", "shell", "chevron", "oxy", "lyondell", "formosa"]
        fac_count = 0
        for kw in facility_keywords:
            if kw in report_content:
                fac_count += 1
        
        # We need at least 2 distinct facility-related keywords to assume 2 facilities were discussed
        if fac_count >= 2:
            score += 10
            feedback.append("Report appears to mention specific facilities.")
        else:
            feedback.append("Report lacks clear facility names.")

        # -- Criterion 9: Quantitative Data (10 pts) --
        # Look for digits
        digits = re.findall(r'\d+', report_content)
        if len(digits) >= 3:
            score += 10
            feedback.append("Report contains quantitative data.")
        else:
            feedback.append("Report lacks sufficient numeric data.")
    else:
        feedback.append("Skipping content checks (no report).")

    # 3. Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }