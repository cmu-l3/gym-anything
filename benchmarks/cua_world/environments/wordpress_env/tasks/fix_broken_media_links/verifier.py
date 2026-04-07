#!/usr/bin/env python3
"""
Verifier for fix_broken_media_links task.

Scoring system (100 points total):
  - Images Uploaded (DB presence) (15 pts)
  - Physical Files Exist in /wp-content/uploads/ (15 pts)
  - Alt Text exactly matches expected strings (10 pts each = 30 pts)
  - Legacy URLs strictly removed from post content (15 pts)
  - New URLs (from Media Library) successfully applied to post (25 pts)

VLM Trajectory Checks:
  - Verify that the agent actually interacted with Media Library and Post Editor.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

TRAJECTORY_PROMPT = """You are analyzing an agent's trajectory performing a site maintenance task in WordPress.
The agent needs to upload 3 architectural images to the Media Library, set their Alternative Text, and then fix a broken post by replacing old legacy image blocks with the newly uploaded ones.

Assess:
1. WORKFLOW_COMPLETED: Did the agent successfully navigate to both the Media Library (to upload) AND the Post Editor?
2. MEDIA_INTERACTION: Is there evidence of the agent uploading images and typing/setting Alt Text?
3. POST_EDITED: Is there evidence of the agent editing the post "Exploring Modern Architecture Masterpieces" and swapping image blocks?
4. MEANINGFUL_PROGRESSION: Does the trajectory show a logical progression of completing these goals?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "media_interaction": true/false,
    "post_edited": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_fix_broken_media_links(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_alt_texts = metadata.get('alt_texts', {
        "guggenheim": "Guggenheim Museum Bilbao",
        "bauhaus": "Bauhaus Dessau Building",
        "fallingwater": "Fallingwater House"
    })

    feedback_parts = []
    score = 0
    max_score = 100

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fix_broken_media_links_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh failed to run."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON exported: {str(e)}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}

    attachments = result.get('attachments', {})
    post_data = result.get('target_post', {})
    physical_files = result.get('physical_files_count', 0)

    # 1. Images Uploaded to DB (15 pts: 5 per image)
    uploaded_count = 0
    for key in ['guggenheim', 'bauhaus', 'fallingwater']:
        if attachments.get(key, {}).get('found', False):
            uploaded_count += 1
    
    score += (uploaded_count * 5)
    feedback_parts.append(f"Images in DB: {uploaded_count}/3")

    # 2. Physical Files Check (15 pts)
    # Check for actual file creation during task timeframe
    if physical_files >= 3:
        score += 15
        feedback_parts.append("Physical files uploaded successfully")
    elif physical_files > 0:
        score += (physical_files * 5)
        feedback_parts.append(f"Partial physical files found ({physical_files}/3)")
    else:
        feedback_parts.append("No physical files uploaded during task")

    # 3. Alt Text Accuracy (30 pts: 10 per image)
    alt_correct_count = 0
    for key, expected_alt in expected_alt_texts.items():
        actual_alt = attachments.get(key, {}).get('alt_text', '').strip()
        # Case insensitive exact match
        if actual_alt.lower() == expected_alt.lower():
            score += 10
            alt_correct_count += 1
        elif expected_alt.lower() in actual_alt.lower():
            score += 5  # Partial credit if it contains the text but isn't exact
            feedback_parts.append(f"Alt text '{key}' partially correct")
    
    feedback_parts.append(f"Alt texts perfectly correct: {alt_correct_count}/3")

    # 4. Legacy URLs Removed (15 pts)
    legacy_count = post_data.get('legacy_url_count', -1)
    if legacy_count == 0:
        score += 15
        feedback_parts.append("All legacy URLs removed")
    elif legacy_count > 0:
        feedback_parts.append(f"FAIL: {legacy_count} legacy URLs still in post")
    else:
        feedback_parts.append("FAIL: Target post missing or empty")

    # 5. New URLs Applied (25 pts)
    new_uploads_count = post_data.get('new_upload_count', 0)
    # Also verify the image IDs might have been inserted as wp:image blocks without full URL
    post_content = post_data.get('content_excerpt', '')
    
    # Count occurrences of our specific uploaded attachment IDs in the block comments
    ids_found = 0
    for key in ['guggenheim', 'bauhaus', 'fallingwater']:
        att_id = attachments.get(key, {}).get('id', '')
        if att_id and (f'"id":{att_id}' in post_content or f'wp-image-{att_id}' in post_content):
            ids_found += 1
            
    # Success if the post contains at least 3 local upload URLs OR 3 correct attachment IDs
    if new_uploads_count >= 3 or ids_found >= 3:
        score += 25
        feedback_parts.append("New media links successfully inserted")
    elif new_uploads_count > 0 or ids_found > 0:
        score += 10
        feedback_parts.append("Partial insertion of new media links")
    else:
        feedback_parts.append("No new media links found in post")

    # VLM Trajectory Verification (Optional/Hybrid)
    vlm_feedback = "VLM not executed"
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=6)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get('post_edited') and vlm_res.get('media_interaction'):
                vlm_feedback = "VLM confirmed media and post edits"
            else:
                vlm_feedback = "VLM did not confirm full workflow"
                # Penalize slightly if the VLM confidently sees no work being done
                if vlm_res.get('confidence') == 'high' and not vlm_res.get('meaningful_progression'):
                    score -= 10
                    feedback_parts.append("VLM penalty: Work not observed in UI")

    feedback_parts.append(f"[{vlm_feedback}]")

    # Threshold: Must have removed legacy URLs, inserted new URLs, and uploaded images.
    passed = score >= 80 and legacy_count == 0 and (new_uploads_count >= 3 or ids_found >= 3)

    return {
        "passed": bool(passed),
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }