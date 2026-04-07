#!/usr/bin/env python3
"""
Verifier for Wallace Creek Fault Offset Measurement task.

VERIFICATION STRATEGY (Multi-signal approach):
1. KML file exists at expected path (15 points)
2. File was created DURING task - anti-gaming (15 points)
3. Valid KML structure with placemark (10 points)
4. Placemark correctly named "Wallace Creek Offset" (10 points)
5. Coordinates near Wallace Creek (35.2715°N, 119.8272°W) (20 points)
6. Measurement value in valid range (110-150m) (20 points)
7. VLM trajectory verification - workflow progression (10 points)

Pass threshold: 70 points with KML exists AND measurement documented
"""

import json
import tempfile
import os
import re
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_wallace_creek_offset(traj, env_info, task_info):
    """
    Verify Wallace Creek fault offset measurement task completion.
    
    Uses copy_from_env to retrieve results from container.
    Uses trajectory frames for VLM verification.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info including copy_from_env function
        task_info: Task metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    # Get metadata with defaults
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 35.2715)
    target_lon = metadata.get('target_longitude', -119.8272)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.01)
    min_offset = metadata.get('min_offset_meters', 110)
    max_offset = metadata.get('max_offset_meters', 150)
    optimal_min = metadata.get('optimal_min_meters', 120)
    optimal_max = metadata.get('optimal_max_meters', 140)
    expected_name = metadata.get('expected_placemark_name', 'Wallace Creek Offset')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # RETRIEVE TASK RESULT FROM CONTAINER
    # ================================================================
    result = None
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        details['result_retrieved'] = True
    except Exception as e:
        logger.error(f"Failed to retrieve task result: {e}")
        details['result_retrieved'] = False
        details['retrieval_error'] = str(e)
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Could not retrieve task result from container",
            "details": details
        }
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    kml_exists = result.get('kml_exists', False)
    details['kml_exists'] = kml_exists
    
    if kml_exists:
        score += 15
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found at expected path")
        # Early exit - nothing else to check meaningfully
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - ANTI-GAMING (15 points)
    # ================================================================
    file_created_during_task = result.get('kml_created_during_task', False)
    details['file_created_during_task'] = file_created_during_task
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("⚠️ File timestamp issue (possible pre-existing file)")
        # Don't fail completely, but this is suspicious
    
    # ================================================================
    # CRITERION 3: Valid KML structure (10 points)
    # ================================================================
    parse_success = result.get('kml_parse_success', False)
    placemark_name = result.get('placemark_name', '')
    details['parse_success'] = parse_success
    details['placemark_name'] = placemark_name
    
    if parse_success and placemark_name:
        score += 10
        feedback_parts.append("✅ Valid KML with placemark")
    elif parse_success:
        score += 5
        feedback_parts.append("⚠️ KML parsed but no placemark name found")
    else:
        feedback_parts.append("❌ KML parsing failed")
    
    # ================================================================
    # CRITERION 4: Placemark correctly named (10 points)
    # ================================================================
    name_correct = False
    if placemark_name:
        # Flexible matching - must contain "wallace" and "creek" or "offset"
        name_lower = placemark_name.lower()
        if "wallace" in name_lower and ("creek" in name_lower or "offset" in name_lower):
            name_correct = True
        elif expected_name.lower() in name_lower:
            name_correct = True
    
    details['name_correct'] = name_correct
    
    if name_correct:
        score += 10
        feedback_parts.append(f"✅ Placemark named correctly: '{placemark_name}'")
    else:
        feedback_parts.append(f"❌ Placemark name incorrect: '{placemark_name}' (expected similar to 'Wallace Creek Offset')")
    
    # ================================================================
    # CRITERION 5: Coordinates accurate (20 points)
    # ================================================================
    placemark_lat = result.get('placemark_lat', 0)
    placemark_lon = result.get('placemark_lon', 0)
    details['placemark_lat'] = placemark_lat
    details['placemark_lon'] = placemark_lon
    
    lat_diff = abs(placemark_lat - target_lat)
    lon_diff = abs(placemark_lon - target_lon)
    coords_accurate = lat_diff <= coord_tolerance and lon_diff <= coord_tolerance
    coords_nearby = lat_diff <= coord_tolerance * 5 and lon_diff <= coord_tolerance * 5
    
    details['lat_diff'] = lat_diff
    details['lon_diff'] = lon_diff
    details['coords_accurate'] = coords_accurate
    
    if coords_accurate:
        score += 20
        feedback_parts.append(f"✅ Coordinates accurate ({placemark_lat:.4f}, {placemark_lon:.4f})")
    elif coords_nearby:
        score += 10
        feedback_parts.append(f"⚠️ Coordinates near target ({placemark_lat:.4f}, {placemark_lon:.4f})")
    elif placemark_lat != 0 and placemark_lon != 0:
        score += 5
        feedback_parts.append(f"❌ Coordinates far from Wallace Creek ({placemark_lat:.4f}, {placemark_lon:.4f})")
    else:
        feedback_parts.append("❌ No valid coordinates found")
    
    # ================================================================
    # CRITERION 6: Measurement in valid range (20 points)
    # ================================================================
    measurement_value = result.get('measurement_value')
    details['measurement_value'] = measurement_value
    
    measurement_valid = False
    measurement_optimal = False
    
    if measurement_value is not None:
        try:
            measurement_float = float(measurement_value)
            if min_offset <= measurement_float <= max_offset:
                measurement_valid = True
                if optimal_min <= measurement_float <= optimal_max:
                    measurement_optimal = True
        except (ValueError, TypeError):
            pass
    
    details['measurement_valid'] = measurement_valid
    details['measurement_optimal'] = measurement_optimal
    
    if measurement_optimal:
        score += 20
        feedback_parts.append(f"✅ Measurement excellent: {measurement_value}m (optimal range)")
    elif measurement_valid:
        score += 15
        feedback_parts.append(f"✅ Measurement acceptable: {measurement_value}m")
    elif measurement_value is not None:
        score += 5
        feedback_parts.append(f"⚠️ Measurement out of range: {measurement_value}m (expected 110-150m)")
    else:
        feedback_parts.append("❌ No measurement value found in description")
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Import VLM utilities
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            except ImportError:
                # Fallback if module not available
                sample_trajectory_frames = None
                get_final_screenshot = None
            
            frames = []
            
            # Get trajectory frames (preferred)
            if sample_trajectory_frames:
                try:
                    frames = sample_trajectory_frames(traj, n=5)
                except:
                    pass
            
            # Get final screenshot as fallback
            if get_final_screenshot and len(frames) == 0:
                try:
                    final = get_final_screenshot(traj)
                    if final:
                        frames = [final]
                except:
                    pass
            
            if frames:
                # VLM verification prompt
                vlm_prompt = """Analyze these screenshots from a Google Earth task to measure the Wallace Creek fault offset.

The user should have:
1. Navigated to Carrizo Plain, California (arid terrain with visible fault trace)
2. Used the Ruler tool to measure a stream channel offset
3. Created a placemark at the fault location

Look for evidence of:
- Aerial/satellite view of arid California terrain
- A visible linear fault trace or offset stream pattern  
- The Ruler tool being used (measurement line visible)
- A placemark being created or saved
- The Save dialog for KML export

Respond in JSON format:
{
    "carrizo_plain_visible": true/false,
    "ruler_tool_used": true/false,
    "placemark_visible": true/false,
    "fault_features_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=frames if len(frames) > 1 else None,
                    image=frames[0] if len(frames) == 1 else None
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_criteria = 0
                    if parsed.get('carrizo_plain_visible'):
                        vlm_criteria += 1
                    if parsed.get('ruler_tool_used'):
                        vlm_criteria += 1
                    if parsed.get('placemark_visible'):
                        vlm_criteria += 1
                    if parsed.get('fault_features_visible'):
                        vlm_criteria += 1
                    if parsed.get('workflow_progression'):
                        vlm_criteria += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_score = int((vlm_criteria / 5) * 10 * confidence_mult)
                    vlm_feedback = f"VLM: {vlm_criteria}/5 criteria ({confidence} confidence)"
                else:
                    vlm_feedback = f"VLM query failed: {vlm_result.get('error', 'unknown')}"
            else:
                vlm_feedback = "No trajectory frames available for VLM"
        else:
            vlm_feedback = "VLM verification not available"
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_feedback = f"VLM error: {str(e)}"
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    feedback_parts.append(f"{'✅' if vlm_score >= 5 else '⚠️'} {vlm_feedback}")
    
    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    details['total_score'] = score
    details['max_score'] = 100
    
    # Key criteria: KML exists AND (measurement documented OR coordinates accurate)
    key_criteria_met = kml_exists and (measurement_valid or coords_accurate)
    details['key_criteria_met'] = key_criteria_met
    
    # Pass threshold: 70+ points AND key criteria
    passed = score >= 70 and key_criteria_met
    
    if passed:
        feedback_parts.append(f"🎉 PASSED with score {score}/100")
    else:
        if score < 70:
            feedback_parts.append(f"❌ FAILED: Score {score}/100 below threshold (70)")
        if not key_criteria_met:
            feedback_parts.append("❌ FAILED: Missing key criteria (valid measurement or coordinates)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }