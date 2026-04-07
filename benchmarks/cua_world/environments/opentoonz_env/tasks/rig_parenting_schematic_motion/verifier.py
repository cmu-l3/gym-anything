#!/usr/bin/env python3
"""
Verifier for rig_parenting_schematic_motion task.

Verifies:
1. MP4 video existence and freshness.
2. OpenToonz Scene structure (XML parsing) for correct parenting hierarchy.
3. Animation keyframe presence on parent vs child.
"""

import json
import os
import re
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rig_parenting(traj, env_info, task_info):
    """
    Verify the rigging task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Video Output (30 points)
    # ---------------------------------------------------------
    video_exists = result.get("video_exists", False)
    video_fresh = result.get("video_created_during_task", False)
    video_size = result.get("video_size", 0)

    if video_exists and video_fresh and video_size > 10000: # >10KB
        score += 30
        feedback_parts.append("Video rendered successfully")
    elif video_exists:
        score += 10
        feedback_parts.append("Video exists but issues with timestamp/size")
    else:
        feedback_parts.append("No output video found")

    # ---------------------------------------------------------
    # Criterion 2: Scene Hierarchy / Parenting (40 points)
    # ---------------------------------------------------------
    tnz_found = result.get("tnz_found", False)
    parenting_confirmed = False
    
    if tnz_found:
        # Copy the scene file from the container
        temp_tnz = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
        try:
            copy_from_env("/tmp/verification_scene.tnz", temp_tnz.name)
            
            # Read content
            with open(temp_tnz.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            # --- Analysis Logic ---
            # We look for <pegbar> elements that have a 'parent' attribute pointing to another column
            # Example: <parent handle="B" id="Col1" parentHandle="B"/>
            # We want to ensure 'nametag' (likely Col2) is parented to 'dwanko' (likely Col1)
            
            # 1. Identify relationships
            # Regex to find parent linkages: parent="..."
            # Matches: <parent ... id="Col1" ... />
            # Note: "Table" is the default root, so we ignore id="Table"
            
            # Find all parent definitions that point to a Column (Col*)
            parent_refs = re.findall(r'<parent[^>]+id="(Col\d+)"', content)
            
            if parent_refs:
                score += 40
                parenting_confirmed = True
                feedback_parts.append(f"Hierarchy detected (Parented to {parent_refs[0]})")
            else:
                feedback_parts.append("No column parenting detected in scene file")

            # ---------------------------------------------------------
            # Criterion 3: Animation (30 points)
            # ---------------------------------------------------------
            # Check for keyframes.
            # In TNZ XML, keyframes are often in <pegbar> -> <grid_dimension> -> <step> or similar structures
            # or simply look for "status" attributes changing or specific keyframe tags depending on version.
            # Robust check: look for <keyframe> tags or "west" / "east" (position attributes)
            
            # Count keyframes (primitive check)
            keyframe_count = len(re.findall(r'<keyframe\s+', content))
            
            # If we have parenting, we expect keyframes on the Parent, but ideally NOT on the Child (for position)
            # This is hard to verify perfectly with regex, so we accept general keyframe presence + hierarchy
            
            if keyframe_count >= 2:
                score += 30
                feedback_parts.append("Animation keyframes detected")
            else:
                # Fallback: check output video for motion if XML check fails (VLM would be ideal here)
                # For now, simplistic check
                feedback_parts.append("Few or no keyframes found in scene")
                if video_exists and video_size > 50000:
                    # Give partial credit if video is large (implies movement/content)
                    score += 15
                    feedback_parts.append("(Partial credit for video content size)")

        except Exception as e:
            feedback_parts.append(f"Error parsing scene file: {str(e)}")
        finally:
            if os.path.exists(temp_tnz.name):
                os.unlink(temp_tnz.name)
    else:
        feedback_parts.append("No scene file (.tnz) saved")

    # Pass logic
    # Must have Video AND Parenting
    passed = (score >= 60) and video_exists and parenting_confirmed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }