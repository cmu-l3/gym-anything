#!/usr/bin/env python3
"""
Verifier for a11y_compliance_audit task.

Verifies:
1. History: Visits to Wikipedia, Craigslist, Archive.org.
2. File: Existence, freshness, and JSON validity of audit report.
3. Content: 
   - Metadata presence.
   - 3 distinct sites audited.
   - Minimum issue counts met.
   - WCAG criterion format validity.
4. VLM: Checks if Accessibility Inspector was actually used (via trajectory).

Scoring:
- History: 20 pts
- File Exists/Fresh: 10 pts
- Valid JSON Structure: 15 pts
- Content Quality (WCAG refs, issue diversity): 45 pts
- VLM Verification (Tool usage): 10 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_a11y_compliance_audit(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

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
    feedback_parts = []
    
    # 2. History Verification (20 pts)
    visits = result.get("visits", {})
    visited_count = 0
    missing_sites = []
    
    if int(visits.get("wikipedia", 0)) > 0: visited_count += 1
    else: missing_sites.append("Wikipedia")
    
    if int(visits.get("craigslist", 0)) > 0: visited_count += 1
    else: missing_sites.append("Craigslist")
    
    if int(visits.get("archive", 0)) > 0: visited_count += 1
    else: missing_sites.append("Archive.org")
    
    history_score = 0
    if visited_count == 3: history_score = 20
    elif visited_count == 2: history_score = 10
    elif visited_count == 1: history_score = 5
    
    score += history_score
    if missing_sites:
        feedback_parts.append(f"History missing visits for: {', '.join(missing_sites)}")
    else:
        feedback_parts.append("All sites visited")

    # 3. File Verification (10 pts)
    stats = result.get("file_stats", {})
    if stats.get("exists") and stats.get("fresh"):
        score += 10
        feedback_parts.append("Report file created")
    elif stats.get("exists"):
        score += 5
        feedback_parts.append("Report file exists but timestamp is old (reused?)")
    else:
        feedback_parts.append("Report file not found")
        # Critical failure if no file
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. JSON Structure & Content (60 pts total)
    analysis = result.get("json_analysis", {})
    
    if analysis.get("valid_json"):
        score += 15
        feedback_parts.append("Valid JSON")
        
        # Metadata check (5 pts)
        if analysis.get("has_metadata"):
            score += 5
        
        # Site coverage (10 pts)
        # Expected 3 sites
        site_count = analysis.get("site_count", 0)
        if site_count >= 3: score += 10
        elif site_count > 0: score += 5
        
        # WCAG References (20 pts)
        # We want to see valid X.X.X references
        wcag_refs = analysis.get("wcag_refs_valid", 0)
        if wcag_refs >= 6: score += 20 # 2 per site * 3
        elif wcag_refs >= 3: score += 10
        
        # Issue Diversity (10 pts)
        # Do we have different types of issues?
        types = analysis.get("issue_types", [])
        if len(types) >= 3: score += 10
        elif len(types) >= 1: score += 5
        
        feedback_parts.append(f"Content: {site_count} sites, {wcag_refs} valid WCAG refs")
        
    else:
        feedback_parts.append("Invalid JSON content")

    # 5. VLM Verification (10 pts)
    # Check if they actually used the Accessibility Inspector
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at these screenshots of Firefox DevTools. 
            Do you see the 'Accessibility' tab active, or an 'Accessibility Inspector' panel showing a tree of elements?
            Answer YES or NO.
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get("success") and "YES" in vlm_res.get("parsed", {}).get("response", "").upper():
                vlm_score = 10
                feedback_parts.append("VLM confirmed Accessibility Inspector usage")
            else:
                feedback_parts.append("VLM did not detect Accessibility Inspector usage")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final Pass Determination
    # Need 60 points AND valid file
    passed = (score >= 60) and stats.get("exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }