#!/usr/bin/env python3
"""
Verifier for web_perf_waterfall_analysis task.

Scoring Breakdown (100 points total):
1. HAR Files (40 pts):
   - At least 3 HAR files exist (10 pts)
   - Files are valid HAR JSON (10 pts)
   - Files were created during task (10 pts)
   - Files contain actual request data (entry count > 0) (10 pts)

2. Performance Report (30 pts):
   - File exists and is valid JSON (10 pts)
   - Contains data for at least 4 of 5 target sites (10 pts)
   - Data values are plausible (not empty/zero) (10 pts)

3. Browser History (20 pts):
   - Evidence of visiting target domains (4 pts per domain)

4. Metadata/Process (10 pts):
   - Screenshot exists (5 pts)
   - Report created during task (5 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_SITES = [
    "news.ycombinator.com",
    "en.wikipedia.org",
    "developer.mozilla.org",
    "www.python.org",
    "docs.github.com"
]

DOMAIN_KEYWORDS = {
    "news.ycombinator.com": "ycombinator",
    "en.wikipedia.org": "wikipedia",
    "developer.mozilla.org": "mozilla",
    "www.python.org": "python",
    "docs.github.com": "github"
}

def verify_web_perf_waterfall_analysis(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # 2. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 3. Verify HAR Files (40 pts)
    har_files = result.get("har_files", [])
    valid_hars = [h for h in har_files if h.get("valid_har") and h.get("entry_count", 0) > 0]
    fresh_hars = [h for h in valid_hars if h.get("fresh")]
    
    # Count
    if len(har_files) >= 3:
        score += 10
        feedback.append(f"Found {len(har_files)} HAR files (+10)")
    else:
        feedback.append(f"Found only {len(har_files)} HAR files (need 3)")

    # Validity
    if len(valid_hars) >= 3:
        score += 10
        feedback.append("HAR files are valid JSON with entries (+10)")
    elif len(valid_hars) > 0:
        score += 5
        feedback.append("Some HAR files are valid (+5)")
    
    # Freshness
    if len(fresh_hars) >= 3:
        score += 10
        feedback.append("HAR files created during task (+10)")
    
    # Content Check (do they match targets?)
    target_matches = 0
    for h in valid_hars:
        domains = str(h.get("domains", [])).lower()
        if any(k in domains for k in DOMAIN_KEYWORDS.values()):
            target_matches += 1
    
    if target_matches >= 3:
        score += 10
        feedback.append("HAR files match target domains (+10)")
    elif target_matches > 0:
        score += 5
        feedback.append("Some HAR files match target domains (+5)")

    # 4. Verify Report (30 pts)
    report = result.get("report", {})
    report_content = report.get("content", {})
    
    if report.get("exists") and report.get("valid_json"):
        score += 10
        feedback.append("Report file exists and is valid JSON (+10)")
        
        # Check coverage
        sites_found = 0
        if isinstance(report_content, dict):
            keys = [k.lower() for k in report_content.keys()]
            for site_keyword in DOMAIN_KEYWORDS.values():
                if any(site_keyword in k for k in keys):
                    sites_found += 1
        
        if sites_found >= 4:
            score += 10
            feedback.append(f"Report covers {sites_found}/5 target sites (+10)")
        elif sites_found >= 1:
            score += 5
            feedback.append(f"Report covers {sites_found}/5 target sites (+5)")
            
        # Check plausibility
        plausible = False
        if sites_found > 0:
            # Check one entry
            first_key = list(report_content.keys())[0]
            entry = report_content[first_key]
            if isinstance(entry, dict) and entry.get("total_requests", 0) > 0:
                plausible = True
        
        if plausible:
            score += 10
            feedback.append("Report values look plausible (+10)")
            
    else:
        feedback.append("Report file missing or invalid")

    # 5. Verify History (20 pts)
    history = result.get("history", {})
    history_hits = 0
    for key, count in history.items():
        # Match against our keywords mapping since history keys might vary slightly
        keyword = key.split('.')[0] # e.g., 'ycombinator' from 'ycombinator.com'
        if count > 0:
            history_hits += 1
    
    # Map hits to score (max 20)
    hist_score = min(20, history_hits * 4)
    score += hist_score
    feedback.append(f"Visited {history_hits} target domains ({hist_score}/20)")

    # 6. Metadata (10 pts)
    if result.get("screenshot_exists"):
        score += 5
        feedback.append("Screenshot exists (+5)")
    
    if report.get("fresh"):
        score += 5
        feedback.append("Report created during task (+5)")

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }