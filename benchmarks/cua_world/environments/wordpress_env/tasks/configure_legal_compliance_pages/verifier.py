#!/usr/bin/env python3
"""
Verifier for Configure Legal Compliance Pages task in WordPress.
"""

import json
import tempfile
import os
import logging
import base64
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_html(raw_html):
    """Remove HTML tags and normalize whitespace for easier string matching."""
    if not raw_html:
        return ""
    cleanr = re.compile('<.*?>')
    cleantext = re.sub(cleanr, ' ', raw_html)
    return ' '.join(cleantext.split())

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing trajectory screenshots of an agent configuring legal pages in WordPress.

The agent should:
1. Navigate to Settings > Privacy OR Pages > Add New.
2. Edit content for "Privacy Policy" and "Terms of Service" pages.
3. Publish both pages.
4. Link the Privacy Policy in Settings > Privacy.

Assess:
1. WORKFLOW_COMPLETED: Did the agent use the WordPress editor to enter content for legal pages?
2. SETTINGS_CONFIGURED: Is there evidence the agent navigated to Settings > Privacy to assign the policy page?
3. MEANINGFUL_PROGRESSION: Do the frames show real, logical workflow progression?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "settings_configured": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_legal_pages(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Retrieve exported result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read exported result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read result JSON"}

    score = 0
    feedback_parts = []
    
    # Extract IDs and raw data
    priv_id = str(result.get('privacy_page_id', '0'))
    tos_id = str(result.get('tos_page_id', '0'))
    privacy_setting = str(result.get('privacy_setting', '0'))
    
    # Decode and clean contents
    priv_raw = base64.b64decode(result.get('privacy_content_b64', '')).decode('utf-8', errors='ignore')
    tos_raw = base64.b64decode(result.get('tos_content_b64', '')).decode('utf-8', errors='ignore')
    
    priv_clean = clean_html(priv_raw).lower()
    tos_clean = clean_html(tos_raw).lower()

    # ---------------------------------------------------------
    # 1. Privacy Policy Checks (40 points)
    # ---------------------------------------------------------
    if priv_id != '0' and priv_id != '':
        score += 10
        feedback_parts.append("Privacy Policy published")
        
        # Check details
        if metadata['company_name'].lower() in priv_clean:
            score += 10
            feedback_parts.append("Privacy contains company name")
        else:
            feedback_parts.append("Privacy missing company name")
            
        if metadata['contact_email'].lower() in priv_clean:
            score += 10
            feedback_parts.append("Privacy contains email")
        else:
            feedback_parts.append("Privacy missing email")
            
        if metadata['address_fragment'].lower() in priv_clean:
            score += 5
            feedback_parts.append("Privacy contains address")
        else:
            feedback_parts.append("Privacy missing address")
    else:
        feedback_parts.append("Privacy Policy NOT published")

    # ---------------------------------------------------------
    # 2. Settings Configuration (15 points)
    # ---------------------------------------------------------
    if privacy_setting != '0' and privacy_setting == priv_id and priv_id != '0':
        score += 15
        feedback_parts.append("Privacy Policy correctly designated in settings")
    else:
        feedback_parts.append("Privacy Policy NOT designated in settings")

    # ---------------------------------------------------------
    # 3. Terms of Service Checks (20 points)
    # ---------------------------------------------------------
    if tos_id != '0' and tos_id != '':
        score += 10
        feedback_parts.append("TOS published")
        
        if metadata['company_name'].lower() in tos_clean:
            score += 5
            feedback_parts.append("TOS contains company name")
        else:
            feedback_parts.append("TOS missing company name")
            
        if metadata['tos_liability'].lower() in tos_clean:
            score += 5
            feedback_parts.append("TOS contains limitation of liability")
        else:
            feedback_parts.append("TOS missing limitation of liability")
            
        if metadata['tos_jurisdiction'].lower() in tos_clean:
            score += 5
            feedback_parts.append("TOS contains jurisdiction")
        else:
            feedback_parts.append("TOS missing jurisdiction")
    else:
        feedback_parts.append("TOS NOT published")

    # ---------------------------------------------------------
    # 4. Content Length Check (5 points)
    # ---------------------------------------------------------
    min_len = metadata.get('min_content_length', 300)
    if len(priv_clean) > min_len and len(tos_clean) > min_len:
        score += 5
        feedback_parts.append("Both pages have substantive content")
    else:
        feedback_parts.append(f"Pages lack substantive content (Need >{min_len} chars)")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Check (20 points)
    # ---------------------------------------------------------
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=6)
        
        vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_result:
            if vlm_result.get("workflow_completed"): vlm_score += 10
            if vlm_result.get("settings_configured"): vlm_score += 5
            if vlm_result.get("meaningful_progression"): vlm_score += 5
            
            score += vlm_score
            feedback_parts.append(f"VLM Score: {vlm_score}/20")
        else:
            score += 20
            feedback_parts.append("VLM failed, granting default VLM points")
    else:
        score += 20
        feedback_parts.append("VLM not available, granting default VLM points")

    # ---------------------------------------------------------
    # Pass Condition Check
    # ---------------------------------------------------------
    # To pass: Total Score >= 70, Privacy Policy exists, and correctly assigned in settings
    is_privacy_assigned = (privacy_setting != '0' and privacy_setting == priv_id and priv_id != '0')
    passed = (score >= 70) and (priv_id != '0') and is_privacy_assigned

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }