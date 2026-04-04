#!/usr/bin/env python3
"""
Verifier for tokyo_3d_buildings task.

Task: Navigate to Tokyo's Shinjuku district, enable 3D Buildings layer,
      tilt camera view, and save screenshot to ~/Documents/tokyo_skyline_3d.png

VERIFICATION STRATEGY (Multi-signal, anti-gaming):
1. File exists at correct path (15 points)
2. File was created DURING task - timestamp check (15 points)
3. Valid image dimensions (10 points)
4. VLM: Tokyo/Shinjuku location visible (20 points)
5. VLM: 3D buildings rendered (not flat imagery) (25 points)
6. VLM: Tilted perspective view (15 points)

Uses TRAJECTORY frames (not just final screenshot) to verify actual work was done.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# VLM PROMPTS
# ============================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro.

The agent's task was to:
1. Navigate to Shinjuku, Tokyo, Japan
2. Enable the 3D Buildings layer
3. Tilt the camera to show a perspective/skyline view
4. Save a screenshot

Look at these trajectory frames (chronologically ordered, earliest to latest) and assess:

1. GOOGLE_EARTH_USED: Is Google Earth Pro visible in any frames?
2. NAVIGATION_TO_TOKYO: Did the agent navigate to what appears to be Tokyo/Japan (dense Asian urban area)?
3. VIEW_CHANGED: Do the frames show meaningful view changes (zoom, pan, tilt) - not just static screens?
4. WORKFLOW_PROGRESSION: Did the agent progress through navigation, layer changes, or view adjustments?

Respond in JSON format:
{
    "google_earth_used": true/false,
    "navigation_to_tokyo": true/false,
    "view_changed": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list what you see: search, navigation, 3d buildings, tilt, save dialog, etc"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression across frames"
}
"""

OUTPUT_IMAGE_VERIFICATION_PROMPT = """You are verifying a saved screenshot from Google Earth Pro.

The agent was asked to capture a 3D perspective view of Tokyo's Shinjuku skyline.

Analyze this image and assess:

1. IS_GOOGLE_EARTH_VIEW: Is this clearly a Google Earth/satellite imagery view (not a photo, webpage, or other app)?

2. SHOWS_TOKYO_AREA: Does this show Tokyo, Japan? Look for:
   - Dense urban development with Asian city characteristics
   - Japanese urban patterns (dense high-rises, mixed development)
   - Shinjuku area has very tall skyscrapers clustered together
   - Could be Shinjuku, Shibuya, or central Tokyo area

3. HAS_3D_BUILDINGS: Are 3D building models visible? Key indicators:
   - Buildings have visible HEIGHT (not flat colored shapes)
   - Buildings cast shadows
   - Building facades/sides are visible
   - Sense of depth and 3D geometry
   - NOT just flat 2D satellite/aerial imagery

4. IS_TILTED_PERSPECTIVE: Is the camera tilted to show a perspective/skyline view?
   - View should NOT be straight down (bird's eye/nadir)
   - Should show building sides and create depth perception
   - Horizon may be visible or implied
   - Buildings should appear to have height perspective

5. IMAGE_QUALITY: Is this a proper screenshot (not corrupt, not blank, reasonable resolution)?

Respond in JSON format:
{
    "is_google_earth_view": true/false,
    "shows_tokyo_area": true/false,
    "has_3d_buildings": true/false,
    "is_tilted_perspective": true/false,
    "image_quality_ok": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see in the image"
}
"""


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def safe_copy_file(copy_from_env, remote_path: str, suffix: str = '.tmp') -> Optional[str]:
    """Safely copy a file from the environment to a temp file."""
    if not copy_from_env:
        return None
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        copy_from_env(remote_path, temp_path)
        if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
            return temp_path
        else:
            os.unlink(temp_path)
            return None
    except Exception as e:
        logger.warning(f"Failed to copy {remote_path}: {e}")
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return None


def query_vlm_safe(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Safely query VLM with error handling."""
    if not query_vlm:
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


# ============================================================
# MAIN VERIFICATION FUNCTION
# ============================================================

def verify_tokyo_3d_buildings(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that agent created a 3D perspective view of Tokyo skyline.
    
    Uses multiple independent verification signals:
    - Programmatic: File existence, timestamps, dimensions
    - VLM on trajectory: Workflow verification
    - VLM on output: Content verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ copy_from_env function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/tokyo_skyline_3d.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ============================================================
    # STEP 1: Copy and parse task result JSON
    # ============================================================
    result_path = safe_copy_file(copy_from_env, "/tmp/task_result.json", suffix='.json')
    
    if not result_path:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Could not retrieve task result file"
        }
    
    try:
        with open(result_path, 'r') as f:
            result = json.load(f)
        details['task_result'] = result
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse task result: {e}"
        }
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)
    
    # ============================================================
    # CRITERION 1: Output file exists (15 points)
    # ============================================================
    output_info = result.get('output_file', {})
    output_exists = output_info.get('exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output file exists")
    else:
        feedback_parts.append("❌ Output file NOT found at ~/Documents/tokyo_skyline_3d.png")
        # Can still get partial points from trajectory verification
    
    # ============================================================
    # CRITERION 2: File created during task (15 points) - ANTI-GAMING
    # ============================================================
    file_created_during_task = output_info.get('created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task execution")
    elif output_exists:
        feedback_parts.append("⚠️ File existed before task (timestamp mismatch)")
    else:
        feedback_parts.append("⚠️ Cannot verify file creation time")
    
    # ============================================================
    # CRITERION 3: Valid image dimensions (10 points)
    # ============================================================
    image_width = output_info.get('image_width', 0)
    image_height = output_info.get('image_height', 0)
    image_format = output_info.get('image_format', 'none')
    file_size_kb = output_info.get('size_bytes', 0) / 1024
    
    if output_exists:
        valid_dimensions = image_width >= 800 and image_height >= 600
        valid_size = file_size_kb >= min_file_size_kb
        valid_format = image_format.upper() in ['PNG', 'JPEG', 'JPG', 'BMP', 'TIFF']
        
        if valid_dimensions and valid_size and valid_format:
            score += 10
            feedback_parts.append(f"✅ Valid image: {image_width}x{image_height} {image_format} ({file_size_kb:.1f}KB)")
        elif valid_dimensions:
            score += 5
            feedback_parts.append(f"⚠️ Image dimensions OK but small: {file_size_kb:.1f}KB")
        else:
            feedback_parts.append(f"❌ Invalid image: {image_width}x{image_height}")
    
    details['image_info'] = {
        'width': image_width,
        'height': image_height,
        'format': image_format,
        'size_kb': file_size_kb
    }
    
    # ============================================================
    # VLM VERIFICATION: Trajectory Analysis (uses sampled frames)
    # ============================================================
    trajectory_vlm_score = 0
    
    if query_vlm and traj:
        # Get trajectory frames - sample across the episode
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            details['trajectory_frames_count'] = len(trajectory_frames) if trajectory_frames else 0
            
            if trajectory_frames and len(trajectory_frames) >= 2:
                traj_result = query_vlm_safe(
                    query_vlm,
                    TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if traj_result:
                    details['trajectory_vlm'] = traj_result
                    
                    # Award points for trajectory evidence
                    if traj_result.get('google_earth_used', False):
                        trajectory_vlm_score += 5
                        feedback_parts.append("✅ Google Earth usage confirmed in trajectory")
                    
                    if traj_result.get('navigation_to_tokyo', False):
                        trajectory_vlm_score += 5
                        feedback_parts.append("✅ Navigation to Tokyo area observed")
                    
                    if traj_result.get('workflow_progression', False):
                        trajectory_vlm_score += 5
                        feedback_parts.append("✅ Workflow progression observed")
                else:
                    feedback_parts.append("⚠️ Trajectory VLM analysis inconclusive")
            else:
                feedback_parts.append("⚠️ Insufficient trajectory frames for analysis")
        except ImportError:
            logger.warning("Could not import trajectory frame functions")
            feedback_parts.append("⚠️ Trajectory analysis unavailable")
    
    # ============================================================
    # VLM VERIFICATION: Output Image Analysis (60 points total)
    # - Tokyo location visible (20 points)
    # - 3D buildings visible (25 points)
    # - Tilted perspective (15 points)
    # ============================================================
    output_vlm_score = 0
    
    if query_vlm and output_exists:
        # Copy the output image
        output_image_path = safe_copy_file(copy_from_env, expected_output, suffix='.png')
        
        if output_image_path:
            try:
                output_result = query_vlm_safe(
                    query_vlm,
                    OUTPUT_IMAGE_VERIFICATION_PROMPT,
                    image=output_image_path
                )
                
                if output_result:
                    details['output_vlm'] = output_result
                    confidence = output_result.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    # Tokyo location (20 points)
                    if output_result.get('shows_tokyo_area', False):
                        points = int(20 * confidence_mult)
                        output_vlm_score += points
                        feedback_parts.append(f"✅ Tokyo/Shinjuku area visible ({confidence} confidence)")
                    else:
                        feedback_parts.append("❌ Tokyo area not identified in image")
                    
                    # 3D Buildings (25 points) - KEY CRITERION
                    if output_result.get('has_3d_buildings', False):
                        points = int(25 * confidence_mult)
                        output_vlm_score += points
                        feedback_parts.append(f"✅ 3D buildings visible ({confidence} confidence)")
                    else:
                        feedback_parts.append("❌ 3D buildings not visible (flat imagery or wrong layer)")
                    
                    # Tilted perspective (15 points)
                    if output_result.get('is_tilted_perspective', False):
                        points = int(15 * confidence_mult)
                        output_vlm_score += points
                        feedback_parts.append(f"✅ Tilted perspective view ({confidence} confidence)")
                    else:
                        feedback_parts.append("❌ View not tilted (appears to be nadir/top-down)")
                    
                    # Basic validity check
                    if output_result.get('is_google_earth_view', False):
                        feedback_parts.append("✅ Confirmed Google Earth view")
                    else:
                        feedback_parts.append("⚠️ May not be Google Earth imagery")
                else:
                    feedback_parts.append("⚠️ Output image VLM analysis failed")
            finally:
                if os.path.exists(output_image_path):
                    os.unlink(output_image_path)
        else:
            feedback_parts.append("⚠️ Could not copy output image for VLM analysis")
    elif not query_vlm:
        feedback_parts.append("⚠️ VLM not available for visual verification")
    
    # ============================================================
    # Calculate final score
    # ============================================================
    # Programmatic: 40 points max (15 + 15 + 10)
    # Trajectory VLM: 15 points max (bonus)
    # Output VLM: 60 points max (20 + 25 + 15)
    # Total possible: 115 (capped at 100)
    
    total_score = score + trajectory_vlm_score + output_vlm_score
    total_score = min(100, total_score)  # Cap at 100
    
    details['score_breakdown'] = {
        'programmatic': score,
        'trajectory_vlm': trajectory_vlm_score,
        'output_vlm': output_vlm_score,
        'total': total_score
    }
    
    # ============================================================
    # Determine pass/fail
    # ============================================================
    # Pass threshold: 70 points with key criteria
    # Key criteria: File created during task AND (3D buildings visible OR trajectory confirms workflow)
    
    key_criterion_met = (
        file_created_during_task or
        (trajectory_vlm_score >= 10) or
        (output_vlm_score >= 25)  # At least 3D buildings detected
    )
    
    passed = total_score >= 70 and output_exists and key_criterion_met
    
    # Additional check: If output doesn't exist, can't pass
    if not output_exists:
        passed = False
    
    # ============================================================
    # Build final feedback
    # ============================================================
    feedback = f"Score: {total_score}/100\n" + "\n".join(feedback_parts)
    
    if passed:
        feedback = "🎉 PASSED\n" + feedback
    else:
        reasons = []
        if not output_exists:
            reasons.append("output file missing")
        if total_score < 70:
            reasons.append(f"score below threshold ({total_score}<70)")
        if not key_criterion_met:
            reasons.append("key criteria not met")
        feedback = f"❌ FAILED ({', '.join(reasons)})\n" + feedback
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": details
    }