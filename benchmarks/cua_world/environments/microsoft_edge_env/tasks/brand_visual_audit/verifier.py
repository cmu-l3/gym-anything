#!/usr/bin/env python3
"""
Verifier for brand_visual_audit task.

Checks:
1. Report file existence and modification time.
2. Content analysis: presence of hex codes, font families, font sizes.
3. Content analysis: mentions of both target sites.
4. Browser history: confirmation of visits to both sites during task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_brand_visual_audit(traj, env_info, task_info):
    """
    Verify the brand visual audit task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load expected metadata thresholds
    metadata = task_info.get('metadata', {})
    min_hex = metadata.get('min_hex_codes', 6)
    min_fonts = metadata.get('min_font_families', 2)
    min_sizes = metadata.get('min_font_sizes', 3)
    
    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Data
    report = result.get('report', {})
    history = result.get('history', {})
    
    score = 0
    feedback = []
    
    # --- Criterion 1: Report Existence & Anti-Gaming (10 pts) ---
    if report.get('exists') and report.get('created_during_task'):
        score += 10
        feedback.append("Report created successfully (10/10)")
    elif report.get('exists'):
        score += 5
        feedback.append("Report exists but timestamp is old/unknown (5/10)")
    else:
        feedback.append("No report file found (0/10)")
    
    # --- Criterion 2: Site Navigation (History Check) (20 pts) ---
    sites_visited = 0
    if history.get('visited_github'):
        sites_visited += 10
        feedback.append("Visited GitHub (10/10)")
    else:
        feedback.append("Did not visit GitHub (0/10)")
        
    if history.get('visited_python'):
        sites_visited += 10
        feedback.append("Visited Python.org (10/10)")
    else:
        feedback.append("Did not visit Python.org (0/10)")
    score += sites_visited
    
    # --- Criterion 3: Report Content - Sites Mentioned (10 pts) ---
    mentions_score = 0
    if report.get('mentions_github'): mentions_score += 5
    if report.get('mentions_python'): mentions_score += 5
    score += mentions_score
    if mentions_score < 10:
        feedback.append(f"Report missing mentions of one or more sites ({mentions_score}/10)")
    else:
        feedback.append("Report covers both sites (10/10)")

    # --- Criterion 4: Hex Colors (20 pts) ---
    hex_count = report.get('content_hex_count', 0)
    if hex_count >= min_hex:
        score += 20
        feedback.append(f"Sufficient color codes found ({hex_count}) (20/20)")
    elif hex_count > 0:
        partial = int(20 * (hex_count / min_hex))
        score += partial
        feedback.append(f"Partial color codes found ({hex_count}/{min_hex}) ({partial}/20)")
    else:
        feedback.append("No hex color codes found in report (0/20)")
        
    # --- Criterion 5: Typography - Families (20 pts) ---
    font_count = report.get('content_font_families', 0)
    if font_count >= min_fonts:
        score += 20
        feedback.append(f"Font information found (20/20)")
    elif font_count > 0:
        score += 10
        feedback.append(f"Minimal font information found (10/20)")
    else:
        feedback.append("No font family information found (0/20)")
        
    # --- Criterion 6: Typography - Sizes (10 pts) ---
    size_count = report.get('content_font_sizes', 0)
    if size_count >= min_sizes:
        score += 10
        feedback.append("Font sizes found (10/10)")
    elif size_count > 0:
        score += 5
        feedback.append("Some font sizes found (5/10)")
    else:
        feedback.append("No font size values (px/rem/em) found (0/10)")
        
    # --- Criterion 7: Substantive Content (10 pts) ---
    if report.get('size_bytes', 0) > 800:
        score += 10
        feedback.append("Report is substantive length (10/10)")
    elif report.get('size_bytes', 0) > 100:
        score += 5
        feedback.append("Report is somewhat short (5/10)")
    else:
        feedback.append("Report is too empty/short (0/10)")

    # 4. Final Verdict
    # Pass threshold: 65 points
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }