#!/usr/bin/env python3
"""
Verifier for OSHA Construction Safety Research task.
Verifies browser history, bookmarks, downloaded files, and text file content.
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_osha_construction_safety_research(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Visited OSHA.gov (History)
    2. Created correct bookmarks (Bookmarks)
    3. Downloaded a PDF (Filesystem)
    4. Created a comprehensive text checklist (File content analysis)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    history_count = result.get("history_osha_visits", 0)
    bm_folder_found = result.get("bookmark_folder_found", False)
    bm_count = result.get("bookmarks_in_folder", 0)
    pdf_found = result.get("pdf_downloaded", False)
    file_exists = result.get("checklist_file_exists", False)
    file_fresh = result.get("checklist_file_fresh", False)
    content_b64 = result.get("checklist_content_b64", "")
    
    # Decode text content
    content = ""
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except:
            content = ""

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # CRITERION 1: History (15 pts)
    # Expecting visits to homepage + 4 hazard pages, so ~5 distinct pages is good
    if history_count >= 4:
        score += 15
        feedback_parts.append(f"Visited OSHA website thoroughly ({history_count} pages) (+15)")
    elif history_count >= 1:
        score += 5
        feedback_parts.append(f"Visited OSHA website minimally ({history_count} pages) (+5)")
    else:
        feedback_parts.append("Did not visit osha.gov (+0)")

    # CRITERION 2: Bookmarks (25 pts)
    if bm_folder_found:
        score += 10
        feedback_parts.append("'OSHA Construction Safety' folder created (+10)")
        if bm_count >= 4:
            score += 15
            feedback_parts.append(f"Correct number of bookmarks ({bm_count}) (+15)")
        elif bm_count >= 1:
            score += 5
            feedback_parts.append(f"Folder exists but insufficient bookmarks ({bm_count}/4) (+5)")
        else:
            feedback_parts.append("Folder empty (+0)")
    else:
        feedback_parts.append("Bookmark folder not found (+0)")

    # CRITERION 3: PDF Download (15 pts)
    if pdf_found:
        score += 15
        feedback_parts.append("PDF reference document downloaded (+15)")
    else:
        feedback_parts.append("No valid PDF found in Downloads (+0)")

    # CRITERION 4: Checklist File Existence (10 pts)
    if file_exists and file_fresh:
        score += 10
        feedback_parts.append("Checklist file created (+10)")
    elif file_exists:
        score += 5
        feedback_parts.append("Checklist file exists but old (+5)")
    else:
        feedback_parts.append("Checklist file missing (+0)")

    # CRITERION 5: Checklist Content Analysis (35 pts)
    content_score = 0
    if content:
        content_lower = content.lower()
        
        # A. Fatal Four Headers (15 pts)
        # Keywords: fall, struck, electrocution (or electrical), caught (or excavation/trenching)
        hazards_found = 0
        if "fall" in content_lower: hazards_found += 1
        if "struck" in content_lower: hazards_found += 1
        if "electr" in content_lower: hazards_found += 1
        if "caught" in content_lower or "excavat" in content_lower or "trench" in content_lower: hazards_found += 1
        
        if hazards_found == 4:
            content_score += 15
            feedback_parts.append("All 4 hazard categories present in text (+15)")
        elif hazards_found >= 2:
            content_score += 7
            feedback_parts.append(f"Some hazard categories present ({hazards_found}/4) (+7)")
        
        # B. OSHA Citations (10 pts)
        # Pattern: 1926.XXX (e.g., 1926.501, 1926.451)
        citations = re.findall(r"1926\.\d{3}", content)
        unique_citations = len(set(citations))
        
        if unique_citations >= 3:
            content_score += 10
            feedback_parts.append(f"Found {unique_citations} distinct OSHA citations (+10)")
        elif unique_citations >= 1:
            content_score += 5
            feedback_parts.append(f"Found {unique_citations} OSHA citation (+5)")
        else:
            feedback_parts.append("No valid OSHA 1926.XXX citations found (+0)")

        # C. Substantive Content (10 pts)
        # Check if file has enough characters to be a real checklist
        if len(content) > 200:
            content_score += 10
            feedback_parts.append("File content length is sufficient (+10)")
        elif len(content) > 50:
            content_score += 5
            feedback_parts.append("File content is very brief (+5)")
        
    score += content_score

    # 4. Final Verification
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }