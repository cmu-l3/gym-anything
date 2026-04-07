#!/usr/bin/env python3
"""
Verifier for drug_interaction_research task.

Criteria:
1. Report file exists, created after task start, contains drug names and key safety terms. (45 pts)
2. Browser history shows visits to authoritative medical sites. (20 pts)
3. New file downloaded (PDF/HTML reference). (15 pts)
4. Bookmark folder 'Patient Safety References' exists with valid links. (20 pts)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_drug_interaction_research(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/drug_interaction_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- CRITERION 1: REPORT (45 pts) ---
    report = result.get("report", {})
    content = report.get("content_check", {})
    
    if report.get("exists") and report.get("modified_after_start"):
        score += 10
        feedback.append("Report created successfully (10/10).")
        
        # Drug names (15 pts)
        drugs_found = sum([content.get("has_warfarin"), content.get("has_lisinopril"), content.get("has_metformin")])
        if drugs_found == 3:
            score += 15
            feedback.append("All 3 drug names found in report (15/15).")
        else:
            partial = drugs_found * 5
            score += partial
            feedback.append(f"Found {drugs_found}/3 drug names in report ({partial}/15).")
            
        # Safety keywords (20 pts)
        if content.get("has_safety_keywords"):
            score += 20
            feedback.append("Report contains relevant safety keywords (20/20).")
        else:
            feedback.append("Report missing key safety terms (interaction, bleeding, etc) (0/20).")
            
    else:
        feedback.append("Report file missing or not modified (0/45).")

    # --- CRITERION 2: HISTORY (20 pts) ---
    hist = result.get("history", {})
    if hist.get("visited_authoritative"):
        score += 20
        domains = ", ".join(hist.get("domains_visited", []))
        feedback.append(f"Visited authoritative sources: {domains} (20/20).")
    else:
        feedback.append("No visits to authoritative medical domains found in history (0/20).")

    # --- CRITERION 3: DOWNLOADS (15 pts) ---
    dl = result.get("downloads", {})
    if dl.get("count_new", 0) > 0:
        score += 15
        feedback.append(f"Downloaded {dl.get('count_new')} new file(s) (15/15).")
    else:
        feedback.append("No new files downloaded (0/15).")

    # --- CRITERION 4: BOOKMARKS (20 pts) ---
    bm = result.get("bookmarks", {})
    if bm.get("folder_exists"):
        score += 10
        feedback.append("Bookmark folder 'Patient Safety References' created (10/10).")
        
        valid_links = bm.get("valid_links_count", 0)
        if valid_links >= 2:
            score += 10
            feedback.append(f"Folder contains {valid_links} authoritative links (10/10).")
        elif valid_links == 1:
            score += 5
            feedback.append("Folder contains only 1 authoritative link (5/10).")
        else:
            feedback.append("Folder exists but contains no authoritative links (0/10).")
    else:
        feedback.append("Bookmark folder 'Patient Safety References' not found (0/20).")

    # --- FINAL VERDICT ---
    passed = score >= 65 and report.get("exists") and hist.get("visited_authoritative")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }