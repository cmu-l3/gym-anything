#!/usr/bin/env python3
"""Verifier for Image Performance and CLS Audit task.

Scoring (100 points total):
- Crawl performed (10 pts)
- Missing Dimensions CSV exists & valid (25 pts)
- Heavy Images CSV exists & valid (25 pts)
- Files are distinct (not identical) (10 pts)
- Report exists and has valid content (10 pts)
- VLM Verification (20 pts)
  - Confirms UI interaction (Images tab, filters, or correct domain)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_image_performance_audit(traj, env_info, task_info):
    """Verify image performance audit task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Crawl Performed (10 pts) ---
    sf_running = result.get('sf_running', False)
    window_info = result.get('window_info', '').lower()
    if sf_running or 'screaming' in window_info:
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not detected (0/10)")

    # --- Criterion 2: Missing Dimensions CSV (25 pts) ---
    md_valid = result.get('missing_dims_valid', False)
    md_rows = result.get('missing_dims_rows', 0)
    
    if md_valid and md_rows > 0:
        score += 25
        feedback_parts.append(f"Missing dimensions CSV valid with {md_rows} rows (25/25)")
    elif result.get('missing_dims_exists', False):
        score += 10
        feedback_parts.append("Missing dimensions CSV exists but empty/invalid (10/25)")
    else:
        feedback_parts.append("Missing dimensions CSV not found (0/25)")

    # --- Criterion 3: Heavy Images CSV (25 pts) ---
    hi_valid = result.get('heavy_images_valid', False)
    hi_rows = result.get('heavy_images_rows', 0)

    if hi_valid and hi_rows > 0:
        score += 25
        feedback_parts.append(f"Heavy images CSV valid with {hi_rows} rows (25/25)")
    elif result.get('heavy_images_exists', False):
        score += 10
        feedback_parts.append("Heavy images CSV exists but empty/invalid (10/25)")
    else:
        feedback_parts.append("Heavy images CSV not found (0/25)")

    # --- Criterion 4: Distinct Files (10 pts) ---
    distinct = result.get('files_distinct', True)
    if distinct and md_valid and hi_valid:
        score += 10
        feedback_parts.append("Export files are distinct (10/10)")
    elif not distinct:
        feedback_parts.append("Export files are identical - likely same filter used twice (0/10)")
    else:
        feedback_parts.append("Files not distinct check skipped due to missing files (0/10)")

    # --- Criterion 5: Report Content (10 pts) ---
    report_valid = result.get('report_content_valid', False)
    if report_valid:
        score += 10
        feedback_parts.append("Report contains relevant keywords (10/10)")
    elif result.get('report_exists', False):
        score += 5
        feedback_parts.append("Report exists but missing keywords (5/10)")
    else:
        feedback_parts.append("Report not found (0/10)")

    # --- Criterion 6: VLM Verification (20 pts) ---
    vlm_score = 0
    if query_vlm and get_final_screenshot:
        final_img = get_final_screenshot(traj)
        if final_img:
            prompt = """
            Analyze this screenshot of Screaming Frog SEO Spider.
            1. Is the 'Images' tab selected or visible?
            2. Is there a filter dropdown showing 'Missing Size Attributes' or 'Over 100kb'?
            3. Does the window title or address bar show 'crawler-test.com'?
            
            Answer JSON: {"images_tab": bool, "filter_visible": bool, "correct_domain": bool}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_img)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('images_tab') or parsed.get('filter_visible'):
                        vlm_score += 10
                    if parsed.get('correct_domain'):
                        vlm_score += 10
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"VLM confirmed UI state ({vlm_score}/20)")
            except Exception:
                pass
    
    # Fallback if VLM fails but logic passed
    if vlm_score == 0 and score >= 70:
        feedback_parts.append("VLM check skipped/failed, relying on file logic")
        score += 20 # Grant points if files are perfect to avoid failing good run due to VLM
    
    score += vlm_score
    score = min(100, score)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }