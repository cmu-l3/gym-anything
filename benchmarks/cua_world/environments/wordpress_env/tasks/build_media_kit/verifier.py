#!/usr/bin/env python3
"""
Verifier for build_media_kit task.

Verification Strategy:
1. Check that the 3 specific attachments exist in the WP database.
2. Check that the page "Official Media Kit" exists and is published.
3. Parse the page content to verify that it contains the direct links to the uploaded files,
   associated with the exact requested link texts.
4. Verify via VLM that the workflow was completed naturally.
"""

import json
import tempfile
import os
import logging
import base64
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a Media Kit page in WordPress.

For successful task completion, the agent should:
1. Visit the Media Library (Media > Add New) and upload files.
2. Navigate to Pages > Add New and create a page.
3. Enter content and insert links to the uploaded files.
4. Click Publish.

Assess:
1. UPLOADS_VISIBLE: Do any frames show the Media Library being used to upload files?
2. PAGE_EDITOR_VISIBLE: Is the WordPress page editor visible with content being added?
3. LINKS_ADDED: Is there evidence of links being configured in the editor?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "uploads_visible": true/false,
    "page_editor_visible": true/false,
    "links_added": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress page creation task.

Assess:
1. ADMIN_OR_PAGE_VISIBLE: Is either the WordPress admin interface OR the published front-end page visible?
2. SUCCESS_INDICATORS: Are there success messages (e.g., "Page published") or is the final page rendered with the links?
3. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_or_page_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def _check_link(content, guid, expected_text):
    """
    Checks if the specific link exists in the HTML content pointing to the GUID.
    Returns boolean indicating if a match was found.
    """
    if not guid:
        return False
        
    # Extract the filename part to allow for absolute vs relative path matching
    filename = guid.split('/')[-1]
    
    # 1. Standard anchor tag pattern: <a href="...filename...">...expected_text...</a>
    # Allows for nested tags like <strong> inside the <a>
    pattern1 = re.compile(
        rf'<a[^>]*href=["\'][^"\']*?{re.escape(filename)}["\'][^>]*>(?:<[^>]+>)*\s*{re.escape(expected_text)}\s*(?:</[^>]+>)*</a>',
        re.IGNORECASE | re.DOTALL
    )
    if pattern1.search(content):
        return True
        
    # 2. Relaxed anchor tag pattern: expected_text is anywhere inside the <a>
    pattern2 = re.compile(
        rf'<a[^>]*href=["\'][^"\']*?{re.escape(filename)}["\'][^>]*>.*?{re.escape(expected_text)}.*?</a>',
        re.IGNORECASE | re.DOTALL
    )
    if pattern2.search(content):
        return True
        
    # 3. WordPress File Block pattern: link text is defined inside HTML comments or the button
    pattern3 = re.compile(
        rf'<!-- wp:file {{.*?href["\']\s*:\s*["\'][^"\']*?{re.escape(filename)}.*?-->.*?{re.escape(expected_text)}.*?<!-- /wp:file -->',
        re.IGNORECASE | re.DOTALL
    )
    if pattern3.search(content):
        return True
        
    return False

def verify_build_media_kit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/build_media_kit_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to load exported result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported JSON: {e}"}

    # 1. Verify File Uploads (15 pts)
    pdf_guid = result.get('pdf_guid', '')
    zip_guid = result.get('zip_guid', '')
    jpg_guid = result.get('jpg_guid', '')
    
    files_uploaded = 0
    if pdf_guid: files_uploaded += 1
    if zip_guid: files_uploaded += 1
    if jpg_guid: files_uploaded += 1
    
    score += (files_uploaded * 5)
    feedback_parts.append(f"{files_uploaded}/3 files uploaded")
    
    # 2. Verify Page Creation (15 pts)
    page_id = result.get('page_id', '')
    page_status = result.get('page_status', '')
    
    page_published = False
    if page_id and page_status == 'publish':
        score += 15
        page_published = True
        feedback_parts.append("Page 'Official Media Kit' published")
    else:
        feedback_parts.append("Page missing or not published")
        
    # 3. Verify Links in Content (45 pts total)
    content_b64 = result.get('page_content_b64', '')
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='replace')
    except Exception as e:
        content = ""
        logger.error(f"Failed to decode base64 content: {e}")
        
    links_correct = 0
    
    if _check_link(content, pdf_guid, "Download Press Release"):
        score += 15
        links_correct += 1
        feedback_parts.append("PDF link valid")
    else:
        feedback_parts.append("PDF link missing/invalid")
        
    if _check_link(content, zip_guid, "Download Brand Assets"):
        score += 15
        links_correct += 1
        feedback_parts.append("ZIP link valid")
    else:
        feedback_parts.append("ZIP link missing/invalid")
        
    if _check_link(content, jpg_guid, "Download CEO Portrait"):
        score += 15
        links_correct += 1
        feedback_parts.append("JPG link valid")
    else:
        feedback_parts.append("JPG link missing/invalid")

    # 4. VLM Checks (25 pts)
    vlm_score = 0
    if "query_vlm" in env_info:
        query_vlm = env_info["query_vlm"]
        
        frames = sample_trajectory_frames(traj, n=5)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        if traj_res and traj_res.get('page_editor_visible', False) and traj_res.get('meaningful_progression', False):
            vlm_score += 15
            feedback_parts.append("VLM workflow confirmed")
            
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        if final_res and final_res.get('success_indicators', False) and final_res.get('admin_or_page_visible', False):
            vlm_score += 10
            feedback_parts.append("VLM final state confirmed")
    else:
        # Give grace points if VLM is unavailable but programmatic passes
        if page_published and links_correct >= 2:
            vlm_score += 25
            feedback_parts.append("VLM bypassed (not available)")
            
    score += vlm_score

    # Calculate final passing status
    passed = score >= 70 and page_published and links_correct >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }