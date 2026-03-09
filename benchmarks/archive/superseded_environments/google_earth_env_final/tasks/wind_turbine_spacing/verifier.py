#!/usr/bin/env python3
"""
Verifier for Wind Turbine Spacing Analysis task.

MULTI-SIGNAL VERIFICATION:
1. Output screenshot exists and created during task (15 pts)
2. Screenshot has valid content (10 pts)
3. Turbine placemarks created (40 pts total)
4. Placemarks are within London Array bounds (10 pts)
5. Placemark spacing is realistic for turbines (10 pts)
6. VLM trajectory verification - workflow completion (15 pts)

Pass threshold: 65 points with at least 2 placemarks created
"""

import json
import tempfile
import os
import logging
import math
from typing import Dict, Any, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wind_turbine_spacing(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent navigated to London Array and measured turbine spacing.
    
    Uses multiple independent signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_screenshot = metadata.get('expected_screenshot_path', '/home/ga/wind_farm_analysis.png')
    bounds = metadata.get('location_bounds', {
        'lat_min': 51.40, 'lat_max': 51.65,
        'lon_min': 1.10, 'lon_max': 1.70
    })
    spacing_min = metadata.get('expected_spacing_min_m', 500)
    spacing_max = metadata.get('expected_spacing_max_m', 900)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
        details['result_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output screenshot exists and created during task (15 pts)
    # ================================================================
    output_info = result.get('output_screenshot', {})
    output_exists = output_info.get('exists', False)
    created_during_task = output_info.get('created_during_task', False)
    output_size = output_info.get('size_bytes', 0)
    
    if output_exists and created_during_task:
        score += 15
        feedback_parts.append(f"✅ Output screenshot created during task ({output_size} bytes)")
        details['screenshot_valid'] = True
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot exists but may predate task ({output_size} bytes)")
        details['screenshot_valid'] = False
    else:
        feedback_parts.append("❌ Output screenshot not found")
        details['screenshot_valid'] = False
    
    # ================================================================
    # CRITERION 2: Screenshot has valid content (10 pts)
    # ================================================================
    if output_exists and output_size > 50000:  # > 50KB suggests real content
        score += 10
        feedback_parts.append("✅ Screenshot file size indicates real content")
        details['screenshot_size_ok'] = True
    elif output_exists and output_size > 10000:
        score += 5
        feedback_parts.append("⚠️ Screenshot is small but may be valid")
        details['screenshot_size_ok'] = False
    else:
        if output_exists:
            feedback_parts.append("❌ Screenshot file too small (likely invalid)")
        details['screenshot_size_ok'] = False
    
    # ================================================================
    # CRITERION 3: Turbine placemarks created (40 pts total)
    # ================================================================
    myplaces_info = result.get('myplaces', {})
    placemark_data = myplaces_info.get('placemark_data', [])
    turbine_count = myplaces_info.get('turbine_placemarks_found', 0)
    new_placemarks = myplaces_info.get('new_placemarks', 0)
    myplaces_modified = myplaces_info.get('modified', False)
    
    # Parse placemark data if it's a string
    if isinstance(placemark_data, str):
        try:
            placemark_data = json.loads(placemark_data)
        except:
            placemark_data = []
    
    details['placemark_data'] = placemark_data
    details['turbine_count'] = turbine_count
    
    # Score based on turbine placemarks found
    if turbine_count >= 3:
        score += 40
        feedback_parts.append(f"✅ All 3 turbine placemarks created")
    elif turbine_count == 2:
        score += 30
        feedback_parts.append(f"⚠️ Only 2 turbine placemarks found (need 3)")
    elif turbine_count == 1:
        score += 15
        feedback_parts.append(f"⚠️ Only 1 turbine placemark found (need 3)")
    elif new_placemarks > 0:
        score += 5
        feedback_parts.append(f"⚠️ Placemarks created but not named 'Turbine X'")
    else:
        feedback_parts.append("❌ No turbine placemarks found")
    
    # ================================================================
    # CRITERION 4: Placemarks within London Array bounds (10 pts)
    # ================================================================
    placemarks_in_bounds = 0
    for pm in placemark_data:
        coords = pm.get('coords')
        if coords:
            lat = coords.get('lat', 0)
            lon = coords.get('lon', 0)
            if (bounds['lat_min'] <= lat <= bounds['lat_max'] and
                bounds['lon_min'] <= lon <= bounds['lon_max']):
                placemarks_in_bounds += 1
    
    details['placemarks_in_bounds'] = placemarks_in_bounds
    
    if placemarks_in_bounds >= 2:
        score += 10
        feedback_parts.append(f"✅ Placemarks located within London Array area ({placemarks_in_bounds}/3)")
    elif placemarks_in_bounds == 1:
        score += 5
        feedback_parts.append(f"⚠️ Only 1 placemark in correct area")
    else:
        if turbine_count > 0:
            feedback_parts.append("❌ Placemarks not in London Array area")
    
    # ================================================================
    # CRITERION 5: Placemark spacing is realistic (10 pts)
    # ================================================================
    spacing_score, spacing_feedback = check_placemark_spacing(placemark_data, spacing_min, spacing_max)
    score += spacing_score
    if spacing_feedback:
        feedback_parts.append(spacing_feedback)
    details['spacing_score'] = spacing_score
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (15 pts)
    # ================================================================
    vlm_score, vlm_feedback = verify_via_vlm(traj, env_info, copy_from_env)
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Final scoring
    # ================================================================
    # Cap score at 100
    score = min(score, 100)
    
    # Key criteria: at least some placemarks created AND (screenshot OR VLM evidence)
    key_criteria_met = (turbine_count >= 2 or new_placemarks >= 2) and (output_exists or vlm_score >= 5)
    passed = score >= 65 and key_criteria_met
    
    # Build final feedback
    final_feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": details
    }


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates in meters."""
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def check_placemark_spacing(placemark_data: List[Dict], min_spacing: float, max_spacing: float) -> Tuple[int, str]:
    """Check if spacing between turbine placemarks is realistic."""
    if not placemark_data or len(placemark_data) < 2:
        return 0, ""
    
    # Get placemarks with valid coordinates
    valid_placemarks = []
    for pm in placemark_data:
        coords = pm.get('coords')
        if coords and coords.get('lat') and coords.get('lon'):
            valid_placemarks.append(pm)
    
    if len(valid_placemarks) < 2:
        return 0, ""
    
    # Calculate distances between consecutive placemarks
    distances = []
    for i in range(len(valid_placemarks) - 1):
        c1 = valid_placemarks[i]['coords']
        c2 = valid_placemarks[i + 1]['coords']
        dist = haversine_distance(c1['lat'], c1['lon'], c2['lat'], c2['lon'])
        distances.append(dist)
    
    # Check if any distance is in the expected range
    valid_spacings = [d for d in distances if min_spacing <= d <= max_spacing]
    
    if valid_spacings:
        avg_spacing = sum(valid_spacings) / len(valid_spacings)
        return 10, f"✅ Turbine spacing ~{avg_spacing:.0f}m (realistic)"
    elif distances:
        avg_dist = sum(distances) / len(distances)
        if avg_dist < min_spacing:
            return 3, f"⚠️ Placemarks too close together (~{avg_dist:.0f}m)"
        else:
            return 3, f"⚠️ Placemarks too far apart (~{avg_dist:.0f}m)"
    
    return 0, ""


def verify_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any], copy_from_env) -> Tuple[int, str]:
    """Use VLM to verify the task was completed via trajectory analysis."""
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return 0, "⚠️ VLM not available"
    
    # Try to get trajectory frames
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory (captures workflow progression)
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if final_frame and final_frame not in frames:
            frames.append(final_frame)
        
        if not frames:
            # Fallback: try to copy final screenshot from container
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                    frames = [temp_screenshot.name]
            except:
                pass
            finally:
                # Don't delete yet, VLM needs it
                pass
        
        if not frames:
            return 0, "⚠️ No trajectory frames available for VLM"
        
    except ImportError:
        # Fallback without gym_anything.vlm
        frames = []
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/task_final.png", temp_screenshot.name)
            if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                frames = [temp_screenshot.name]
        except:
            return 0, "⚠️ Could not load screenshots for VLM"
    
    # VLM prompt for trajectory/final verification
    vlm_prompt = """You are verifying if a computer agent completed a wind turbine spacing analysis task in Google Earth.

TASK: Navigate to London Array offshore wind farm (Thames Estuary, UK), place placemarks on turbines, and measure the spacing between them.

Analyze these screenshots and determine:

1. GOOGLE_EARTH_VISIBLE: Is this Google Earth showing satellite imagery?

2. OFFSHORE_WIND_FARM_VISIBLE: Can you see an offshore wind farm? Look for:
   - Grid pattern of white dots/structures on water (turbines)
   - Open sea/ocean with regular array of objects
   - Thames Estuary or UK coastline nearby

3. PLACEMARKS_VISIBLE: Are there placemarks/markers placed on the map?
   - Yellow pushpin icons or custom markers
   - Labels like "Turbine 1", "Turbine 2", etc.

4. MEASUREMENT_TOOL_VISIBLE: Is there evidence of measurement?
   - Ruler/path line between points
   - Distance measurement overlay/popup
   - Measurement dialog or results

5. WORKFLOW_EVIDENCE: Does this show task completion?
   - Navigation occurred (not just default view)
   - Multiple placemarks placed
   - Measurement performed

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "offshore_wind_farm_visible": true/false,
    "placemarks_visible": true/false,
    "measurement_tool_visible": true/false,
    "workflow_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
    
    try:
        # Query VLM with trajectory frames
        if len(frames) > 1:
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        else:
            vlm_result = query_vlm(prompt=vlm_prompt, image=frames[0])
        
        if not vlm_result.get("success"):
            return 0, f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}"
        
        parsed = vlm_result.get("parsed", {})
        
        # Score based on VLM findings
        vlm_score = 0
        findings = []
        
        if parsed.get("google_earth_visible"):
            vlm_score += 3
            findings.append("GE")
        
        if parsed.get("offshore_wind_farm_visible"):
            vlm_score += 5
            findings.append("WindFarm")
        
        if parsed.get("placemarks_visible"):
            vlm_score += 4
            findings.append("Placemarks")
        
        if parsed.get("measurement_tool_visible"):
            vlm_score += 3
            findings.append("Measurement")
        
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            vlm_score = int(vlm_score * 0.7)
        elif confidence == "medium":
            vlm_score = int(vlm_score * 0.85)
        
        # Cap at 15
        vlm_score = min(vlm_score, 15)
        
        if findings:
            return vlm_score, f"VLM: {'+'.join(findings)} ({confidence} confidence)"
        else:
            return 0, "VLM: Task completion not visually confirmed"
        
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return 0, f"⚠️ VLM error: {str(e)[:50]}"


# Allow running as standalone script for testing
if __name__ == "__main__":
    print("Wind Turbine Spacing verifier - run via framework")