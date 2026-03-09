#!/usr/bin/env python3
"""
Verifier for attach_web_link_to_case task.

Verification strategy:
1. Read exported JSON from VM via copy_from_env.
2. Verify that:
   - "Gideon v. Wainwright" was found.
   - It has a child attachment.
   - Attachment linkMode is 3 (URI).
   - URL matches Oyez (https://www.oyez.org/cases/1962/155).
   - Title matches "Oyez Transcript".
3. Verify via VLM that the agent performed the UI interaction (trajectory check).

Scoring (100 points):
- Attachment created as child of Gideon: 30 pts
- Link Mode is URI (3): 30 pts
- Correct URL: 30 pts
- Correct Title: 10 pts

Pass threshold: 90 points (Small typos in title allowed, but URL and Type must be exact).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

# Import VLM utils provided by framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attach_web_link(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the web link was correctly attached."""
    
    # 1. Retrieve Data from Container
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    # 2. Programmatic Verification
    score = 0
    feedback = []
    
    target_case_found = result.get("target_case_found", False)
    attachment_found = result.get("attachment_found", False)
    link_mode = str(result.get("link_mode", ""))
    url = result.get("attachment_url", "").strip()
    title = result.get("attachment_title", "").strip()
    
    expected_url = task_info.get("metadata", {}).get("expected_url", "https://www.oyez.org/cases/1962/155")
    expected_title = task_info.get("metadata", {}).get("expected_title", "Oyez Transcript")

    if not target_case_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target case 'Gideon v. Wainwright' not found in library. Did you delete it?",
            "details": result
        }

    # Criterion 1: Attachment Created (30 pts)
    if attachment_found:
        score += 30
        feedback.append("Attachment created on 'Gideon v. Wainwright' (+30)")
    else:
        feedback.append("No attachment found on 'Gideon v. Wainwright'. Use 'Add Attachment > Attach Link to URI'")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback), "details": result}

    # Criterion 2: Link Mode is URI (30 pts)
    # linkMode 3 = Linked URI/URL
    if link_mode == "3":
        score += 30
        feedback.append("Attachment type is 'Linked URI' (+30)")
    else:
        feedback.append(f"Incorrect attachment type (LinkMode: {link_mode}). Expected 'Attach Link to URI' (Mode 3)")

    # Criterion 3: Correct URL (30 pts)
    # Normalize URLs for comparison (remove trailing slashes)
    norm_url = url.rstrip('/')
    norm_expected = expected_url.rstrip('/')
    if norm_url == norm_expected:
        score += 30
        feedback.append("URL matches exactly (+30)")
    elif "oyez.org" in norm_url and "1962" in norm_url:
        score += 15
        feedback.append(f"URL is close but not exact (+15). Got: {url}")
    else:
        feedback.append(f"URL incorrect. Expected: {expected_url}, Got: {url}")

    # Criterion 4: Correct Title (10 pts)
    if title.lower() == expected_title.lower():
        score += 10
        feedback.append("Title matches (+10)")
    elif expected_title.lower() in title.lower():
        score += 5
        feedback.append(f"Title contains expected text (+5). Got: {title}")
    else:
        feedback.append(f"Title incorrect. Expected: {expected_title}, Got: {title}")

    # 3. VLM Trajectory Verification (Optional but good for anti-gaming context)
    # We only check this if the programmatic check is borderline or for additional confidence
    # Here we perform it to comply with "USE TRAJECTORY FRAMES" requirement.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Review these screenshots of a user interacting with Juris-M (a Zotero fork). "
            "Does the user open a dialog box to 'Attach Link to URI' or enter a URL starting with 'https://www.oyez.org'? "
            "Answer yes or no."
        )
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if "yes" in vlm_response.lower():
                feedback.append("VLM confirms UI interaction.")
            else:
                logger.info(f"VLM did not detect interaction: {vlm_response}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result,
    }