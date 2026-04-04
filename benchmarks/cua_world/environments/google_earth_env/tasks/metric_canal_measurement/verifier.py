#!/usr/bin/env python3
"""
Verifier for metric_canal_measurement task.

TASK: Configure Google Earth Pro to use metric units, navigate to the Suez Canal
at coordinates (30.5853, 32.2654), measure the canal width, and save the
measurement to My Places as 'Suez_Canal_Width_Metric'.

VERIFICATION STRATEGY (Multi-Signal Anti-Gaming):
1. Programmatic: Check myplaces.kml for saved measurement (25 pts)
2. Programmatic: Verify measurement was created during task (15 pts)
3. Programmatic: Check coordinates near target location (15 pts)
4. Programmatic: Check config for metric units (15 pts)
5. VLM Trajectory: Verify workflow progression through Options dialog (15 pts)
6. VLM Final: Verify Suez Canal visible with measurement (15 pts)

Pass threshold: 60 points with key criteria (measurement saved OR VLM confirms work)
"""

import json
import tempfile
import os
import logging
import re
import math
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS
# ================================================================

TARGET_LAT = 30.5853
TARGET_LON = 32.2654
COORD_TOLERANCE = 0.1  # ~11km tolerance
EXPECTED_MEASUREMENT_NAME = "Suez_Canal_Width_Metric"


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def parse_kml_coordinates(coord_string: str) -> list:
    """Parse KML coordinate string into list of (lon, lat) tuples."""
    coords = []
    if not coord_string:
        return coords
    
    # KML format: lon,lat,alt lon,lat,alt ...
    parts = coord_string.strip().split()
    for part in parts:
        try:
            values = part.split(',')
            if len(values) >= 2:
                lon = float(values[0])
                lat = float(values[1])
                coords.append((lon, lat))
        except (ValueError, IndexError):
            continue
    return coords


def coords_near_target(coords: list, target_lat: float, target_lon: float, tolerance: float) -> bool:
    """Check if any coordinates are within tolerance of target."""
    for lon, lat in coords:
        if abs(lat - target_lat) < tolerance and abs(lon - target_lon) < tolerance:
            return True
    return False


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in meters."""
    R = 6371000  # Earth radius in meters
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def estimate_measurement_length(coords: list) -> Optional[float]:
    """Estimate measurement length from coordinates in meters."""
    if len(coords) < 2:
        return None
    
    # For a simple line measurement, calculate distance between first and last points
    lon1, lat1 = coords[0]
    lon2, lat2 = coords[-1]
    
    return haversine_distance(lat1, lon1, lat2, lon2)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_WORKFLOW_PROMPT = """You are analyzing screenshots from an agent configuring Google Earth Pro settings and measuring a canal.

The task requires the agent to:
1. Open Tools > Options menu
2. Navigate to 3D View tab
3. Change measurement units to Metric (Meters, Kilometers)
4. Navigate to the Suez Canal in Egypt
5. Use the Ruler tool to measure the canal width
6. Save the measurement

Looking at these trajectory screenshots (in chronological order), assess:

1. OPTIONS_DIALOG_VISIBLE: Is the Options/Preferences dialog visible in any frame?
2. SETTINGS_INTERACTION: Is there evidence of changing settings (3D View tab, unit dropdowns)?
3. CANAL_NAVIGATION: Is the Suez Canal (a waterway in Egypt with desert on sides) visible?
4. RULER_TOOL_USED: Is there evidence of the Ruler tool being used (measurement line, ruler dialog)?
5. WORKFLOW_PROGRESSION: Do the frames show meaningful state changes (not stuck on same screen)?

Respond in JSON format:
{
    "options_dialog_visible": true/false,
    "settings_interaction": true/false,
    "canal_navigation": true/false,
    "ruler_tool_used": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list what you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro task.

The task was to:
1. Configure metric units
2. Navigate to the Suez Canal (coordinates 30.5853, 32.2654 - near Ismailia, Egypt)
3. Measure the canal width using the Ruler tool
4. Save the measurement

Look at this screenshot and assess:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite imagery application)?
2. SHOWS_SUEZ_CANAL: Is the Suez Canal visible? Look for:
   - A waterway (blue/dark line) cutting through desert terrain
   - The distinctive narrow channel between the Mediterranean and Red Sea
   - Desert/arid landscape on both sides
   - Located in Egypt (northeast Africa/Sinai region)
3. MEASUREMENT_VISIBLE: Is there a ruler/measurement line or dialog visible?
4. METRIC_UNITS_SHOWN: If measurement values are visible, are they in meters (not feet)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_suez_canal": true/false,
    "measurement_visible": true/false,
    "metric_units_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_metric_canal_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the metric canal measurement task completion.
    
    Uses multiple independent signals for robust verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # CRITERION 1: Load and parse task result JSON (from export_result.sh)
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not load task result: {e}")
        feedback_parts.append("⚠️ Could not load task result JSON")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 2: Check if measurement was saved to My Places (25 pts)
    # ================================================================
    measurement_info = result_data.get('measurement', {})
    measurement_found = measurement_info.get('found', False)
    measurement_name = measurement_info.get('name', '')
    measurement_coords_str = measurement_info.get('coordinates', '')
    
    if measurement_found and EXPECTED_MEASUREMENT_NAME in measurement_name:
        score += 25
        feedback_parts.append(f"✅ Measurement '{measurement_name}' saved to My Places")
        details['measurement_saved'] = True
    else:
        feedback_parts.append("❌ Measurement not found in My Places")
        details['measurement_saved'] = False
    
    # ================================================================
    # CRITERION 3: Verify measurement was created during task (15 pts)
    # ================================================================
    myplaces_info = result_data.get('myplaces', {})
    myplaces_modified = myplaces_info.get('modified_during_task', False)
    
    if myplaces_modified:
        score += 15
        feedback_parts.append("✅ My Places modified during task")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ My Places not modified during task")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 4: Check coordinates near target location (15 pts)
    # ================================================================
    coords_valid = False
    measurement_length = None
    
    if measurement_coords_str:
        coords = parse_kml_coordinates(measurement_coords_str)
        details['parsed_coordinates'] = coords
        
        if coords_near_target(coords, TARGET_LAT, TARGET_LON, COORD_TOLERANCE):
            score += 15
            coords_valid = True
            feedback_parts.append(f"✅ Measurement location near target ({TARGET_LAT}, {TARGET_LON})")
            
            # Estimate measurement length
            measurement_length = estimate_measurement_length(coords)
            if measurement_length:
                details['estimated_length_meters'] = round(measurement_length, 1)
                
                # Check if length is reasonable for Suez Canal width (150-400m)
                min_width = metadata.get('expected_width_meters_min', 150)
                max_width = metadata.get('expected_width_meters_max', 400)
                
                if min_width <= measurement_length <= max_width:
                    feedback_parts.append(f"✅ Measurement length ({measurement_length:.0f}m) in expected range")
                else:
                    feedback_parts.append(f"⚠️ Measurement length ({measurement_length:.0f}m) outside expected range ({min_width}-{max_width}m)")
        else:
            feedback_parts.append("⚠️ Measurement coordinates not near Suez Canal target")
    else:
        feedback_parts.append("⚠️ Could not parse measurement coordinates")
    
    details['coords_valid'] = coords_valid
    
    # ================================================================
    # CRITERION 5: Check configuration for metric units (15 pts)
    # ================================================================
    config_info = result_data.get('config', {})
    units_metric = config_info.get('units_metric', False)
    config_modified = config_info.get('modified_during_task', False)
    
    if units_metric:
        score += 15
        feedback_parts.append("✅ Metric units configured")
        details['metric_units'] = True
    elif config_modified:
        score += 5  # Partial credit for modifying config
        feedback_parts.append("⚠️ Config modified but metric units not confirmed")
        details['metric_units'] = False
    else:
        feedback_parts.append("❌ Metric units not configured")
        details['metric_units'] = False
    
    # ================================================================
    # CRITERION 6: VLM Trajectory Verification (15 pts)
    # ================================================================
    vlm_trajectory_score = 0
    
    if query_vlm:
        # Import trajectory frame sampling
        try:
            from gym_anything.vlm import sample_trajectory_frames
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            
            if trajectory_frames and len(trajectory_frames) > 0:
                vlm_traj_result = query_vlm(
                    prompt=TRAJECTORY_WORKFLOW_PROMPT,
                    images=trajectory_frames
                )
                details['vlm_trajectory_result'] = vlm_traj_result
                
                if vlm_traj_result.get('success'):
                    parsed = vlm_traj_result.get('parsed', {})
                    
                    # Count workflow stages observed
                    stages_seen = 0
                    if parsed.get('options_dialog_visible'):
                        stages_seen += 1
                    if parsed.get('settings_interaction'):
                        stages_seen += 1
                    if parsed.get('canal_navigation'):
                        stages_seen += 1
                    if parsed.get('ruler_tool_used'):
                        stages_seen += 1
                    if parsed.get('workflow_progression'):
                        stages_seen += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    conf_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_trajectory_score = int((stages_seen / 5) * 15 * conf_mult)
                    score += vlm_trajectory_score
                    
                    observations = parsed.get('observations', '')
                    if vlm_trajectory_score >= 10:
                        feedback_parts.append(f"✅ VLM trajectory: workflow progression observed ({stages_seen}/5 stages)")
                    else:
                        feedback_parts.append(f"⚠️ VLM trajectory: limited workflow evidence ({stages_seen}/5 stages)")
                    
                    details['vlm_trajectory_stages'] = stages_seen
                else:
                    feedback_parts.append("⚠️ VLM trajectory analysis failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            logger.warning("Could not import trajectory frame sampling")
            feedback_parts.append("⚠️ Trajectory frame sampling not available")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    details['vlm_trajectory_score'] = vlm_trajectory_score
    
    # ================================================================
    # CRITERION 7: VLM Final State Verification (15 pts)
    # ================================================================
    vlm_final_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                vlm_final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                details['vlm_final_result'] = vlm_final_result
                
                if vlm_final_result.get('success'):
                    parsed = vlm_final_result.get('parsed', {})
                    
                    criteria_met = 0
                    if parsed.get('is_google_earth'):
                        criteria_met += 1
                    if parsed.get('shows_suez_canal'):
                        criteria_met += 1
                    if parsed.get('measurement_visible'):
                        criteria_met += 1
                    if parsed.get('metric_units_shown'):
                        criteria_met += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    conf_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_final_score = int((criteria_met / 4) * 15 * conf_mult)
                    score += vlm_final_score
                    
                    if parsed.get('shows_suez_canal'):
                        feedback_parts.append("✅ VLM final: Suez Canal visible")
                    else:
                        feedback_parts.append("⚠️ VLM final: Suez Canal not clearly visible")
                    
                    if parsed.get('measurement_visible'):
                        feedback_parts.append("✅ VLM final: Measurement visible")
                    
                    details['vlm_final_criteria'] = criteria_met
                else:
                    feedback_parts.append("⚠️ VLM final state analysis failed")
            else:
                feedback_parts.append("⚠️ No final screenshot available for VLM")
        except ImportError:
            logger.warning("Could not import final screenshot function")
            feedback_parts.append("⚠️ Final screenshot function not available")
    
    details['vlm_final_score'] = vlm_final_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: measurement saved OR strong VLM evidence
    key_criteria_met = (
        (measurement_found and myplaces_modified) or
        (vlm_trajectory_score >= 10 and vlm_final_score >= 8)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }