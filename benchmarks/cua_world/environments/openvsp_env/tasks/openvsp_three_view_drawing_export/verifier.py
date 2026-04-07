#!/usr/bin/env python3
"""
Verifier for openvsp_three_view_drawing_export task.

Multi-Criteria Verification:
1. File Existence & Timestamps (45 pts, 15 per file):
   - top, front, and side SVG files must exist.
   - Files must contain valid <svg> indicators.
   - Files must have been created during the task (Anti-gaming).
2. Content Uniqueness (25 pts):
   - The SHA-256 hashes of the three files must all be distinct.
   - This proves the agent actually changed the camera viewpoint between exports.
3. VLM Trajectory Verification (30 pts):
   - Verifies the agent actively navigated the GUI and changed views.

Pass threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _is_valid_svg(snippet: str, size: int) -> bool:
    """Checks if the snippet appears to be a valid SVG file."""
    if size < 50:
        return False
    snippet_lower = snippet.lower()
    return "<svg" in snippet_lower or "xml" in snippet_lower


def verify_three_view_export(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_three_view_drawing_export_result.json"
    )

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    files_data = data.get("files", {})
    hashes = []

    # 1. Evaluate individual files (45 points total - 15 per file)
    for view in ["top", "front", "side"]:
        info = files_data.get(view, {})
        exists = info.get("exists", False)
        created_during = info.get("created_during_task", False)
        size = info.get("size", 0)
        snippet = info.get("content_snippet", "")
        file_hash = info.get("hash", "")
        
        if not exists:
            feedback_parts.append(f"❌ {view.capitalize()} SVG missing.")
            continue
            
        if not created_during:
            feedback_parts.append(f"❌ {view.capitalize()} SVG existed before task (gaming detected).")
            continue
            
        if _is_valid_svg(snippet, size):
            score += 15
            feedback_parts.append(f"✅ {view.capitalize()} SVG created and valid.")
            if file_hash:
                hashes.append(file_hash)
        else:
            feedback_parts.append(f"❌ {view.capitalize()} SVG exists but content is invalid/empty.")

    # 2. Evaluate Uniqueness (25 points)
    # If the user just exported the same view three times, the hashes will be identical.
    if len(hashes) == 3:
        unique_hashes = set(hashes)
        if len(unique_hashes) == 3:
            score += 25
            feedback_parts.append("✅ All 3 exports are geometrically unique (camera was changed).")
        elif len(unique_hashes) == 2:
            score += 10
            feedback_parts.append("⚠️ Only 2 unique exports found. One view was duplicated.")
        else:
            feedback_parts.append("❌ All exports are identical. Camera view was not changed.")
    else:
        feedback_parts.append("❌ Not enough valid files to verify view uniqueness.")

    # 3. VLM Trajectory Verification (30 points)
    query_vlm = env_info.get("query_vlm")
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample trajectory frames
            frames = sample_trajectory_frames(traj, n=4)
            
            prompt = """You are evaluating an agent performing a CAD operation in OpenVSP.
The goal was to change the 3D viewport camera to different orthographic views (Top, Front, Side) and export them.
Review these frames from the agent's workflow:
1. Does the agent use the OpenVSP GUI (e.g., View menu, or view buttons) to change the camera angles?
2. Does the model clearly change orientation (e.g., from isometric to top-down, to side profile)?
3. Is the 'File -> Export' dialog invoked?

Respond in JSON format:
{
    "changed_views": true/false,
    "used_export_dialog": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}"""
            vlm_result = query_vlm(prompt=prompt, images=frames)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                changed = parsed.get("changed_views", False)
                exported = parsed.get("used_export_dialog", False)
                
                if changed and exported:
                    vlm_score = 30
                    feedback_parts.append("✅ VLM confirmed trajectory shows camera manipulation and export.")
                elif exported:
                    vlm_score = 15
                    feedback_parts.append("⚠️ VLM confirmed export, but camera changes weren't clearly observed.")
                else:
                    feedback_parts.append("❌ VLM could not confirm the required GUI interactions.")
            else:
                feedback_parts.append("⚠️ VLM query failed, skipping visual verification.")
                # Give partial credit if VLM fails but files are perfect
                if score == 70: 
                    vlm_score = 20
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            if score == 70:
                vlm_score = 20
    else:
        # If VLM unavailable but files match criteria, grant partial fallback points
        if score == 70:
            vlm_score = 20
            feedback_parts.append("⚠️ VLM unavailable, awarding fallback points for perfect programmatic score.")
            
    score += vlm_score

    # Final Pass/Fail determination
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }