#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_import_bg_composite(traj, env_info, task_info):
    """
    Verifies that the OpenToonz scene was rendered with the imported background composite.
    
    Criteria:
    1. Output files exist (>10 frames).
    2. Files created after task start.
    3. Image is fully opaque (background fills frame).
    4. Color analysis confirms Sky (top) and Grass (bottom) gradients.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frames', 10)
    # Color thresholds from metadata or defaults
    # Sky Blue (135, 206, 235) -> Blue channel is high
    # Forest Green (34, 139, 34) -> Green channel is high
    top_blue_thresh = metadata.get('color_check', {}).get('top_region_blue_min', 150)
    bottom_green_thresh = metadata.get('color_check', {}).get('bottom_region_green_min', 80)

    # Read result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Data extraction
    file_count = result.get("file_count", 0)
    total_size = result.get("total_size_bytes", 0)
    analysis = result.get("analysis", {})
    
    valid_timestamps = analysis.get("files_valid_timestamp", False)
    has_transparency = analysis.get("has_transparency", True)
    top_blue = analysis.get("top_blue_avg", 0)
    bottom_green = analysis.get("bottom_green_avg", 0)

    # Criterion 1: File Count (20 pts)
    if file_count >= min_frames:
        score += 20
        feedback.append(f"Rendered {file_count} frames (Pass)")
    elif file_count > 0:
        score += 10
        feedback.append(f"Rendered {file_count} frames (Partial, expected {min_frames})")
    else:
        feedback.append("No output files found")

    # Criterion 2: Anti-gaming Timestamp (20 pts)
    if valid_timestamps and file_count > 0:
        score += 20
        feedback.append("Files created during task session (Pass)")
    elif file_count > 0:
        feedback.append("Files have old timestamps - pre-existing data? (Fail)")

    # Criterion 3: Background Presence via Color Analysis (25 pts)
    # Check if the gradient background is visible
    bg_colors_detected = False
    if top_blue > top_blue_thresh and bottom_green > bottom_green_thresh:
        score += 25
        bg_colors_detected = True
        feedback.append(f"Background colors detected (Top Blue:{int(top_blue)}, Bottom Green:{int(bottom_green)}) (Pass)")
    else:
        feedback.append(f"Background colors missing or wrong (Top Blue:{int(top_blue)}, Bottom Green:{int(bottom_green)})")

    # Criterion 4: Compositing / Opacity (20 pts)
    # If the background is behind the character and fills the screen, there should be NO transparency.
    # If the user only rendered the character (no BG), there will be transparency.
    if not has_transparency and bg_colors_detected:
        score += 20
        feedback.append("Composite is fully opaque (Pass)")
    elif has_transparency:
        feedback.append("Output contains transparency - background likely missing or not filling frame (Fail)")
    else:
        # Opaque but wrong colors?
        score += 5
        feedback.append("Image is opaque but colors don't match background")

    # Criterion 5: File Size Integrity (15 pts)
    if total_size > 200 * 1024: # > 200KB
        score += 15
        feedback.append("Output size indicates valid content (Pass)")
    elif total_size > 0:
        score += 5
        feedback.append("Output size too small (Partial)")

    # Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }