#!/usr/bin/env python3
"""
Verifier for moon_tycho_exploration task.

VERIFICATION STRATEGY:
This task requires switching Google Earth Pro to Moon mode, navigating to
Tycho Crater, and creating a placemark. We use a hybrid verification approach:

1. PROGRAMMATIC CHECKS (from myplaces.kml):
   - Tycho placemark exists (20 pts)
   - Coordinates near target (15 pts)
   - Description includes 85km reference (10 pts)

2. VLM TRAJECTORY VERIFICATION (from framework-captured screenshots):
   - Moon mode activated - lunar surface visible (25 pts)
   - Tycho Crater located - crater with rays visible (25 pts)
   - Workflow progression evidence (5 pts)

ANTI-GAMING:
- Trajectory screenshots are captured by the framework and cannot be tampered with
- File timestamps are checked to ensure work was done during the task
- Multiple independent signals required for passing

Pass threshold: 70 points with Moon mode (25 pts) being mandatory
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# VLM PROMPTS
# ============================================================

TRAJECTORY_MOON_PROMPT = """Analyze these sequential screenshots from Google Earth Pro to determine if the agent switched to Moon exploration mode.

The screenshots are in chronological order (earliest to latest).

EARTH VIEW characteristics:
- Blue oceans covering ~70% of surface
- Green/brown landmasses (continents)
- White cloud patterns
- Colorful terrain

MOON VIEW characteristics:
- Gray/white cratered surface (NO blue, NO green)
- Heavily cratered terrain
- No atmosphere/clouds
- Monochromatic gray appearance
- Impact craters visible everywhere

For EACH screenshot, identify if it shows Earth or Moon surface.

The task PASSES if at least one screenshot clearly shows the MOON surface (gray cratered terrain, not Earth).

Respond in JSON format:
{
    "moon_surface_detected": true/false,
    "earth_frames_count": <number of frames showing Earth>,
    "moon_frames_count": <number of frames showing Moon>,
    "transition_detected": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the progression"
}
"""

CRATER_VERIFICATION_PROMPT = """Analyze these screenshots from Google Earth Pro's Moon exploration mode.

The task was to navigate to TYCHO CRATER on the Moon. Tycho Crater has these distinctive features:
- Large impact crater (~85 km diameter)
- Located in lunar southern hemisphere
- PROMINENT BRIGHT RAY SYSTEM extending hundreds of kilometers
- Central peak visible at crater center
- One of the youngest large craters (bright and well-preserved)

Look for evidence that the view is centered on or shows Tycho Crater:
1. Is a large impact crater visible?
2. Does it have a ray system (bright streaks extending outward)?
3. Is there a central peak?
4. Does the crater appear well-preserved (sharp rim)?

Note: The agent may be zoomed in (showing just the crater) or zoomed out (showing crater with ray system). Both are valid.

Respond in JSON format:
{
    "large_crater_visible": true/false,
    "ray_system_visible": true/false,
    "central_peak_visible": true/false,
    "appears_to_be_tycho": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what crater features you observe"
}
"""

PLACEMARK_DIALOG_PROMPT = """Analyze this screenshot to determine if the user is creating or has created a placemark in Google Earth.

Look for evidence of placemark creation:
1. "New Placemark" or "Edit Placemark" dialog box visible
2. A placemark pin/marker icon on the surface
3. Properties panel showing placemark name/description
4. Text containing "Tycho" visible
5. "My Places" panel showing saved locations

Respond in JSON format:
{
    "placemark_dialog_visible": true/false,
    "placemark_marker_visible": true/false,
    "tycho_text_visible": true/false,
    "my_places_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe placemark-related UI elements"
}
"""


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def check_coordinates_near_tycho(lat: Optional[float], lon: Optional[float], tolerance: float = 5.0) -> Tuple[bool, str]:
    """
    Check if coordinates are near Tycho Crater.
    Tycho Crater: approximately 43.31°S, 11.36°W
    
    On the Moon, Google Earth may use different coordinate conventions.
    We'll accept reasonable variations.
    """
    if lat is None or lon is None:
        return False, "No coordinates found"
    
    # Target: 43.31°S = -43.31, 11.36°W = -11.36
    target_lat = -43.31
    target_lon = -11.36
    
    lat_diff = abs(lat - target_lat)
    lon_diff = abs(lon - target_lon)
    
    # Also check positive variants (coordinate convention differences)
    alt_lat_diff = abs(abs(lat) - 43.31)
    alt_lon_diff = abs(abs(lon) - 11.36)
    
    if (lat_diff <= tolerance and lon_diff <= tolerance):
        return True, f"Coordinates ({lat}, {lon}) within {tolerance}° of Tycho"
    elif (alt_lat_diff <= tolerance and alt_lon_diff <= tolerance):
        return True, f"Coordinates ({lat}, {lon}) match Tycho (different convention)"
    else:
        return False, f"Coordinates ({lat}, {lon}) not near Tycho target ({target_lat}, {target_lon})"


def query_vlm_safe(query_vlm, prompt: str, images: list) -> Optional[Dict]:
    """Safely query VLM with error handling."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


# ============================================================
# MAIN VERIFICATION FUNCTION
# ============================================================

def verify_moon_tycho_exploration(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent:
    1. Switched Google Earth to Moon mode
    2. Navigated to Tycho Crater
    3. Created a placemark documenting the location
    
    Uses hybrid verification: programmatic checks + VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata for expected values
    metadata = task_info.get('metadata', {})
    coordinate_tolerance = metadata.get('coordinate_tolerance', 5.0)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    criteria = {}
    
    # ============================================================
    # STEP 1: Copy and parse task result from container
    # ============================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load task result: {e}")
        details['result_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ============================================================
    # STEP 2: Check programmatic evidence - Tycho placemark (20 pts)
    # ============================================================
    tycho_data = result_data.get('tycho_placemark', {})
    
    if tycho_data.get('found', False):
        placemark_score = 20
        feedback_parts.append("✅ Tycho placemark created")
        details['placemark_name'] = tycho_data.get('name', '')
    else:
        placemark_score = 0
        feedback_parts.append("❌ No Tycho placemark found in My Places")
    
    criteria['placemark_created'] = placemark_score
    score += placemark_score
    
    # ============================================================
    # STEP 3: Check coordinate accuracy (15 pts)
    # ============================================================
    lat = tycho_data.get('latitude')
    lon = tycho_data.get('longitude')
    
    coords_correct, coords_msg = check_coordinates_near_tycho(lat, lon, coordinate_tolerance)
    details['coordinate_check'] = coords_msg
    
    if coords_correct:
        coord_score = 15
        feedback_parts.append(f"✅ Coordinates correct: ({lat}, {lon})")
    elif lat is not None and lon is not None:
        # Partial credit if coordinates exist but wrong location
        coord_score = 5
        feedback_parts.append(f"⚠️ Placemark has coordinates but not near Tycho")
    else:
        coord_score = 0
        feedback_parts.append("❌ No valid coordinates in placemark")
    
    criteria['coordinates_correct'] = coord_score
    score += coord_score
    
    # ============================================================
    # STEP 4: Check description includes 85km (10 pts)
    # ============================================================
    if tycho_data.get('has_85km_reference', False):
        desc_score = 10
        feedback_parts.append("✅ Description mentions 85 km diameter")
    elif tycho_data.get('description', ''):
        desc_score = 3
        feedback_parts.append("⚠️ Description exists but missing 85km reference")
    else:
        desc_score = 0
        feedback_parts.append("❌ No description in placemark")
    
    criteria['description_included'] = desc_score
    score += desc_score
    
    # ============================================================
    # STEP 5: Check file modification timestamps (anti-gaming)
    # ============================================================
    myplaces_data = result_data.get('myplaces', {})
    file_modified = myplaces_data.get('modified_during_task', False)
    
    if file_modified:
        details['file_timestamp_valid'] = True
    else:
        details['file_timestamp_valid'] = False
        # Reduce placemark score if file wasn't modified during task
        if placemark_score > 0:
            score -= 10
            feedback_parts.append("⚠️ Placemark file may predate task")
    
    # ============================================================
    # STEP 6: VLM Trajectory Verification - Moon Mode (25 pts)
    # ============================================================
    moon_score = 0
    
    if query_vlm:
        # Get trajectory frames from the framework
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        trajectory_frames = sample_trajectory_frames(traj, n=6) if hasattr(traj, '__iter__') or isinstance(traj, dict) else []
        final_screenshot = get_final_screenshot(traj)
        
        # Combine for analysis
        all_frames = trajectory_frames if trajectory_frames else []
        if final_screenshot and final_screenshot not in all_frames:
            all_frames.append(final_screenshot)
        
        details['trajectory_frames_count'] = len(all_frames)
        
        if all_frames:
            # Check for Moon surface
            moon_result = query_vlm_safe(query_vlm, TRAJECTORY_MOON_PROMPT, all_frames)
            
            if moon_result:
                details['moon_vlm_result'] = moon_result
                
                if moon_result.get('moon_surface_detected', False):
                    confidence = moon_result.get('confidence', 'low')
                    
                    if confidence == 'high':
                        moon_score = 25
                        feedback_parts.append("✅ Moon surface clearly visible in trajectory")
                    elif confidence == 'medium':
                        moon_score = 20
                        feedback_parts.append("✅ Moon surface detected (medium confidence)")
                    else:
                        moon_score = 15
                        feedback_parts.append("⚠️ Possible Moon surface (low confidence)")
                else:
                    feedback_parts.append("❌ Moon surface not detected in screenshots")
            else:
                feedback_parts.append("⚠️ Could not verify Moon mode via VLM")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for Moon verification")
    else:
        # Without VLM, give partial credit based on other evidence
        feedback_parts.append("⚠️ VLM not available for Moon mode verification")
        # If we have valid coordinates on Moon, assume Moon mode was activated
        if coords_correct:
            moon_score = 15
            feedback_parts.append("✓ Moon mode inferred from lunar coordinates")
    
    criteria['moon_mode_activated'] = moon_score
    score += moon_score
    
    # ============================================================
    # STEP 7: VLM Trajectory Verification - Crater Located (25 pts)
    # ============================================================
    crater_score = 0
    
    if query_vlm and moon_score > 0:  # Only check crater if Moon mode confirmed
        if all_frames:
            crater_result = query_vlm_safe(query_vlm, CRATER_VERIFICATION_PROMPT, all_frames)
            
            if crater_result:
                details['crater_vlm_result'] = crater_result
                
                if crater_result.get('appears_to_be_tycho', False):
                    confidence = crater_result.get('confidence', 'low')
                    
                    if confidence == 'high':
                        crater_score = 25
                        feedback_parts.append("✅ Tycho Crater identified in view")
                    elif confidence == 'medium':
                        crater_score = 20
                        feedback_parts.append("✅ Large crater with rays visible (likely Tycho)")
                    else:
                        crater_score = 12
                        feedback_parts.append("⚠️ Crater visible but Tycho identification uncertain")
                elif crater_result.get('large_crater_visible', False):
                    crater_score = 10
                    feedback_parts.append("⚠️ Crater visible but not confirmed as Tycho")
                else:
                    feedback_parts.append("❌ Tycho Crater not identified in view")
            else:
                feedback_parts.append("⚠️ Could not verify crater via VLM")
    elif moon_score == 0:
        feedback_parts.append("⚠️ Crater verification skipped (Moon mode not confirmed)")
    else:
        # Without VLM, infer from coordinates
        if coords_correct:
            crater_score = 15
            feedback_parts.append("✓ Crater location inferred from coordinates")
    
    criteria['tycho_crater_located'] = crater_score
    score += crater_score
    
    # ============================================================
    # STEP 8: Workflow Evidence (5 pts)
    # ============================================================
    workflow_score = 0
    
    # Check task duration
    duration = result_data.get('task_duration_seconds', 0)
    if duration >= 30:
        workflow_score = 5
        details['task_duration'] = duration
    elif duration >= 15:
        workflow_score = 3
    
    criteria['workflow_evidence'] = workflow_score
    score += workflow_score
    
    # ============================================================
    # FINAL DETERMINATION
    # ============================================================
    
    # Key criteria: Moon mode must be detected (mandatory for passing)
    moon_mode_achieved = moon_score >= 15
    
    # Pass requires 70 points AND Moon mode
    passed = score >= 70 and moon_mode_achieved
    
    if not moon_mode_achieved:
        feedback_parts.append("⚠️ MANDATORY: Moon mode activation not confirmed")
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "criteria": criteria,
        "max_score": max_score
    }