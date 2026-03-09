#!/usr/bin/env python3
"""
Verifier for cartographic_export_scalebar task.

TASK: Navigate to Nile Delta, enable scale legend, export map image.

VERIFICATION STRATEGY (Multi-signal, anti-gaming):

1. FILE EXISTS (15 pts): Output file present at expected path
2. FILE VALID (10 pts): Valid image format with reasonable size
3. FILE TIMESTAMP (10 pts): Created DURING task (anti-gaming)
4. SCALE BAR VISIBLE (25 pts): VLM confirms scale bar in exported image
5. NILE DELTA SHOWN (20 pts): VLM confirms Egyptian delta geography
6. APPROPRIATE ZOOM (10 pts): Delta fits in frame appropriately
7. NORTH ORIENTATION (10 pts): Mediterranean at top (north-up)

Pass Threshold: 70 points AND scale bar criterion must be met

Uses TRAJECTORY FRAMES for VLM verification (not just final screenshot)
to prove the agent actually performed the workflow.
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

SCALE_BAR_PROMPT = """Analyze this Google Earth map export image.

TASK: Determine if a scale bar/scale legend is visible.

A Google Earth scale bar typically appears as:
- A horizontal bar in a corner (usually bottom-left or bottom-right)
- Shows distance measurement (e.g., "10 km", "5 mi", "50 km")
- Has tick marks or segments showing distance increments
- May be black/white or colored bar with text

Carefully examine ALL corners and edges of the image for a scale indicator.

Respond in JSON format:
{
    "scale_bar_present": true/false,
    "scale_bar_location": "description of location or null",
    "scale_bar_text_visible": "any readable distance text or null",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

GEOGRAPHY_PROMPT = """Analyze this satellite/map image to identify the geographic location.

TASK: Determine if this shows the Nile Delta region of Egypt.

Key indicators of the Nile Delta:
1. Fan-shaped river delta formation spreading north toward the sea
2. Mediterranean Sea coastline at the top (if north-oriented)
3. Green/agricultural areas contrasting with surrounding desert (tan/brown)
4. Two main river branches (Rosetta and Damietta) splitting the delta
5. Dense development near Cairo at the southern apex of the delta
6. The Nile River flowing from south through the delta

Also assess:
- Is the view oriented with north at the top? (Mediterranean Sea at top)
- Is the zoom level appropriate to see the whole delta?

Respond in JSON format:
{
    "shows_nile_delta": true/false,
    "mediterranean_visible": true/false,
    "north_oriented": true/false,
    "delta_features_visible": ["list any visible features"],
    "zoom_level_appropriate": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""

TRAJECTORY_WORKFLOW_PROMPT = """Analyze these sequential screenshots from a Google Earth session.

TASK: The agent should have:
1. Navigated to the Nile Delta, Egypt
2. Enabled the Scale Legend (View menu)
3. Saved an image

Look for evidence of this workflow across the frames:
- Google Earth interface visible
- Navigation to Egypt/Nile region (search bar usage, map showing Egypt)
- View menu interaction (for enabling scale legend)
- File save dialog (for exporting image)
- The Nile Delta region visible in the view

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "navigation_performed": true/false,
    "view_menu_accessed": true/false,
    "file_save_dialog_seen": true/false,
    "nile_region_shown": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def _safe_vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Safely query VLM and return parsed result or None."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    
    try:
        if images:
            result = query_vlm(prompt=prompt, images=images)
        elif image:
            result = query_vlm(prompt=prompt, image=image)
        else:
            return None
        
        if result.get("success"):
            return result.get("parsed", {})
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return None
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
        return None


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_cartographic_export_scalebar(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Verify the cartographic export task completion.
    
    Uses multiple independent signals:
    - Programmatic: File existence, validity, timestamp
    - VLM on exported image: Scale bar, geography
    - VLM on trajectory: Workflow verification
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    
    # Get functions from env_info
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/nile_delta_map.jpg')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output file exists")
    else:
        feedback_parts.append("❌ Output file NOT found")
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File is valid image (10 points)
    # ================================================================
    output_size = result_data.get('output_size_bytes', 0)
    image_format = result_data.get('image_format', 'unknown')
    image_width = result_data.get('image_width', 0)
    image_height = result_data.get('image_height', 0)
    
    valid_formats = ['jpeg', 'jpg', 'png', 'tiff', 'bmp']
    is_valid_format = any(fmt in image_format.lower() for fmt in valid_formats)
    is_valid_size = output_size >= (min_file_size_kb * 1024)
    
    if is_valid_format and is_valid_size:
        score += 10
        feedback_parts.append(f"✅ Valid image ({image_format}, {output_size/1024:.1f}KB)")
    elif is_valid_format:
        score += 5
        feedback_parts.append(f"⚠️ Valid format but small ({output_size/1024:.1f}KB)")
    else:
        feedback_parts.append(f"❌ Invalid image format ({image_format})")
    
    # ================================================================
    # CRITERION 3: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result_data.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("❌ File NOT created during task (pre-existing)")
        # This is suspicious - could be gaming
        details['anti_gaming_flag'] = 'file_timestamp_mismatch'
    
    # ================================================================
    # STEP 2: Copy exported image for VLM analysis
    # ================================================================
    temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    exported_image_path = None
    
    try:
        output_path = result_data.get('output_path', expected_output_path)
        copy_from_env(output_path, temp_image.name)
        
        # Verify the copied file is valid
        if os.path.exists(temp_image.name) and os.path.getsize(temp_image.name) > 1000:
            exported_image_path = temp_image.name
            details['exported_image_copied'] = True
        else:
            details['exported_image_copied'] = False
    except Exception as e:
        logger.warning(f"Could not copy exported image: {e}")
        details['image_copy_error'] = str(e)
    
    # ================================================================
    # CRITERION 4: Scale bar visible (25 points) - MANDATORY
    # ================================================================
    scale_bar_verified = False
    
    if exported_image_path and query_vlm:
        vlm_scale = _safe_vlm_query(query_vlm, SCALE_BAR_PROMPT, image=exported_image_path)
        details['vlm_scale_bar'] = vlm_scale
        
        if vlm_scale:
            scale_bar_present = vlm_scale.get('scale_bar_present', False)
            confidence = vlm_scale.get('confidence', 'low')
            
            if scale_bar_present:
                if confidence == 'high':
                    score += 25
                    scale_bar_verified = True
                    feedback_parts.append("✅ Scale bar visible (high confidence)")
                elif confidence == 'medium':
                    score += 20
                    scale_bar_verified = True
                    feedback_parts.append("✅ Scale bar visible (medium confidence)")
                else:
                    score += 12
                    feedback_parts.append("⚠️ Scale bar possibly visible (low confidence)")
            else:
                feedback_parts.append("❌ Scale bar NOT detected in image")
        else:
            feedback_parts.append("⚠️ Could not verify scale bar (VLM unavailable)")
    else:
        feedback_parts.append("⚠️ Could not verify scale bar (image/VLM unavailable)")
    
    # ================================================================
    # CRITERION 5: Nile Delta shown (20 points)
    # ================================================================
    nile_delta_verified = False
    north_oriented = False
    
    if exported_image_path and query_vlm:
        vlm_geo = _safe_vlm_query(query_vlm, GEOGRAPHY_PROMPT, image=exported_image_path)
        details['vlm_geography'] = vlm_geo
        
        if vlm_geo:
            shows_delta = vlm_geo.get('shows_nile_delta', False)
            confidence = vlm_geo.get('confidence', 'low')
            north_oriented = vlm_geo.get('north_oriented', False)
            zoom_appropriate = vlm_geo.get('zoom_level_appropriate', False)
            
            if shows_delta:
                if confidence in ['high', 'medium']:
                    score += 20
                    nile_delta_verified = True
                    feedback_parts.append("✅ Nile Delta region confirmed")
                else:
                    score += 10
                    feedback_parts.append("⚠️ Nile Delta possibly shown (low confidence)")
            else:
                feedback_parts.append("❌ Nile Delta NOT identified in image")
            
            details['north_oriented'] = north_oriented
            details['zoom_appropriate'] = zoom_appropriate
        else:
            feedback_parts.append("⚠️ Could not verify geography (VLM unavailable)")
    else:
        feedback_parts.append("⚠️ Could not verify geography (image/VLM unavailable)")
    
    # ================================================================
    # CRITERION 6: Appropriate zoom level (10 points)
    # ================================================================
    if details.get('vlm_geography', {}).get('zoom_level_appropriate', False):
        score += 10
        feedback_parts.append("✅ Appropriate zoom level")
    elif image_width >= 800 and image_height >= 600:
        # Fallback: reasonable image dimensions
        score += 5
        feedback_parts.append(f"⚠️ Image dimensions OK ({image_width}x{image_height})")
    else:
        feedback_parts.append("❌ Zoom level may be inappropriate")
    
    # ================================================================
    # CRITERION 7: North-up orientation (10 points)
    # ================================================================
    if north_oriented:
        score += 10
        feedback_parts.append("✅ North-up orientation confirmed")
    elif details.get('vlm_geography', {}).get('mediterranean_visible', False):
        # Mediterranean visible suggests correct orientation
        score += 7
        feedback_parts.append("⚠️ Orientation likely correct (Mediterranean visible)")
    else:
        feedback_parts.append("⚠️ Could not confirm north orientation")
    
    # ================================================================
    # BONUS: Trajectory verification (workflow evidence)
    # ================================================================
    if query_vlm:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            traj_frames = sample_trajectory_frames(traj, n=5)
            if traj_frames and len(traj_frames) >= 2:
                vlm_traj = _safe_vlm_query(query_vlm, TRAJECTORY_WORKFLOW_PROMPT, images=traj_frames)
                details['vlm_trajectory'] = vlm_traj
                
                if vlm_traj:
                    workflow_done = vlm_traj.get('workflow_progression', False)
                    if workflow_done:
                        feedback_parts.append("✅ Workflow verified via trajectory")
                        details['trajectory_verified'] = True
        except ImportError:
            logger.info("Trajectory frame sampling not available")
        except Exception as e:
            logger.warning(f"Trajectory verification failed: {e}")
    
    # ================================================================
    # Clean up temporary files
    # ================================================================
    if temp_image and os.path.exists(temp_image.name):
        try:
            os.unlink(temp_image.name)
        except:
            pass
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = 100
    
    # Determine pass/fail
    # Must have: >= 70 points AND scale bar criterion substantially met
    mandatory_met = scale_bar_verified or (score >= 12 and details.get('vlm_scale_bar', {}).get('scale_bar_present', False))
    passed = score >= 70 and mandatory_met
    
    # If file wasn't created during task, that's highly suspicious
    if not file_created_during_task and score > 30:
        passed = False
        feedback_parts.append("⚠️ FAILED: Anti-gaming check - file not created during task")
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Score: {score}/{max_score}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }