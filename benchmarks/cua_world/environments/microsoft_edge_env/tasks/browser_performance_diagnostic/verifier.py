#!/usr/bin/env python3
"""
Verifier for browser_performance_diagnostic task.

Verifies:
1. Report creation and content (Version, Sites, Memory usage, Optimizations).
2. Browser History (Visits to required sites and internal pages).
3. Browser Preferences (Sleeping tabs and Startup boost enabled).
4. Anti-gaming (Time checks).
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_browser_performance_diagnostic(traj, env_info, task_info):
    """
    Verify the Browser Performance Diagnostic task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Target data
    target_domains = ["bbc.com", "nytimes.com", "github.com", "wikipedia.org", "weather.gov"]
    required_internal = ["edge://version", "edge://process-internals"]
    
    # Load result from container
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
    
    task_start_ts = result.get("task_start_ts", 0)
    
    # --- 1. REPORT VERIFICATION (40 pts) ---
    report = result.get("report", {})
    report_content = report.get("content", "").lower()
    
    # Exists and created after start
    if report.get("exists") and report.get("modified_ts", 0) > task_start_ts:
        score += 10
        feedback_parts.append("Report created")
        
        # Check content requirements
        
        # Edge Version (look for x.x.x.x pattern)
        if re.search(r'\d+\.\d+\.\d+\.\d+', report_content):
            score += 5
            feedback_parts.append("Version found")
        
        # Memory usage data (look for MB/KB or numbers associated with memory)
        if re.search(r'\d+\s*(mb|kb|%|megabytes)', report_content):
            score += 10
            feedback_parts.append("Memory data found")
            
        # Optimization mentions
        if "sleeping tab" in report_content:
            score += 5
        if "startup boost" in report_content:
            score += 5
            
        # Target sites mention check
        sites_mentioned = sum(1 for d in target_domains if d.split('.')[0] in report_content)
        if sites_mentioned >= 3:
            score += 5
            feedback_parts.append(f"{sites_mentioned} sites mentioned")
            
    else:
        feedback_parts.append("Report missing or too old")

    # --- 2. HISTORY VERIFICATION (30 pts) ---
    history = result.get("history", [])
    visited_urls = [h.get("url", "").lower() for h in history]
    
    # Check websites
    sites_visited = 0
    for domain in target_domains:
        if any(domain in url for url in visited_urls):
            sites_visited += 1
            
    # 5 pts per site, max 25
    site_score = min(25, sites_visited * 5)
    score += site_score
    feedback_parts.append(f"Visited {sites_visited}/5 target sites")
    
    # Check internal pages (harder to catch in history sometimes, but edge://version usually shows up)
    # Note: edge://process-internals might not appear in history db, so we check edge://version mainly
    if any("edge://version" in url for url in visited_urls):
        score += 5
        feedback_parts.append("Internal version page visited")

    # --- 3. PREFERENCES VERIFICATION (30 pts) ---
    prefs = result.get("preferences", {})
    
    # Sleeping tabs
    st_prefs = prefs.get("sleeping_tabs", {})
    # Check if enabled is explicitly True
    if st_prefs.get("enabled") is True:
        score += 15
        feedback_parts.append("Sleeping tabs ENABLED")
    else:
        feedback_parts.append("Sleeping tabs NOT enabled")
        
    # Startup boost
    sb_prefs = prefs.get("startup_boost", {})
    if sb_prefs.get("enabled") is True:
        score += 15
        feedback_parts.append("Startup boost ENABLED")
    else:
        feedback_parts.append("Startup boost NOT enabled")

    # Calculate Pass/Fail
    # Threshold: 60 pts
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }