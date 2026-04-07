#!/usr/bin/env python3
"""Verifier for historical_map_optimization_html task.

Checks that the agent:
1. Created the 4 quadrant images with dimensions ~50% of the original.
2. Created an HTML file containing a <table>.
3. Ensured the table is gapless (cellspacing/cellpadding=0 or CSS).
4. Arranged the images in a 2x2 grid in the correct geographical order.
"""

import json
import os
import tempfile
import re

def verify_historical_map_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/map_optimization_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    task_start = result.get("task_start", 0)
    orig_w = result.get("orig_w", 2560)
    orig_h = result.get("orig_h", 1877)
    
    quadrants = result.get("quadrants", {})
    expected_q = ["map_nw.jpg", "map_ne.jpg", "map_sw.jpg", "map_se.jpg"]
    
    # ---------------------------------------------------------
    # Criterion 1 & 2: Quadrant Files Exist and Properly Cropped
    # ---------------------------------------------------------
    files_exist_count = 0
    proper_crop_count = 0
    
    for q in expected_q:
        q_data = quadrants.get(q, {})
        if q_data.get("exists") and q_data.get("size", 0) > 1000 and q_data.get("mtime", 0) >= task_start:
            files_exist_count += 1
            
            w = q_data.get("width", 0)
            h = q_data.get("height", 0)
            
            # Check if dimensions are roughly 50% (allow 45% to 55% for rounding/1px borders)
            if (0.45 * orig_w) <= w <= (0.55 * orig_w) and (0.45 * orig_h) <= h <= (0.55 * orig_h):
                proper_crop_count += 1

    if files_exist_count == 4:
        score += 10
        feedback.append("All 4 quadrant files exist and were modified.")
    else:
        feedback.append(f"Only {files_exist_count}/4 quadrant files found/modified.")
        
    if proper_crop_count == 4:
        score += 20
        feedback.append(f"All 4 quadrants properly cropped (~{orig_w//2}x{orig_h//2}).")
    elif proper_crop_count > 0:
        score += (proper_crop_count * 5)
        feedback.append(f"Only {proper_crop_count}/4 quadrants properly cropped.")
    else:
        feedback.append("Images were not properly cropped to ~50% dimensions.")

    # ---------------------------------------------------------
    # Criterion 3: HTML File Exists
    # ---------------------------------------------------------
    html_content = result.get("html_content", "")
    if result.get("html_exists") and result.get("html_size", 0) > 50:
        score += 10
        feedback.append("map_viewer.html exists.")
    else:
        feedback.append("map_viewer.html is missing or empty.")
        # If no HTML, we can't test the rest.
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback), 
            "subscores": {"images_cropped": proper_crop_count == 4}
        }

    # ---------------------------------------------------------
    # Criterion 4: HTML Table Exists
    # ---------------------------------------------------------
    html_lower = html_content.lower()
    if "<table" in html_lower:
        score += 10
        feedback.append("HTML <table> element found.")
    else:
        feedback.append("No <table> element found in HTML.")

    # ---------------------------------------------------------
    # Criterion 5: Gapless Layout
    # ---------------------------------------------------------
    # Check for cellspacing="0" cellpadding="0" OR CSS border-collapse/padding:0
    has_cellspacing = 'cellspacing="0"' in html_lower or "cellspacing='0'" in html_lower or "cellspacing=0" in html_lower
    has_cellpadding = 'cellpadding="0"' in html_lower or "cellpadding='0'" in html_lower or "cellpadding=0" in html_lower
    has_css_gapless = "border-collapse" in html_lower or "padding: 0" in html_lower or "padding:0" in html_lower
    
    if (has_cellspacing and has_cellpadding) or has_css_gapless:
        score += 10
        feedback.append("Gapless table attributes/CSS detected.")
    else:
        feedback.append("Table missing gapless attributes (cellspacing/cellpadding=0).")

    # ---------------------------------------------------------
    # Criterion 6, 7 & 8: 2x2 Grid Structure and Image Placement
    # ---------------------------------------------------------
    # Extract rows (<tr>...</tr>)
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', html_lower, re.DOTALL)
    
    if len(rows) >= 2:
        score += 10
        feedback.append("At least 2 table rows (<tr>) found.")
        
        # Check row 1
        row1_imgs = re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', rows[0])
        row1_clean = [os.path.basename(src).strip() for src in row1_imgs]
        if len(row1_clean) >= 2 and "map_nw.jpg" in row1_clean[0] and "map_ne.jpg" in row1_clean[1]:
            score += 15
            feedback.append("Row 1 correctly contains NW and NE maps.")
        else:
            feedback.append(f"Row 1 incorrect: found {row1_clean}.")
            
        # Check row 2
        row2_imgs = re.findall(r'<img[^>]+src=["\']([^"\']+)["\']', rows[1])
        row2_clean = [os.path.basename(src).strip() for src in row2_imgs]
        if len(row2_clean) >= 2 and "map_sw.jpg" in row2_clean[0] and "map_se.jpg" in row2_clean[1]:
            score += 15
            feedback.append("Row 2 correctly contains SW and SE maps.")
        else:
            feedback.append(f"Row 2 incorrect: found {row2_clean}.")
            
    else:
        feedback.append(f"Expected 2 <tr> elements, found {len(rows)}.")

    passed = score >= 70 and proper_crop_count > 0

    if passed:
        feedback.append("SUCCESS: Map optimization gallery complete!")
    else:
        feedback.append(f"FAILED: Score {score} < 70 or missing vital crop steps.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "files_exist": files_exist_count == 4,
            "proper_crop": proper_crop_count == 4,
            "html_exists": result.get("html_exists", False)
        }
    }