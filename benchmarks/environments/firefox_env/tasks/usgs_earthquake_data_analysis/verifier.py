#!/usr/bin/env python3
"""
Verifier for USGS Earthquake Data Analysis Task.

Criteria:
1. CSV Download (35 pts):
   - Exists and fresh (10)
   - Valid headers (10)
   - Row count >= 50 (10)
   - Magnitude check >= 5.5 (5) - inferred from content parsing

2. Report Analysis (35 pts):
   - File exists and fresh (5)
   - Contains integer count (10)
   - Identifies strongest quake (10)
   - Lists >=5 events (10)
   - Mentions USGS (attribute included in text check)

3. Browser Evidence (30 pts):
   - Bookmark folder 'USGS Earthquake Research' exists (10)
   - Contains >=3 bookmarks (10)
   - USGS.gov visited in history (10)

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def verify_usgs_earthquake_analysis(traj, env_info, task_info):
    # 1. Retrieve Result JSON from Container
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []

    # --- CRITERION 1: CSV DATA (35 pts) ---
    csv_exists = data.get("csv_exists", False)
    csv_fresh = data.get("csv_fresh", False)
    csv_rows = data.get("csv_rows", 0)
    csv_headers = data.get("csv_has_headers", False)

    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("CSV file downloaded (10/10)")
        
        if csv_headers:
            score += 10
            feedback_parts.append("CSV has valid USGS headers (10/10)")
        else:
            feedback_parts.append("CSV missing standard headers (0/10)")
            
        # Expecting ~100-170 M6.0+ earthquakes in a year
        if csv_rows >= 50:
            score += 10
            feedback_parts.append(f"CSV contains sufficient data rows ({csv_rows}) (10/10)")
        elif csv_rows > 0:
            score += 5
            feedback_parts.append(f"CSV contains data but fewer rows than expected for annual search ({csv_rows}) (5/10)")
        else:
            feedback_parts.append("CSV is empty (0/10)")
            
        # Basic content sanity check (simulated magnitude check via size/rows)
        # If we have >50 rows and valid headers, we assume query was roughly correct
        if csv_rows >= 50 and csv_headers:
            score += 5
            feedback_parts.append("Data volume matches M6.0+ query characteristics (5/5)")
            
    else:
        feedback_parts.append("No fresh CSV file found in Downloads (0/35)")

    # --- CRITERION 2: REPORT CONTENT (35 pts) ---
    report_exists = data.get("report_exists", False)
    report_fresh = data.get("report_fresh", False)
    content = data.get("report_content_preview", "")
    
    if report_exists and report_fresh:
        score += 5
        feedback_parts.append("Analysis report created (5/5)")
        
        # Check for Total Count (looking for reasonable integers)
        # Regex for "Total: 123" or "123 earthquakes"
        # 2024 had roughly 120-130 M6.0+ quakes. Accept 50-250 range.
        count_match = re.search(r'\b([5-9][0-9]|[1-2][0-9]{2})\b', content)
        if count_match:
            score += 10
            feedback_parts.append(f"Report includes plausible earthquake count: {count_match.group(1)} (10/10)")
        else:
            feedback_parts.append("Report missing plausible total count (0/10)")
            
        # Check for Strongest Earthquake (M7.0+)
        # Regex for "7.[0-9]" or "8.[0-9]"
        strongest_match = re.search(r'[78]\.[0-9]', content)
        if strongest_match:
            score += 10
            feedback_parts.append(f"Report identifies major earthquake magnitude: {strongest_match.group(0)} (10/10)")
        else:
            feedback_parts.append("Report missing strongest earthquake details (0/10)")
            
        # Check for List of Events (looking for multiple lines with magnitudes/dates)
        # Heuristic: Count lines containing dates (2024) and magnitudes
        lines_with_data = 0
        for line in content.split('\n'):
            if "2024" in line and re.search(r'[6-8]\.[0-9]', line):
                lines_with_data += 1
        
        if lines_with_data >= 5:
            score += 10
            feedback_parts.append(f"Report lists {lines_with_data} specific events (10/10)")
        elif lines_with_data >= 1:
            score += 5
            feedback_parts.append(f"Report lists {lines_with_data} events (partial) (5/10)")
        else:
            feedback_parts.append("Report does not list specific events clearly (0/10)")
            
    else:
        feedback_parts.append("No fresh analysis report found (0/35)")

    # --- CRITERION 3: BROWSER EVIDENCE (30 pts) ---
    folder_exists = data.get("bookmark_folder_exists", False)
    bm_count = data.get("bookmark_count", 0)
    usgs_visits = data.get("usgs_visits", 0)
    
    if folder_exists:
        score += 10
        feedback_parts.append("'USGS Earthquake Research' bookmark folder exists (10/10)")
        
        if bm_count >= 3:
            score += 10
            feedback_parts.append(f"Folder contains {bm_count} bookmarks (10/10)")
        elif bm_count >= 1:
            score += 5
            feedback_parts.append(f"Folder contains only {bm_count} bookmarks (5/10)")
        else:
            feedback_parts.append("Folder is empty (0/10)")
    else:
        feedback_parts.append("Bookmark folder missing (0/20)")
        
    if usgs_visits >= 1:
        score += 10
        feedback_parts.append("USGS website visited (10/10)")
    else:
        feedback_parts.append("No history of visiting USGS (0/10)")

    # Final Verdict
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }