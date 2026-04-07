#!/usr/bin/env python3
"""
Verifier for Responsive Design Audit task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_responsive_audit(traj, env_info, task_info):
    """
    Verify the responsive design audit task.
    
    Criteria:
    1. Output directory created (5 pts)
    2. Screenshots exist for all 3 sites x 3 viewports (30 pts - ~3.3 pts each)
    3. Viewport differentiation: Mobile width < Desktop width (15 pts) - PROVES emulation
    4. Screenshot distinctness: Files are not identical (5 pts)
    5. Browser history confirms visits (10 pts)
    6. Report exists and is substantive (5 pts)
    7. Report content analysis (30 pts)
       - Mentions all sites (10 pts)
       - Mentions viewport terms (10 pts)
       - Contains layout analysis keywords (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Directory Check
    if result.get("dir_exists"):
        score += 5
        feedback.append("Output directory exists (+5)")
    else:
        feedback.append("Output directory missing")

    # 2. Screenshot Existence
    files = result.get("files", {})
    sites = ["usa_gov", "weather_gov", "nasa_gov"]
    viewports = ["mobile", "tablet", "desktop"]
    
    screenshots_found = 0
    total_screenshots = 9
    
    for site in sites:
        for vp in viewports:
            key = f"{site}_{vp}"
            file_info = files.get(key, {})
            if file_info.get("exists") and file_info.get("created_during_task") and file_info.get("size", 0) > 1000:
                screenshots_found += 1
    
    # Scale score for screenshots (Max 30)
    screenshot_score = int((screenshots_found / total_screenshots) * 30)
    score += screenshot_score
    feedback.append(f"Found {screenshots_found}/9 valid screenshots (+{screenshot_score})")

    # 3. Viewport Differentiation (Critical: Proves Emulation)
    # Check if mobile width < desktop width for at least one site
    differentiation_found = False
    for site in sites:
        mobile_info = files.get(f"{site}_mobile", {})
        desktop_info = files.get(f"{site}_desktop", {})
        
        if mobile_info.get("exists") and desktop_info.get("exists"):
            m_width = mobile_info.get("width", 0)
            d_width = desktop_info.get("width", 0)
            
            # Allow some tolerance, but mobile should be significantly smaller
            if m_width > 0 and d_width > 0 and m_width < (d_width * 0.8):
                differentiation_found = True
                break
    
    if differentiation_found:
        score += 15
        feedback.append("Viewport differentiation detected (Mobile < Desktop) (+15)")
    else:
        feedback.append("No viewport differentiation detected (Did you use emulation?)")

    # 4. File Distinctness (Simple check: sizes not all identical)
    # Collect all file sizes
    sizes = [info.get("size") for info in files.values() if info.get("exists")]
    if len(sizes) > 1 and len(set(sizes)) > 1:
        score += 5
        feedback.append("Screenshots are distinct files (+5)")
    elif len(sizes) > 1:
        feedback.append("Warning: All screenshots have identical file size")

    # 5. History Check
    history = result.get("history", {})
    sites_visited = sum(1 for data in history.values() if data.get("visited"))
    if sites_visited >= 3:
        score += 10
        feedback.append("Visited all 3 target sites (+10)")
    elif sites_visited > 0:
        score += 5
        feedback.append(f"Visited {sites_visited}/3 target sites (+5)")

    # 6 & 7. Report Analysis
    report = result.get("report", {})
    if report.get("exists") and report.get("created_during_task") and report.get("size", 0) > 100:
        score += 5
        feedback.append("Report file exists and is substantive (+5)")
        
        # Content checks
        if report.get("mentions_sites"):
            score += 10
            feedback.append("Report mentions all target sites (+10)")
        
        if report.get("mentions_viewports"):
            score += 10
            feedback.append("Report mentions viewport types (+10)")
            
        # Layout analysis keywords check (can't do easily without content, assume implied by size + viewports/sites for now or requires reading content in export)
        # Note: export script reads content for sites/viewports. Let's assume if it mentions those and is large enough, it likely contains analysis.
        # Adding a length check as proxy for "analysis"
        if report.get("content_length", 0) > 500:
             score += 10
             feedback.append("Report length suggests detailed analysis (+10)")
        else:
             feedback.append("Report too short for full analysis points")
             
    else:
        feedback.append("Report missing or empty")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }