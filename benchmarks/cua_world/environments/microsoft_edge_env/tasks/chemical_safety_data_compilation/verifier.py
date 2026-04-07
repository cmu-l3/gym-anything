#!/usr/bin/env python3
"""
Verifier for Chemical Safety Data Compilation task.

Scoring Breakdown (100 points total):
1. Directory Creation (5 pts): ~/Documents/Safety_Data/ exists.
2. PDF Archives (30 pts): 3 PDFs exist, correct names, >30KB, created during task.
3. Bookmarks (25 pts): "Emergency Protocols" folder exists with 3 CDC NIOSH links.
4. Summary Content (25 pts): Text file exists, has First Aid keywords, mentions all 3 chemicals.
5. Formatting/Naming (15 pts): Filenames match exactly.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_safety_data(traj, env_info, task_info):
    # 1. Setup - Get data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify Directory (5 pts)
    if result.get("dir_exists"):
        score += 5
        feedback.append("Directory created (5/5)")
    else:
        feedback.append("Directory ~/Documents/Safety_Data/ missing (0/5)")

    # 3. Verify PDFs (30 pts - 10 per file)
    required_pdfs = ["ammonia.pdf", "chlorine.pdf", "formaldehyde.pdf"]
    pdf_score = 0
    files_data = result.get("files", {})
    
    for pdf in required_pdfs:
        f_info = files_data.get(pdf, {})
        if f_info.get("exists"):
            # Check for anti-gaming: size and timestamp
            if f_info.get("size", 0) > 30000 and f_info.get("created_during_task"):
                pdf_score += 10
            else:
                feedback.append(f"{pdf} exists but is too small or old (0/10)")
        else:
            feedback.append(f"{pdf} missing (0/10)")
    
    score += pdf_score
    feedback.append(f"PDF Archives: {pdf_score}/30")

    # 4. Verify Bookmarks (25 pts)
    bm_data = result.get("bookmarks", {})
    bm_score = 0
    if bm_data.get("folder_found"):
        bm_score += 10
        valid_links = bm_data.get("valid_links_count", 0)
        # 5 pts per valid link, up to 15
        link_points = min(valid_links * 5, 15)
        bm_score += link_points
        feedback.append(f"Bookmarks: Folder found, {valid_links} valid links ({bm_score}/25)")
    else:
        feedback.append("Bookmarks: 'Emergency Protocols' folder not found (0/25)")
    
    score += bm_score

    # 5. Verify Summary Content (25 pts)
    summary = result.get("summary_content", {})
    summary_score = 0
    if summary.get("exists"):
        summary_score += 5 # Existence
        if summary.get("has_keywords"):
            summary_score += 10 # Keywords present
        else:
            feedback.append("Summary missing First Aid keywords")
            
        if summary.get("mentions_chemicals"):
            summary_score += 10 # Chemical names present
        else:
            feedback.append("Summary missing chemical names")
    else:
        feedback.append("Summary file missing (0/25)")
        
    score += summary_score
    feedback.append(f"Summary Content: {summary_score}/25")

    # 6. Formatting/Naming (15 pts)
    # Implicitly checked in section 3, but we award points for perfection here
    format_score = 0
    if pdf_score == 30 and summary.get("exists"):
        format_score = 15
    elif pdf_score >= 20:
        format_score = 10
    
    score += format_score
    feedback.append(f"Formatting/Naming consistency: {format_score}/15")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }