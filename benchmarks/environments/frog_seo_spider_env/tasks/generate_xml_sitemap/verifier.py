#!/usr/bin/env python3
"""Verifier for generate_xml_sitemap task.

Scoring (100 points total):
- Sitemap file exists and created during task (20 pts)
- Sitemap is valid XML with sitemap namespace (15 pts)
- Sitemap contains ≥20 URLs (15 pts)
- Sitemap URLs match target domain (10 pts)
- Summary report exists and created during task (10 pts)
- Report has meaningful content (domain, number) (10 pts)
- Report contains date (5 pts)
- VLM: Verified workflow (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_generate_xml_sitemap(traj, env_info, task_info):
    """Verify sitemap generation task completion."""
    copy_from_env = env_info.get('copy_from_env')
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

    # --- Sitemap Verification (60 pts) ---
    
    # 1. Existence and timing (20 pts)
    sitemap_exists = result.get('sitemap_exists', False)
    sitemap_fresh = result.get('sitemap_created_after_start', False)
    
    if sitemap_exists and sitemap_fresh:
        score += 20
        feedback_parts.append("Sitemap created (20/20)")
    elif sitemap_exists:
        feedback_parts.append("Sitemap exists but old timestamp (0/20)")
    else:
        feedback_parts.append("No sitemap file found (0/20)")

    # 2. XML Validity (15 pts)
    valid_xml = result.get('sitemap_valid_xml', False)
    has_ns = result.get('sitemap_has_namespace', False)
    
    if valid_xml and has_ns:
        score += 15
        feedback_parts.append("Valid XML sitemap (15/15)")
    elif valid_xml:
        score += 10
        feedback_parts.append("Valid XML but missing namespace (10/15)")
    else:
        feedback_parts.append("Invalid or unparseable XML (0/15)")

    # 3. Content: URL Count (15 pts)
    url_count = result.get('sitemap_url_count', 0)
    expected_min = task_info.get('metadata', {}).get('expected_min_urls', 20)
    
    if url_count >= expected_min:
        score += 15
        feedback_parts.append(f"Contains {url_count} URLs (15/15)")
    elif url_count > 0:
        score += 5
        feedback_parts.append(f"Contains {url_count} URLs, expected {expected_min} (5/15)")
    else:
        feedback_parts.append("No URLs found in sitemap (0/15)")

    # 4. Content: Domain (10 pts)
    has_domain = result.get('sitemap_has_target_domain', False)
    if has_domain:
        score += 10
        feedback_parts.append("Target domain verified (10/10)")
    else:
        feedback_parts.append("Target domain URLs not found (0/10)")

    # --- Report Verification (25 pts) ---
    
    # 5. Existence (10 pts)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_after_start', False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report created (10/10)")
    else:
        feedback_parts.append("No report found (0/10)")

    # 6. Content (10 pts)
    has_num = result.get('report_has_number', False)
    has_dom = result.get('report_has_domain', False)
    length = result.get('report_content_length', 0)
    
    if length > 50 and has_num and has_dom:
        score += 10
        feedback_parts.append("Report content valid (10/10)")
    elif length > 10:
        score += 5
        feedback_parts.append("Report content partial (5/10)")
    else:
        feedback_parts.append("Report empty or missing content (0/10)")

    # 7. Date (5 pts)
    has_date = result.get('report_has_date', False)
    if has_date:
        score += 5
        feedback_parts.append("Date found (5/5)")

    # --- VLM Verification (15 pts) ---
    # Only run if we have a trajectory
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_frames = env_info.get('sample_trajectory_frames')
    
    if query_vlm and get_frames:
        frames = get_frames(traj, n=4)
        if frames:
            prompt = """Analyze these screenshots of a user operating Screaming Frog SEO Spider.
            
            Look for this workflow:
            1. User entering a URL (books.toscrape.com)
            2. Crawl progress (progress bars, URLs appearing)
            3. User accessing menus like 'Sitemaps > XML Sitemap'
            4. Export/Save dialog
            
            Does the user appear to have performed a crawl and generated a sitemap?
            Answer YES or NO, and provide confidence (0-100)."""
            
            try:
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res.get('success'):
                    resp = vlm_res.get('response', '').lower()
                    if 'yes' in resp:
                        vlm_score = 15
                        feedback_parts.append("VLM confirms workflow (15/15)")
                    else:
                        feedback_parts.append("VLM did not confirm workflow (0/15)")
            except Exception:
                feedback_parts.append("VLM check failed (0/15)")
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 60 and sitemap_exists and sitemap_fresh and valid_xml

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }