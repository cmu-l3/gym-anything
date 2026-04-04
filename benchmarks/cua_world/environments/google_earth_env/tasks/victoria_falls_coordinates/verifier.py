#!/usr/bin/env python3
"""
Verifier for Victoria Falls Coordinates Task.

Task: Navigate to Victoria Falls and record the precise coordinates of the main
waterfall to a text file.

Verification Strategy:
1. File existence at ~/Documents/victoria_falls_coords.txt (15 pts)
2. File created after task start - anti-gaming (10 pts)
3. Coordinates successfully parsed from file (15 pts)
4. Latitude accuracy within tolerance (25 pts)
5. Longitude accuracy within tolerance (25 pts)
6. VLM verification using trajectory frames (10 pts)

Pass Threshold: 70 points with valid coordinates

CRITICAL: Uses copy_from_env (NOT exec_in_env) and trajectory frames for VLM.
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# CONSTANTS
# ============================================================

# Victoria Falls main drop coordinates (UNESCO World Heritage data)
TARGET_LAT = -17.9243
TARGET_LON = 25.8572
TOLERANCE = 0.005  # ~500 meters
TOLERANCE_PARTIAL = 0.01  # ~1km for partial credit


# ============================================================
# COORDINATE PARSING
# ============================================================

def extract_coordinates(content: str) -> Tuple[Optional[float], Optional[float]]:
    """
    Extract latitude and longitude from text content.
    Handles various common coordinate formats.
    
    Returns:
        Tuple of (latitude, longitude) or (None, None) if parsing fails
    """
    if not content:
        return None, None
    
    patterns = [
        # "Latitude: -17.9243, Longitude: 25.8572"
        (r'[Ll]at(?:itude)?[:\s]+(-?\d+\.?\d*)[,\s]+[Ll]on(?:gitude)?[:\s]+(-?\d+\.?\d*)', 'decimal'),
        # "-17.9243, 25.8572" or "-17.9243 25.8572"
        (r'(-?\d+\.\d{3,})[,\s]+(-?\d+\.\d{3,})', 'decimal'),
        # "17.9243°S, 25.8572°E" or "17.9243 S, 25.8572 E"
        (r'(\d+\.?\d*)[°]?\s*([SN])[,\s]+(\d+\.?\d*)[°]?\s*([EW])', 'dms_suffix'),
        # "S 17.9243, E 25.8572"
        (r'([SN])\s*(\d+\.?\d*)[,\s]+([EW])\s*(\d+\.?\d*)', 'dms_prefix'),
        # "lat=-17.9243 lon=25.8572"
        (r'lat\s*=\s*(-?\d+\.?\d*)[,\s]+lon\s*=\s*(-?\d+\.?\d*)', 'decimal'),
    ]
    
    for pattern, ptype in patterns:
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            groups = match.groups()
            try:
                if ptype == 'decimal' and len(groups) == 2:
                    return float(groups[0]), float(groups[1])
                elif ptype == 'dms_suffix' and len(groups) == 4:
                    lat = float(groups[0])
                    if groups[1].upper() == 'S':
                        lat = -lat
                    lon = float(groups[2])
                    if groups[3].upper() == 'W':
                        lon = -lon
                    return lat, lon
                elif ptype == 'dms_prefix' and len(groups) == 4:
                    lat = float(groups[1])
                    if groups[0].upper() == 'S':
                        lat = -lat
                    lon = float(groups[3])
                    if groups[2].upper() == 'W':
                        lon = -lon
                    return lat, lon
            except (ValueError, IndexError):
                continue
    
    return None, None


# ============================================================
# VLM VERIFICATION
# ============================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are verifying if an agent successfully navigated to Victoria Falls in Google Earth.

Victoria Falls (Mosi-oa-Tunya) is located on the Zambia-Zimbabwe border in Africa. It is one of the largest waterfalls in the world, where the Zambezi River plunges into a narrow gorge.

Examine these screenshots from the agent's interaction and determine:

1. IS_GOOGLE_EARTH: Is this clearly Google Earth Pro (satellite imagery application)?
2. SHOWS_AFRICA: Does the view show the African continent or southern Africa region?
3. SHOWS_WATERFALL_REGION: Is there a large waterfall or gorge visible (Victoria Falls is a long cliff/gorge where water falls)?
4. SHOWS_ZAMBEZI: Is a river visible (the Zambezi River flows to Victoria Falls)?
5. NAVIGATION_OCCURRED: Do the frames show the agent navigating/searching (not just sitting at default view)?

Look for:
- Satellite imagery of a river meeting a dramatic cliff/gorge
- The characteristic zigzag gorge pattern downstream of Victoria Falls
- Green vegetation along the falls (rainforest sustained by spray)
- The town of Livingstone (Zambia) or Victoria Falls town (Zimbabwe) nearby

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_africa_region": true/false,
    "shows_waterfall_or_gorge": true/false,
    "shows_river": true/false,
    "navigation_occurred": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the images"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """
    Verify task completion using VLM on trajectory frames.
    
    Uses MULTIPLE trajectory frames to verify actual navigation occurred,
    not just the final state (which could be spoofed).
    """
    if not query_vlm:
        return {"success": False, "error": "VLM query function not available", "score": 0}
    
    # Import VLM utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("Could not import VLM utilities, using fallback")
        # Fallback: try to get frames from trajectory
        frames = traj.get('frames', [])
        if not frames:
            return {"success": False, "error": "No trajectory frames available", "score": 0}
        # Sample evenly across trajectory
        n_samples = min(5, len(frames))
        indices = [int(i * len(frames) / n_samples) for i in range(n_samples)]
        sampled_frames = [frames[i] for i in indices]
        final_frame = frames[-1] if frames else None
        
        # Use these as our images
        images = sampled_frames
        if final_frame and final_frame not in images:
            images.append(final_frame)
    else:
        # Use proper utilities
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames if frames else []
        if final and final not in images:
            images.append(final)
    
    if not images:
        return {"success": False, "error": "No images available for VLM verification", "score": 0}
    
    try:
        vlm_result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=images
        )
        
        if not vlm_result.get("success"):
            return {
                "success": False, 
                "error": vlm_result.get("error", "VLM query failed"),
                "score": 0
            }
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate VLM score based on criteria
        criteria_met = 0
        total_criteria = 5
        
        if parsed.get("is_google_earth", False):
            criteria_met += 1
        if parsed.get("shows_africa_region", False):
            criteria_met += 1
        if parsed.get("shows_waterfall_or_gorge", False):
            criteria_met += 1
        if parsed.get("shows_river", False):
            criteria_met += 1
        if parsed.get("navigation_occurred", False):
            criteria_met += 1
        
        confidence = parsed.get("confidence", "low")
        confidence_multiplier = {"high": 1.0, "medium": 0.85, "low": 0.7}.get(confidence, 0.7)
        
        # VLM contributes up to 10 points
        vlm_score = int((criteria_met / total_criteria) * 10 * confidence_multiplier)
        
        return {
            "success": True,
            "score": vlm_score,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "confidence": confidence,
            "observations": parsed.get("observations", ""),
            "parsed": parsed
        }
        
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"success": False, "error": str(e), "score": 0}


# ============================================================
# MAIN VERIFICATION FUNCTION
# ============================================================

def verify_victoria_falls_coordinates(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent navigated to Victoria Falls and recorded correct coordinates.
    
    Multi-criteria scoring:
    1. File exists (15 pts)
    2. File created during task (10 pts) - anti-gaming
    3. Coordinates parsed successfully (15 pts)
    4. Latitude within tolerance (25 pts)
    5. Longitude within tolerance (25 pts)
    6. VLM trajectory verification (10 pts)
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "details": {"error": "copy_from_env not provided"}
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', TARGET_LAT)
    target_lon = metadata.get('target_longitude', TARGET_LON)
    tolerance = metadata.get('tolerance_degrees', TOLERANCE)
    output_file = metadata.get('output_file', '/home/ga/Documents/victoria_falls_coords.txt')
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Copy the actual coordinate file from container
    # ================================================================
    file_content = None
    temp_coords = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(output_file, temp_coords.name)
        with open(temp_coords.name, 'r') as f:
            file_content = f.read()
        details['file_content'] = file_content
    except Exception as e:
        logger.info(f"Could not copy coordinate file: {e}")
        file_content = None
    finally:
        if os.path.exists(temp_coords.name):
            os.unlink(temp_coords.name)
    
    # ================================================================
    # CRITERION 1: File exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False) or (file_content is not None)
    
    if output_exists and file_content:
        score += 15
        feedback_parts.append("✅ Coordinate file exists")
        details['file_exists'] = True
    elif output_exists:
        score += 10
        feedback_parts.append("⚠️ File exists but could not read content")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Coordinate file not found")
        details['file_exists'] = False
        # Early partial return - continue to check other criteria
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['timestamp_valid'] = True
    elif output_exists and output_mtime > task_start:
        score += 10
        feedback_parts.append("✅ File modified during task")
        details['timestamp_valid'] = True
    elif output_exists:
        feedback_parts.append("⚠️ File may have existed before task")
        details['timestamp_valid'] = "uncertain"
    else:
        details['timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Coordinates parsed successfully (15 points)
    # ================================================================
    parsed_lat = None
    parsed_lon = None
    
    # Try parsing from file content first
    if file_content:
        parsed_lat, parsed_lon = extract_coordinates(file_content)
    
    # Fall back to export script's parsed values
    if parsed_lat is None and result.get('parse_success'):
        parsed_lat = result.get('parsed_latitude')
        parsed_lon = result.get('parsed_longitude')
    
    if parsed_lat is not None and parsed_lon is not None:
        score += 15
        feedback_parts.append(f"✅ Coordinates parsed: ({parsed_lat:.4f}, {parsed_lon:.4f})")
        details['coordinates_parsed'] = True
        details['parsed_latitude'] = parsed_lat
        details['parsed_longitude'] = parsed_lon
    else:
        feedback_parts.append("❌ Could not parse coordinates from file")
        details['coordinates_parsed'] = False
    
    # ================================================================
    # CRITERION 4: Latitude accuracy (25 points)
    # ================================================================
    lat_error = None
    if parsed_lat is not None:
        lat_error = abs(parsed_lat - target_lat)
        details['latitude_error_degrees'] = lat_error
        
        if lat_error <= tolerance:
            score += 25
            feedback_parts.append(f"✅ Latitude correct (error: {lat_error:.4f}°)")
            details['latitude_correct'] = True
        elif lat_error <= TOLERANCE_PARTIAL:
            score += 15
            feedback_parts.append(f"⚠️ Latitude close (error: {lat_error:.4f}°)")
            details['latitude_correct'] = "partial"
        else:
            feedback_parts.append(f"❌ Latitude incorrect (error: {lat_error:.4f}°)")
            details['latitude_correct'] = False
    else:
        details['latitude_correct'] = False
    
    # ================================================================
    # CRITERION 5: Longitude accuracy (25 points)
    # ================================================================
    lon_error = None
    if parsed_lon is not None:
        lon_error = abs(parsed_lon - target_lon)
        details['longitude_error_degrees'] = lon_error
        
        if lon_error <= tolerance:
            score += 25
            feedback_parts.append(f"✅ Longitude correct (error: {lon_error:.4f}°)")
            details['longitude_correct'] = True
        elif lon_error <= TOLERANCE_PARTIAL:
            score += 15
            feedback_parts.append(f"⚠️ Longitude close (error: {lon_error:.4f}°)")
            details['longitude_correct'] = "partial"
        else:
            feedback_parts.append(f"❌ Longitude incorrect (error: {lon_error:.4f}°)")
            details['longitude_correct'] = False
    else:
        details['longitude_correct'] = False
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (10 points)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        score += vlm_score
        if vlm_score >= 7:
            feedback_parts.append(f"✅ VLM verification passed ({vlm_score}/10)")
        elif vlm_score >= 4:
            feedback_parts.append(f"⚠️ VLM verification partial ({vlm_score}/10)")
        else:
            feedback_parts.append(f"❌ VLM verification low ({vlm_score}/10)")
    else:
        feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # Calculate final result
    # ================================================================
    
    # Key criteria for passing
    coordinates_valid = (
        details.get('coordinates_parsed', False) and
        details.get('latitude_correct') in [True, "partial"] and
        details.get('longitude_correct') in [True, "partial"]
    )
    
    # Pass requires 70+ points AND valid coordinates
    passed = score >= 70 and coordinates_valid
    
    # Summary
    feedback_parts.append(f"Score: {score}/{max_score}")
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }