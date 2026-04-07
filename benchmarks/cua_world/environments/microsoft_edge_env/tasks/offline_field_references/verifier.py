#!/usr/bin/env python3
"""
Verifier for offline_field_references task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_offline_field_references(traj, env_info, task_info):
    """
    Verify that the agent saved the required web pages and created the index.
    
    Scoring Criteria (Total 100):
    1. Directory '/home/ga/Documents/offline_references/' exists (10 pts)
    2. At least 3 HTML files > 5KB exist (proxy for "saved pages") (30 pts - 10 each)
    3. Browser history shows visits to required domains (20 pts - ~6.6 each)
    4. Index file exists and modified after task start (10 pts)
    5. Index file content analysis:
       - Header present (5 pts)
       - Mentions required domains (15 pts - 5 each)
       - Sufficient length/detail (10 pts)
    
    Pass Threshold: 65 points
    """
    
    # 1. Setup and load result
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
    
    # Metadata / Thresholds
    min_html_size = task_info.get('metadata', {}).get('min_html_size_bytes', 5000)
    
    # Criterion 1: Directory Structure (10 pts)
    if result.get("directory_exists"):
        score += 10
        feedback.append("Directory created.")
    else:
        feedback.append("Target directory not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Saved Files (30 pts)
    # We look for files created during task and > min_size
    valid_saves = 0
    html_files = result.get("html_files", [])
    
    for f in html_files:
        if f["created_during_task"] and f["size"] > min_html_size:
            valid_saves += 1
            
    # Cap valid saves at 3 for scoring
    scored_saves = min(valid_saves, 3)
    score += (scored_saves * 10)
    feedback.append(f"Found {valid_saves} valid saved HTML files (>{min_html_size/1000}KB).")

    # Criterion 3: Browser History (20 pts)
    # Domains: usda.gov, epa.gov, nass.usda.gov
    history = result.get("history_visits", {})
    domains_visited = 0
    required_domains = ["usda.gov", "epa.gov", "nass.usda.gov"]
    
    for domain in required_domains:
        if history.get(domain, {}).get("visited", False):
            domains_visited += 1
    
    # 20 points distributed across 3 domains is awkward, let's say 7, 7, 6 approx.
    # Simple formula: int(20 * (visited / 3))
    history_score = int(20 * (domains_visited / 3))
    score += history_score
    feedback.append(f"Visited {domains_visited}/3 required domains.")

    # Criterion 4: Index File Existence (10 pts)
    index_info = result.get("index_file", {})
    if index_info.get("exists") and index_info.get("modified_after_start"):
        score += 10
        feedback.append("Index file created.")
    else:
        feedback.append("Index file missing or not updated.")
        
    # Criterion 5: Index Content (30 pts)
    if index_info.get("exists"):
        content = index_info.get("content", "").lower()
        
        # Header check (5 pts)
        if "offline field reference" in content:
            score += 5
            feedback.append("Index header found.")
            
        # Domain mentions (15 pts)
        mentions = 0
        for domain in required_domains:
            # simple check for domain name in text
            base_domain = domain.replace("www.", "").replace("https://", "")
            if base_domain in content:
                mentions += 1
        
        score += (mentions * 5)
        feedback.append(f"Index references {mentions}/3 sources.")
        
        # Detail check (10 pts)
        # 3 items * roughly 50 chars each = 150 chars minimum expected
        if len(content) > 150:
            score += 10
            feedback.append("Index content length sufficient.")
        elif len(content) > 50:
            score += 5
            feedback.append("Index content sparse.")
        else:
            feedback.append("Index content too short.")

    # Final Verification
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }