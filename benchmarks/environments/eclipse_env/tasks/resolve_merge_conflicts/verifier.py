#!/usr/bin/env python3
"""Verifier for resolve_merge_conflicts task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_merge_conflicts(traj, env_info, task_info):
    """
    Verify that git merge conflicts were resolved correctly.
    
    Criteria:
    1. No conflict markers in source files (15 pts)
    2. Maven compilation succeeds (10 pts)
    3. Git merge commit exists (clean status + 2 parents) (10 pts)
    4. Code content preserved from BOTH branches (50 pts total)
    5. VLM verification of workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/chinook-java')

    score = 0
    feedback_parts = []
    
    # Read result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result_final.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Helper to pull file content for deep verification
    def get_file_content(rel_path):
        try:
            tf = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            copy_from_env(f"{project_dir}/{rel_path}", tf.name)
            with open(tf.name, 'r') as f:
                content = f.read()
            os.unlink(tf.name)
            return content
        except Exception:
            return ""

    # 1. Check for Conflict Markers (15 pts)
    marker_count = result.get("conflict_marker_count", 999)
    if marker_count == 0:
        score += 15
        feedback_parts.append("No conflict markers found")
    else:
        feedback_parts.append(f"Found {marker_count} unresolved conflict markers")

    # 2. Check Compilation (10 pts)
    if result.get("compile_success", False):
        score += 10
        feedback_parts.append("Maven compilation succeeded")
    else:
        feedback_parts.append("Maven compilation failed")

    # 3. Check Git State (10 pts)
    is_clean = result.get("git_clean", False)
    parents = result.get("git_merge_commit_parents", 0)
    
    if is_clean and parents == 2:
        score += 10
        feedback_parts.append("Git merge committed successfully")
    elif parents != 2:
        feedback_parts.append(f"Git commit does not look like a merge (parents: {parents})")
    elif not is_clean:
        feedback_parts.append("Working tree not clean (changes not committed)")

    # 4. Check Content Preservation (50 pts)
    # We verify this by reading the actual files to be sure, falling back to JSON if read fails
    
    # Track.java Checks (20 pts)
    track_content = get_file_content("src/main/java/com/chinook/model/Track.java")
    if "getStreamingQuality" in track_content and "StreamingQuality" in track_content:
        score += 10
        feedback_parts.append("Track.java: Main branch changes preserved")
    else:
        feedback_parts.append("Track.java: Missing 'getStreamingQuality' (Main branch)")

    if "toCsvRow" in track_content and 'albumName' in track_content: # simplistic check for albumName usage
        score += 10
        feedback_parts.append("Track.java: Feature branch changes preserved")
    else:
        feedback_parts.append("Track.java: Missing 'toCsvRow' (Feature branch)")

    # PlaylistService.java Checks (20 pts)
    playlist_content = get_file_content("src/main/java/com/chinook/service/PlaylistService.java")
    if "getPlaylistDuration" in playlist_content and "java.time.Duration" in playlist_content:
        score += 10
        feedback_parts.append("PlaylistService.java: Main branch changes preserved")
    else:
        feedback_parts.append("PlaylistService.java: Missing 'getPlaylistDuration' (Main branch)")

    if "exportToCsv" in playlist_content and "java.io.FileWriter" in playlist_content:
        score += 10
        feedback_parts.append("PlaylistService.java: Feature branch changes preserved")
    else:
        feedback_parts.append("PlaylistService.java: Missing 'exportToCsv' (Feature branch)")

    # pom.xml Checks (10 pts)
    pom_content = get_file_content("pom.xml")
    if "gson" in pom_content and "opencsv" in pom_content:
        score += 10
        feedback_parts.append("pom.xml: Both dependencies preserved")
    else:
        feedback_parts.append("pom.xml: Missing one or both dependencies")

    # 5. VLM Verification (15 pts)
    # Check if the agent actually used Eclipse to do this
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Resolve git merge conflicts in Eclipse IDE",
            checklist_items=[
                "Eclipse IDE window is visible",
                "Editor shows Java code with conflict markers (<<<<<<<) at some point",
                "Agent is seen editing the conflicted files",
                "Package Explorer or Git Staging view is visible"
            ]
        )
        if vlm_result:
            if vlm_result.get("vlm_passed"):
                score += 15
            feedback_parts.append(vlm_result.get("vlm_feedback", ""))
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Pass threshold: 60 pts
    # Critical criteria: No markers + Compile success
    passed = (score >= 60) and (marker_count == 0) and result.get("compile_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }