#!/usr/bin/env python3
"""
Verifier for the firefox_wikipedia_citation_capture task.
Evaluates SQLite browser telemetry and files exported from the container.
"""

import json
import os
import tempfile
import logging

# Attempt to import VLM utilities for trajectory validation
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_citation_capture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    task_start = result.get("task_start", 0)

    # 1. History Evidence (10 pts)
    if result.get("history_visited_wiki", False):
        score += 10
        feedback_parts.append("[+10] History shows Wikipedia visit")
    else:
        feedback_parts.append("[+0] No Wikipedia visit in history")

    # 2. Bookmark folder (15 pts)
    folders = result.get("folders", [])
    if "Space History" in folders:
        score += 15
        feedback_parts.append("[+15] Folder 'Space History' created")
    else:
        feedback_parts.append("[+0] Folder 'Space History' NOT found")

    # 3. Bookmark entry (15 pts)
    bookmarks = result.get("bookmarks", [])
    bookmark_found = any(
        bm.startswith("Space History|") and "Apollo_11" in bm
        for bm in bookmarks
    )
    if bookmark_found:
        score += 15
        feedback_parts.append("[+15] Apollo 11 bookmarked in 'Space History'")
    else:
        feedback_parts.append("[+0] Apollo 11 NOT bookmarked in 'Space History'")

    # 4. PDF Checks (20 pts)
    pdf = result.get("pdf", {})
    pdf_exists = pdf.get("exists", False)
    if pdf_exists:
        # Require PDF magic bytes, >100KB (rendered wiki is large), and fresh timestamp
        if pdf.get("is_valid", False) and pdf.get("size", 0) > 100000 and pdf.get("mtime", 0) >= task_start:
            score += 20
            feedback_parts.append("[+20] Valid PDF downloaded and renamed correctly")
        else:
            score += 5
            feedback_parts.append("[+5] PDF exists but invalid, too small, or from before task")
    else:
        feedback_parts.append("[+0] apollo11.pdf NOT found")

    # 5. BibTeX Checks (20 pts)
    bib = result.get("bib", {})
    bib_exists = bib.get("exists", False)
    if bib_exists:
        content = bib.get("content", "")
        # Require BibTeX indicators (@misc, enwiki, Apollo) and fresh timestamp
        if "@misc" in content and ("Apollo" in content or "enwiki" in content) and bib.get("mtime", 0) >= task_start:
            score += 20
            feedback_parts.append("[+20] Valid BibTeX downloaded and renamed correctly")
        else:
            score += 5
            feedback_parts.append("[+5] BibTeX exists but content seems invalid or old")
    else:
        feedback_parts.append("[+0] apollo11.bib NOT found")

    # 6. Browser native download evidence (10 pts)
    if result.get("downloads_handled", False):
        score += 10
        feedback_parts.append("[+10] Browser records confirm native downloads")
    else:
        feedback_parts.append("[+0] No browser download records for Apollo")

    # 7. VLM Trajectory Verification (10 pts)
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        if images:
            vlm_prompt = (
                "You are verifying a web automation task. "
                "Did the user/agent view the Wikipedia page for 'Apollo 11' AND interact with the browser's side-menu or download tools (like 'Download as PDF' or 'Cite this page')? "
                "Respond with 'YES' if there is visual evidence of this workflow in the trajectory images, otherwise 'NO'."
            )
            try:
                vlm_response = query_vlm(images=images, prompt=vlm_prompt)
                if "YES" in vlm_response.get("response", "").upper():
                    score += 10
                    feedback_parts.append("[+10] VLM confirmed trajectory shows Wikipedia interaction")
                else:
                    feedback_parts.append("[+0] VLM did not see Wikipedia interaction in trajectory")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append("[+0] VLM verification error")
        else:
            feedback_parts.append("[+0] No images available for VLM")
    else:
        # Fallback if VLM isn't loaded; grant points implicitly if programmatic states are extremely strong
        if pdf_exists and bib_exists and result.get("history_visited_wiki", False):
            score += 10
            feedback_parts.append("[+10] VLM skipped but programmatic evidence strong")

    # Final logic: MUST have both resulting files outputted correctly to pass the whole task
    key_criteria_met = pdf_exists and bib_exists
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }