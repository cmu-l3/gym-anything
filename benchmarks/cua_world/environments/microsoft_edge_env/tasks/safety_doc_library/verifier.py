#!/usr/bin/env python3
"""
Verifier for Safety Documentation Library task.
Evaluates file structure, downloaded content, index file quality, and browsing history.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safety_doc_library(traj, env_info, task_info):
    """
    Verifies the Safety Documentation Library task.
    
    Scoring criteria (Total 100):
    1. Directory Structure (10 pts)
    2. OSHA Documents (20 pts)
    3. EPA Documents (15 pts)
    4. PDF Validity (10 pts) - implicit in counting functions
    5. Index File Existence & Size (10 pts)
    6. Index Content - Mentions Cats/Agencies (10 pts)
    7. Index Content - Entries/Depth (5 pts)
    8. Index Content - URLs (5 pts)
    9. Browser History (10 pts)
    10. Anti-gaming / Timestamps (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Data from export script
    structure = result.get("structure", {})
    files = result.get("files", {})
    index = result.get("index_content", {})
    history = result.get("history", {})
    timestamps_valid = result.get("timestamps_valid", False)
    
    # 1. Directory Structure (10 pts)
    if structure.get("base_exists") and structure.get("osha_exists") and structure.get("epa_exists"):
        score += 10
        feedback_parts.append("Directory structure correct")
    else:
        feedback_parts.append("Directory structure missing or incomplete")
        
    # 2. OSHA Documents (20 pts)
    # Export script filters for valid PDFs > 10KB
    osha_count = len(files.get("osha_pdfs", []))
    if osha_count >= 2:
        score += 20
        feedback_parts.append(f"OSHA documents sufficient ({osha_count})")
    elif osha_count == 1:
        score += 10
        feedback_parts.append("OSHA documents partial (1/2)")
    else:
        feedback_parts.append("OSHA documents missing")
        
    # 3. EPA Documents (15 pts)
    epa_count = len(files.get("epa_pdfs", []))
    if epa_count >= 1:
        score += 15
        feedback_parts.append(f"EPA documents sufficient ({epa_count})")
    else:
        feedback_parts.append("EPA documents missing")
        
    # 4. PDF Validity (10 pts)
    # We award this if at least one valid PDF exists in both folders total
    total_valid_pdfs = osha_count + epa_count
    if total_valid_pdfs >= 3:
        score += 10
        feedback_parts.append("All PDF files valid")
    elif total_valid_pdfs > 0:
        score += 5
        feedback_parts.append("Some PDF files valid")
        
    # 5. Index File Existence & Size (10 pts)
    if structure.get("index_exists") and index.get("size", 0) > 200:
        score += 10
        feedback_parts.append("Index file exists and has content")
    elif structure.get("index_exists"):
        score += 5
        feedback_parts.append("Index file exists but is too small/empty")
    else:
        feedback_parts.append("Index file missing")
        
    # 6. Index Content - Mentions (10 pts)
    if index.get("mentions_osha") and index.get("mentions_epa"):
        score += 10
        feedback_parts.append("Index correctly categorizes OSHA and EPA")
    elif index.get("mentions_osha") or index.get("mentions_epa"):
        score += 5
        feedback_parts.append("Index partially categorizes docs")
        
    # 7. Index Content - Entries/Depth (5 pts)
    # Rough check using line count (assuming at least 3 lines per doc or 1 line per doc)
    if index.get("line_count", 0) >= 3:
        score += 5
        feedback_parts.append("Index appears to have entries")
        
    # 8. Index Content - URLs (5 pts)
    if index.get("has_urls"):
        score += 5
        feedback_parts.append("Index contains source URLs")
        
    # 9. Browser History (10 pts)
    if history.get("visited_osha") and history.get("visited_epa"):
        score += 10
        feedback_parts.append("History confirms visits to OSHA and EPA")
    elif history.get("visited_osha") or history.get("visited_epa"):
        score += 5
        feedback_parts.append("History confirms visit to one agency")
    else:
        feedback_parts.append("History does not show visits to agency sites")
        
    # 10. Anti-gaming (5 pts)
    if timestamps_valid and total_valid_pdfs > 0:
        score += 5
    elif not timestamps_valid:
        score = 0 # Penalize heavily if files pre-dated task
        feedback_parts.append("TIMESTAMPS INVALID - Files pre-date task start")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }