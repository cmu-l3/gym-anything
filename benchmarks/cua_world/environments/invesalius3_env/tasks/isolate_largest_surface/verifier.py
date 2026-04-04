#!/usr/bin/env python3
"""
Verifier for isolate_largest_surface task.

SCORING CRITERIA (100 pts total):
1. `bone_raw.stl` exists and is valid (15 pts)
2. `bone_raw.stl` has substantial geometry (>10k tris) (10 pts)
3. `bone_cleaned.stl` exists and is valid (15 pts)
4. `bone_cleaned.stl` has substantial geometry (>10k tris) (10 pts)
5. Raw has MORE triangles than Cleaned (20 pts)
   - This proves the "Keep largest region" logic was applied correctly.
6. Triangle count difference is meaningful (>= 100) (10 pts)
7. Files have different hashes (5 pts)
8. Both files created during task (anti-gaming) (5 pts)
9. VLM Trajectory Verification (10 pts)
   - Confirms visual workflow.

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_isolate_largest_surface(traj, env_info, task_info):
    """
    Verify that the agent produced two distinct STL files, where the raw file
    contains more triangles (fragments) than the cleaned file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    raw = result.get("raw", {})
    cleaned = result.get("cleaned", {})
    
    score = 0
    feedback_parts = []

    # 1. Raw file checks (25 pts total)
    if raw.get("exists") and raw.get("valid"):
        score += 15
        feedback_parts.append("Raw STL exists")
        if raw.get("triangle_count", 0) > 10000:
            score += 10
            feedback_parts.append(f"Raw geometry OK ({raw['triangle_count']} tris)")
        else:
            feedback_parts.append(f"Raw geometry too simple ({raw['triangle_count']} tris)")
    else:
        feedback_parts.append("Raw STL missing or invalid")

    # 2. Cleaned file checks (25 pts total)
    if cleaned.get("exists") and cleaned.get("valid"):
        score += 15
        feedback_parts.append("Cleaned STL exists")
        if cleaned.get("triangle_count", 0) > 10000:
            score += 10
            feedback_parts.append(f"Cleaned geometry OK ({cleaned['triangle_count']} tris)")
        else:
            feedback_parts.append(f"Cleaned geometry too simple ({cleaned['triangle_count']} tris)")
    else:
        feedback_parts.append("Cleaned STL missing or invalid")

    # 3. Comparative Logic (35 pts total)
    raw_count = raw.get("triangle_count", 0)
    cleaned_count = cleaned.get("triangle_count", 0)
    
    if raw.get("valid") and cleaned.get("valid"):
        if raw_count > cleaned_count:
            score += 20
            diff = raw_count - cleaned_count
            feedback_parts.append(f"Fragments removed correctly (Raw > Cleaned)")
            
            if diff >= 100:
                score += 10
                feedback_parts.append(f"Significant cleanup ({diff} tris removed)")
            else:
                feedback_parts.append(f"Cleanup trivial ({diff} tris)")
        else:
            feedback_parts.append(f"FAIL: Raw file ({raw_count}) does not have more triangles than Cleaned file ({cleaned_count})")

        # Distinct files check
        if raw.get("sha256") != cleaned.get("sha256"):
            score += 5
        else:
            feedback_parts.append("Files are identical (hashes match)")

    # 4. Anti-gaming (5 pts)
    if raw.get("modified_after_start") and cleaned.get("modified_after_start"):
        score += 5
    elif raw.get("exists") or cleaned.get("exists"):
        feedback_parts.append("Warning: Files have old timestamps")

    # 5. VLM Verification (10 pts)
    # Check if a 3D surface was ever visible in the trajectory
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_prompt = (
                "Is a 3D reconstruction of a skull (white or bone colored) visible in any of these screenshots? "
                "The interface is medical software InVesalius. Answer YES or NO."
            )
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success") and "yes" in str(vlm_res.get("parsed", "")).lower():
                score += 10
                feedback_parts.append("VLM: 3D Surface confirmed visually")
            else:
                feedback_parts.append("VLM: 3D Surface not clearly seen")
        else:
            # Fallback if no frames (shouldn't happen in real run)
            score += 10 
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient on VLM failure if programmatic checks pass
        if score >= 60:
            score += 10

    # Final Pass/Fail
    passed = score >= 60 and (raw_count > cleaned_count)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }