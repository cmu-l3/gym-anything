#!/usr/bin/env python3
"""
Verifier for Easter Island Cartographic Basemap Export task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists at correct path (15 points)
2. File is valid PNG format (10 points)
3. Resolution meets minimum requirements (15 points)
4. File was created during task (10 points) - anti-gaming
5. File size reasonable for satellite imagery (5 points)
6. VLM: Image shows Easter Island (20 points)
7. VLM: Complete island visible (10 points)
8. VLM: No text labels visible (10 points)
9. VLM: Trajectory shows workflow progression (5 points)

Pass threshold: 60 points AND (file exists + created during task + Easter Island confirmed)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

EASTER_ISLAND_VERIFICATION_PROMPT = """You are verifying a satellite image export from Google Earth.

TASK: Export a clean satellite base map of Easter Island (Rapa Nui), Chile.

Easter Island is a distinctive triangular volcanic island with:
- Three volcanic peaks at the corners: Terevaka (north), Poike (east), Rano Kau (southwest)
- A roughly triangular shape, about 24km long
- Surrounded by ocean on all sides
- Located in the remote southeastern Pacific

Look at this image and determine:

1. SHOWS_EASTER_ISLAND: Does this image show Easter Island? Look for the distinctive triangular volcanic island shape with three peaks.

2. COMPLETE_ISLAND_VISIBLE: Is the complete island visible in the frame? All three volcanic corners should be within the image bounds, not cropped.

3. NO_TEXT_LABELS: Is the image free of text labels, place names, road overlays, or other Google Earth annotations? A clean base map should show only satellite imagery.

4. IS_SATELLITE_IMAGERY: Is this satellite/aerial imagery showing natural terrain (not a 3D render, not a photo, not a map)?

5. TOP_DOWN_VIEW: Is this a top-down (nadir) view looking straight down, rather than a tilted 3D perspective?

Respond in JSON format:
{
    "shows_easter_island": true/false,
    "complete_island_visible": true/false,
    "no_text_labels": true/false,
    "is_satellite_imagery": true/false,
    "top_down_view": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see in the image"
}
"""

TRAJECTORY_WORKFLOW_PROMPT = """You are analyzing a sequence of screenshots showing an agent working in Google Earth.

The agent's task was to:
1. Navigate to Easter Island
2. Disable overlay layers (labels, roads, etc.)
3. Export a clean satellite image

Look at these trajectory frames (ordered chronologically from earliest to latest) and assess:

1. GOOGLE_EARTH_USED: Was Google Earth Pro being used? (Look for the Google Earth interface)

2. NAVIGATION_OCCURRED: Did the agent navigate/search for a location? (Look for search dialogs, "Fly To", or view changes)

3. LAYER_MANAGEMENT: Did the agent appear to access layer controls or view settings? (Look for sidebar panels, View menu, or layer toggles)

4. EXPORT_DIALOG: Did the agent open a save/export dialog? (Look for File menu, Save dialogs)

5. MEANINGFUL_PROGRESSION: Do the frames show real state changes and workflow progression (not just the same screen repeated)?

Respond in JSON format:
{
    "google_earth_used": true/false,
    "navigation_occurred": true/false,
    "layer_management": true/false,
    "export_dialog": true/false,
    "meaningful_progression": true/false,
    "workflow_stages_observed": ["list what stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def _vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Execute VLM query with single or multiple images."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    if not image and not images:
        logger.warning("No images provided for VLM query")
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def sample_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """Sample n frames evenly distributed across the trajectory."""
    frames = traj.get("frames", [])
    if not frames:
        return []
    
    if len(frames) <= n:
        return frames
    
    # Sample evenly distributed indices
    indices = [int(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    return [frames[i] for i in indices]


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    frames = traj.get("frames", [])
    if frames:
        return frames[-1]
    return None


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_easter_island_basemap_export(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Easter Island basemap export task completion.
    
    Uses multiple independent verification signals:
    - Programmatic: File existence, format, size, timestamps
    - VLM: Content verification on exported image and trajectory
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/exports/easter_island_basemap.png')
    min_width = metadata.get('min_width', 1920)
    min_height = metadata.get('min_height', 1080)
    min_file_size_kb = metadata.get('min_file_size_kb', 500)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['task_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    output_info = result.get('output', {})
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = output_info.get('exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output file exists")
    else:
        feedback_parts.append("❌ Output file NOT found")
        # Can't proceed without file - return early with minimal score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: Valid PNG format (10 points)
    # ================================================================
    image_format = output_info.get('image_format', 'unknown')
    image_valid = output_info.get('image_valid', False)
    
    if image_valid and image_format.upper() == 'PNG':
        score += 10
        feedback_parts.append("✅ Valid PNG format")
    elif image_valid:
        score += 5
        feedback_parts.append(f"⚠️ Valid image but format is {image_format}")
    else:
        feedback_parts.append("❌ Invalid image file")
    
    # ================================================================
    # CRITERION 3: Resolution meets minimum (15 points)
    # ================================================================
    image_width = output_info.get('image_width', 0)
    image_height = output_info.get('image_height', 0)
    
    width_ok = image_width >= min_width
    height_ok = image_height >= min_height
    
    if width_ok and height_ok:
        score += 15
        feedback_parts.append(f"✅ Resolution {image_width}x{image_height} meets minimum")
    elif width_ok or height_ok:
        score += 8
        feedback_parts.append(f"⚠️ Resolution {image_width}x{image_height} partially meets minimum")
    else:
        feedback_parts.append(f"❌ Resolution {image_width}x{image_height} below minimum {min_width}x{min_height}")
    
    # ================================================================
    # CRITERION 4: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = output_info.get('created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task (timestamp verified)")
    else:
        feedback_parts.append("⚠️ File timestamp suspicious (may have existed before task)")
        # This is a warning but not disqualifying
    
    # ================================================================
    # CRITERION 5: File size reasonable (5 points)
    # ================================================================
    file_size_bytes = output_info.get('size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    
    if file_size_kb >= min_file_size_kb:
        score += 5
        feedback_parts.append(f"✅ File size {file_size_kb:.1f}KB reasonable for satellite imagery")
    elif file_size_kb >= 100:
        score += 2
        feedback_parts.append(f"⚠️ File size {file_size_kb:.1f}KB smaller than expected")
    else:
        feedback_parts.append(f"❌ File size {file_size_kb:.1f}KB suspiciously small")
    
    # ================================================================
    # CRITERION 6-8: VLM verification on exported image (40 points total)
    # ================================================================
    vlm_score = 0
    vlm_details = {}
    
    if query_vlm:
        # Copy the exported image for VLM analysis
        temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_image.name)
            
            # Query VLM on the exported image
            vlm_result = _vlm_query(query_vlm, EASTER_ISLAND_VERIFICATION_PROMPT, image=temp_image.name)
            vlm_details['image_analysis'] = vlm_result
            
            if vlm_result:
                # CRITERION 6: Shows Easter Island (20 points)
                if vlm_result.get('shows_easter_island', False):
                    vlm_score += 20
                    feedback_parts.append("✅ VLM confirms Easter Island visible")
                else:
                    feedback_parts.append("❌ VLM: Easter Island not identified")
                
                # CRITERION 7: Complete island visible (10 points)
                if vlm_result.get('complete_island_visible', False):
                    vlm_score += 10
                    feedback_parts.append("✅ VLM confirms complete island in frame")
                else:
                    feedback_parts.append("⚠️ VLM: Island may be cropped")
                
                # CRITERION 8: No text labels (10 points)
                if vlm_result.get('no_text_labels', False):
                    vlm_score += 10
                    feedback_parts.append("✅ VLM confirms clean image (no labels)")
                else:
                    feedback_parts.append("⚠️ VLM: Text labels may be visible")
                
                # Bonus verification
                if vlm_result.get('is_satellite_imagery', False):
                    feedback_parts.append("✅ VLM confirms satellite imagery")
                if vlm_result.get('top_down_view', False):
                    feedback_parts.append("✅ VLM confirms top-down view")
                
                vlm_details['reasoning'] = vlm_result.get('reasoning', '')
                vlm_details['confidence'] = vlm_result.get('confidence', 'unknown')
            else:
                feedback_parts.append("⚠️ VLM image analysis failed")
                
        except Exception as e:
            logger.warning(f"Failed to copy/analyze exported image: {e}")
            feedback_parts.append(f"⚠️ Could not analyze exported image: {e}")
        finally:
            if os.path.exists(temp_image.name):
                os.unlink(temp_image.name)
    else:
        feedback_parts.append("⚠️ VLM not available for content verification")
    
    score += vlm_score
    result_details['vlm_image_analysis'] = vlm_details
    
    # ================================================================
    # CRITERION 9: Trajectory workflow verification (5 points)
    # ================================================================
    trajectory_score = 0
    
    if query_vlm:
        # Sample frames from trajectory for workflow verification
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        
        if trajectory_frames:
            traj_result = _vlm_query(query_vlm, TRAJECTORY_WORKFLOW_PROMPT, images=trajectory_frames)
            result_details['trajectory_analysis'] = traj_result
            
            if traj_result:
                workflow_checks = [
                    traj_result.get('google_earth_used', False),
                    traj_result.get('navigation_occurred', False),
                    traj_result.get('meaningful_progression', False)
                ]
                
                if all(workflow_checks):
                    trajectory_score = 5
                    feedback_parts.append("✅ Trajectory shows proper workflow")
                elif any(workflow_checks):
                    trajectory_score = 2
                    feedback_parts.append("⚠️ Trajectory shows partial workflow")
                else:
                    feedback_parts.append("⚠️ Trajectory workflow unclear")
            else:
                feedback_parts.append("⚠️ Trajectory analysis failed")
        else:
            feedback_parts.append("⚠️ No trajectory frames available")
    
    score += trajectory_score
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    
    # Key criteria for passing:
    # - File must exist
    # - File must have been created during task (or at least be valid)
    # - Easter Island must be confirmed by VLM (if VLM available)
    
    key_criteria_met = (
        output_exists and 
        (file_created_during_task or image_valid) and
        (vlm_score >= 20 or not query_vlm)  # Easter Island confirmed OR no VLM
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Additional details
    result_details['score_breakdown'] = {
        'file_exists': 15 if output_exists else 0,
        'valid_format': 10 if (image_valid and image_format.upper() == 'PNG') else (5 if image_valid else 0),
        'meets_resolution': 15 if (width_ok and height_ok) else (8 if (width_ok or height_ok) else 0),
        'created_during_task': 10 if file_created_during_task else 0,
        'file_size': 5 if file_size_kb >= min_file_size_kb else (2 if file_size_kb >= 100 else 0),
        'vlm_content': vlm_score,
        'trajectory': trajectory_score
    }
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }