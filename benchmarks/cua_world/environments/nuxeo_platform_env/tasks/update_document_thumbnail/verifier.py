#!/usr/bin/env python3
"""
Verifier for update_document_thumbnail task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_document_thumbnail(traj, env_info, task_info):
    """
    Verifies that the document thumbnail was updated correctly while preserving the main file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    initial_pdf_digest = result.get('initial_pdf_digest', 'init_missing')
    target_thumb_digest = result.get('target_thumbnail_digest', 'target_missing')
    final_pdf_digest = result.get('final_pdf_digest', 'final_missing')
    final_thumb_digest = result.get('final_thumbnail_digest', 'null')

    score = 0
    feedback_parts = []
    passed = False

    # 2. Verify Main Content Preservation (Anti-Gaming)
    # The agent must NOT overwrite the PDF with the image.
    content_preserved = (final_pdf_digest == initial_pdf_digest)
    
    if final_pdf_digest == "null":
        feedback_parts.append("Main document file was deleted.")
    elif final_pdf_digest == target_thumb_digest:
        feedback_parts.append("CRITICAL: You replaced the main document file instead of the thumbnail.")
    elif content_preserved:
        score += 30
        feedback_parts.append("Main PDF content preserved.")
    else:
        feedback_parts.append("Main PDF content was modified unexpectedly.")

    # 3. Verify Thumbnail Update
    thumbnail_updated = (final_thumb_digest == target_thumb_digest)
    
    if thumbnail_updated:
        score += 60
        feedback_parts.append("Thumbnail successfully updated to target image.")
    elif final_thumb_digest == "null":
        feedback_parts.append("No thumbnail found on the document.")
    else:
        feedback_parts.append("Thumbnail changed, but does not match the target image.")

    # 4. Basic State Check
    if result.get('app_running'):
        score += 5
    
    # 5. VLM Verification (Trajectory Analysis)
    # Check if agent accessed the summary/manage views
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a user action in Nuxeo Platform. 
        The goal was to update a document's thumbnail.
        
        Review the screenshots. Did the user:
        1. Navigate to a document view?
        2. Open a menu or tab related to "Summary", "View", or "Manage"?
        3. Access a file upload interface (likely for the thumbnail)?
        
        Answer with JSON: {"navigated": bool, "upload_interface_seen": bool}
        """
        
        vlm_resp = query_vlm(images=frames + [final_shot], prompt=prompt)
        if vlm_resp and vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            if analysis.get('navigated'):
                vlm_score += 5
            if analysis.get('upload_interface_seen'): # Bonus check
                pass 
            feedback_parts.append("Visual workflow verified.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: give points if programmatic checks passed
        if thumbnail_updated: 
            vlm_score += 5

    score += vlm_score

    # Final Pass Logic
    # Must have updated thumbnail AND preserved content
    if thumbnail_updated and content_preserved:
        passed = True
    else:
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }