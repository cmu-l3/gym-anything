#!/usr/bin/env python3
"""
Verifier for Customize Transactional Email task in WooCommerce.

Verification Strategy (Hybrid):

Programmatic checks (70 points):
  1. Settings were modified from initial defaults (10 pts)
  2. Subject line matches exactly (20 pts)
  3. Heading matches exactly (20 pts)
  4. Additional content contains required text (20 pts)

VLM checks (30 points):
  5. Process verification (15 pts): Trajectory shows navigation to Email settings > Completed order
  6. Final state verification (15 pts): Screenshot shows the updated fields or saved state

Pass threshold: 60 points AND subject/heading correct
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent customizing a WooCommerce email template.

The images are sampled chronologically.

For success, the agent should:
1. Start at Dashboard
2. Navigate to WooCommerce > Settings
3. Click the "Emails" tab
4. Select "Completed order" (or click Manage)
5. Fill in Subject, Heading, and Additional Content fields
6. Save changes

Assess:
1. SETTINGS_ACCESSED: Did the agent reach the WooCommerce Settings > Emails section?
2. SPECIFIC_EMAIL_OPENED: Did they open the "Completed order" email settings?
3. EDITING_OBSERVED: Are there frames showing text being entered into email fields?

Respond in JSON format:
{
    "settings_accessed": true/false,
    "specific_email_opened": true/false,
    "editing_observed": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce task.

This is a desktop screenshot showing the WordPress admin interface.

Assess:
1. ADMIN_VISIBLE: Is the interface visible?
2. EMAIL_SETTINGS_VISIBLE: Are we on an Email settings page?
3. CONTENT_MATCH: Can you see "Your package has arrived" or "Hooray" in the fields?
4. SUCCESS_MESSAGE: Is there a "Settings saved" message?

Respond in JSON format:
{
    "admin_visible": true/false,
    "email_settings_visible": true/false,
    "content_match": true/false,
    "success_message": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_customize_transactional_email(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_subject = metadata.get('expected_subject', '')
    expected_heading = metadata.get('expected_heading', '')
    expected_content_line1 = metadata.get('expected_content_line1', '')
    expected_content_line2 = metadata.get('expected_content_line2', '')

    feedback_parts = []
    score = 0
    
    # 1. Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    current_settings = result.get('current_settings', {})
    initial_settings = result.get('initial_settings', {})
    
    # 2. Programmatic Verification (70 pts)
    
    # Check if settings changed (10 pts)
    if current_settings != initial_settings:
        score += 10
        feedback_parts.append("Settings modified")
    else:
        feedback_parts.append("No changes detected")
    
    # Check Subject (20 pts)
    actual_subject = current_settings.get('subject', '')
    if actual_subject == expected_subject:
        score += 20
        feedback_parts.append("Subject correct")
    elif expected_subject in actual_subject:
        score += 10 # Partial credit
        feedback_parts.append("Subject partially correct")
    else:
        feedback_parts.append(f"Subject incorrect ('{actual_subject}')")

    # Check Heading (20 pts)
    actual_heading = current_settings.get('heading', '')
    if actual_heading == expected_heading:
        score += 20
        feedback_parts.append("Heading correct")
    elif expected_heading in actual_heading:
        score += 10
        feedback_parts.append("Heading partially correct")
    else:
        feedback_parts.append(f"Heading incorrect ('{actual_heading}')")
        
    # Check Content (20 pts)
    actual_content = current_settings.get('additional_content', '')
    # Normalize newlines for comparison
    actual_content_norm = actual_content.replace('\r\n', '\n').strip()
    
    if expected_content_line1 in actual_content_norm and expected_content_line2 in actual_content_norm:
        score += 20
        feedback_parts.append("Content correct")
    elif expected_content_line1 in actual_content_norm:
        score += 10
        feedback_parts.append("Content partially correct (missing line 2)")
    elif expected_content_line2 in actual_content_norm:
        score += 10
        feedback_parts.append("Content partially correct (missing line 1)")
    else:
        feedback_parts.append("Content incorrect")

    # 3. VLM Verification (30 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Trajectory check (15 pts)
        frames = sample_trajectory_frames(traj, n=5)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        
        if traj_res:
            traj_score = 0
            if traj_res.get('settings_accessed'): traj_score += 5
            if traj_res.get('specific_email_opened'): traj_score += 5
            if traj_res.get('editing_observed'): traj_score += 5
            
            score += traj_score
            if traj_score > 0:
                feedback_parts.append(f"VLM trajectory: {traj_score}/15 pts")
        
        # Final state check (15 pts)
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        
        if final_res:
            final_score = 0
            if final_res.get('email_settings_visible'): final_score += 5
            if final_res.get('content_match'): final_score += 5
            if final_res.get('success_message'): final_score += 5
            
            score += final_score
            if final_score > 0:
                feedback_parts.append(f"VLM final state: {final_score}/15 pts")
    else:
        # Gracefully handle missing VLM by scaling up programmatic score if it's high
        if score >= 60:
            score = int(score * (100/70))
            feedback_parts.append("VLM unavailable, scaled score")

    # 4. Final Assessment
    # Must have at least Subject or Heading correct to pass
    critical_success = (actual_subject == expected_subject) or (actual_heading == expected_heading)
    passed = (score >= 60) and critical_success
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }