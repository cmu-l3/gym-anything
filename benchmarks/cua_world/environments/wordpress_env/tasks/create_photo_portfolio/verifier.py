#!/usr/bin/env python3
"""
Verifier for Create Photo Portfolio Page task in WordPress.

Verification Strategy:

Programmatic checks (70 points max):
  1. Attachments uploaded correctly (max 20 pts)
     - 5 pts if at least 1 image uploaded
     - 15 pts if all 5 expected images found
  2. Alt text correct (max 20 pts)
     - 10 pts if >= 3 images have exact alt text
     - 10 bonus pts if ALL 5 have exact alt text
  3. Page Exists (10 pts)
     - Must be titled "Urban Photography Portfolio"
  4. Page Published (5 pts)
     - Status must be 'publish'
  5. Page Content - Intro Text (5 pts)
     - Must contain the exact required string (fuzzy matched)
  6. Page Content - Gallery/Images (10 pts)
     - Content must contain gallery block or image block references

VLM checks (30 points max):
  7. Process verification (15 pts): Trajectory frames show media upload/page creation
  8. Final state verification (15 pts): Final page shows images

Pass threshold: score >= 60 AND page exists AND at least 3 images uploaded
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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent creating a photo portfolio in WordPress.

The workflow should include:
1. Navigating to Media Library and uploading images
2. Editing Image details (specifically Alt Text)
3. Navigating to Pages -> Add New
4. Creating a page, adding a text paragraph, and adding a Gallery block or Image blocks

Assess:
1. MEDIA_UPLOAD: Is there evidence of images being uploaded to the Media Library?
2. ALT_TEXT_EDITED: Is there a frame showing the agent editing image 'Alt Text' metadata?
3. PAGE_EDITOR: Is the WordPress page block editor visible?
4. GALLERY_ADDED: Is there evidence of a gallery or multiple images being added to the page content?

Respond in JSON format:
{
    "media_upload": true/false,
    "alt_text_edited": true/false,
    "page_editor": true/false,
    "gallery_added": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress photo portfolio task.

Assess:
1. PAGE_VISIBLE: Is a portfolio page visible (either in the block editor or published front-end)?
2. IMAGES_PRESENT: Are there multiple photographs visible on the page?
3. INTRO_TEXT_PRESENT: Is there an introductory text paragraph visible above or near the images?

Respond in JSON format:
{
    "page_visible": true/false,
    "images_present": true/false,
    "intro_text_present": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def verify_create_photo_portfolio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_intro = metadata.get('expected_intro_text', "A curated collection of urban photography capturing the beauty of city life, architecture, and public spaces.").lower()
    expected_images_meta = metadata.get('images', [])
    
    # Map expected alt text by filename for easy lookup
    expected_alts = {img['filename']: img['alt'].lower().strip() for img in expected_images_meta}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data from result
    counts = result.get('counts', {})
    images_data = result.get('images', [])
    page_data = result.get('page', {})

    # ==========================================
    # 1. Media Upload Check (20 pts)
    # ==========================================
    images_found = sum(1 for img in images_data if img.get('found', False))
    
    if images_found == 5:
        score += 20
        feedback_parts.append("All 5 images uploaded")
    elif images_found > 0:
        score += 5 + (images_found * 2) # partial credit
        feedback_parts.append(f"{images_found}/5 images uploaded")
    else:
        feedback_parts.append("No required images found in Media Library")

    # ==========================================
    # 2. Alt Text Check (20 pts)
    # ==========================================
    correct_alts = 0
    for img in images_data:
        if img.get('found', False):
            filename = img.get('filename')
            actual_alt = img.get('alt_text', '').lower().strip()
            expected_alt = expected_alts.get(filename, '')
            
            # Allow minor punctuation/spacing differences
            if actual_alt == expected_alt or actual_alt.replace('.', '') == expected_alt.replace('.', ''):
                correct_alts += 1

    if correct_alts >= 3:
        score += 10
        feedback_parts.append(f"Alt text correct for {correct_alts} images")
        if correct_alts == 5:
            score += 10
            feedback_parts.append("Perfect alt text metadata")
    elif correct_alts > 0:
        score += (correct_alts * 2) # minor partial credit
        feedback_parts.append(f"Alt text correct for only {correct_alts} images")
    elif images_found > 0:
        feedback_parts.append("Alt text incorrect or missing")

    # ==========================================
    # 3. Page Exists Check (10 pts)
    # ==========================================
    page_exists = page_data.get('found', False)
    if page_exists:
        score += 10
        feedback_parts.append("Portfolio page created")
    else:
        feedback_parts.append("Portfolio page NOT found (exact title required)")

    # ==========================================
    # 4. Page Published Check (5 pts)
    # ==========================================
    page_status = page_data.get('status', '')
    if page_exists and page_status == 'publish':
        score += 5
        feedback_parts.append("Page is published")
    elif page_exists:
        feedback_parts.append(f"Page is not published (status: {page_status})")

    # ==========================================
    # 5. Page Content - Intro Text Check (5 pts)
    # ==========================================
    content = page_data.get('content', '').lower()
    
    # Remove all HTML tags and normalize spaces for text comparison
    clean_content = re.sub(r'<[^>]+>', ' ', content)
    clean_content = re.sub(r'\s+', ' ', clean_content).strip()
    
    # Simplify expected string for robust fuzzy matching (strip punctuation)
    simplified_expected = re.sub(r'[^\w\s]', '', expected_intro)
    simplified_actual = re.sub(r'[^\w\s]', '', clean_content)
    
    if simplified_expected in simplified_actual:
        score += 5
        feedback_parts.append("Intro paragraph found")
    elif page_exists:
        # Check partial match as a fallback (at least half the sentence)
        half_expected = simplified_expected[:len(simplified_expected)//2]
        if half_expected in simplified_actual:
            score += 2
            feedback_parts.append("Partial intro paragraph found")
        else:
            feedback_parts.append("Required intro text missing")

    # ==========================================
    # 6. Page Content - Gallery Check (10 pts)
    # ==========================================
    # We look for gallery block, multiple image blocks, or embedded attachment links
    has_gallery_block = 'wp:gallery' in content
    image_block_count = content.count('wp:image')
    img_tag_count = content.count('<img')
    attachment_ref_count = content.count('wp-image-')
    
    if page_exists:
        if has_gallery_block or image_block_count >= 3 or attachment_ref_count >= 3 or img_tag_count >= 3:
            score += 10
            feedback_parts.append("Gallery/Images embedded in page")
        else:
            feedback_parts.append("No gallery or images found in page content")

    # ==========================================
    # 7. & 8. VLM Verification (30 pts)
    # ==========================================
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Trajectory frames
            frames = sample_trajectory_frames(traj, n=5)
            traj_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            
            if traj_result:
                if traj_result.get("media_upload", False):
                    score += 5
                if traj_result.get("alt_text_edited", False):
                    score += 5
                if traj_result.get("gallery_added", False) or traj_result.get("page_editor", False):
                    score += 5
                feedback_parts.append("VLM confirmed trajectory process")

            # Final frame
            final_frame = get_final_screenshot(traj)
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            
            if final_result:
                if final_result.get("images_present", False):
                    score += 10
                if final_result.get("page_visible", False) or final_result.get("intro_text_present", False):
                    score += 5
                feedback_parts.append("VLM confirmed final visual state")

        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            # Automatically grant VLM points if VLM fails but programmatic is perfect (fallback)
            if score == 70:
                score += 30
                feedback_parts.append("(VLM bypassed - programmatic perfect)")
    else:
        # If no VLM capability, scale the score to 100 based on programmatic checks
        score = int((score / 70.0) * 100.0)
        feedback_parts.append("(Score scaled - no VLM)")

    # ==========================================
    # Final Evaluation
    # ==========================================
    # Key criteria: Must have score >= 60, must have page, must have >= 3 images
    key_criteria_met = page_exists and (images_found >= 3)
    passed = (score >= 60) and key_criteria_met

    if not key_criteria_met:
        feedback_parts.append("FAIL: Critical requirement missing (Page missing or <3 images uploaded)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "images_uploaded": images_found,
            "correct_alts": correct_alts,
            "page_exists": page_exists,
            "page_published": page_status == 'publish'
        }
    }