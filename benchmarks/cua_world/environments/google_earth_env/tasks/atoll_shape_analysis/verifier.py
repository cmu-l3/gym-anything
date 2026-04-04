#!/usr/bin/env python3
"""
Verifier for Bora Bora Atoll Shape Index Analysis task.

VERIFICATION STRATEGY:
1. Output file exists and created during task (15 points)
2. Area measurement within valid range (20 points)
3. Perimeter measurement within valid range (20 points)
4. Polsby-Popper calculation correct (20 points)
5. Polygon saved to My Places (10 points)
6. VLM trajectory verification (15 points)

Pass threshold: 60 points with file created during task

Uses copy_from_env (NOT exec_in_env) and trajectory-based VLM verification.
"""

import json
import tempfile
import os
import re
import math
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_atoll_shape_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Bora Bora shape index analysis task completion.
    
    Uses multiple independent verification signals:
    1. File-based: Output file with measurements
    2. Calculation: Polsby-Popper formula verification
    3. KML: Polygon saved to My Places
    4. VLM: Trajectory shows correct workflow
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ copy_from_env function not available"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_area_min = metadata.get('expected_area_min', 25)
    expected_area_max = metadata.get('expected_area_max', 38)
    expected_perimeter_min = metadata.get('expected_perimeter_min', 25)
    expected_perimeter_max = metadata.get('expected_perimeter_max', 45)
    expected_pp_min = metadata.get('expected_pp_score_min', 0.25)
    expected_pp_max = metadata.get('expected_pp_score_max', 0.55)
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_json'] = result
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        details['result_json_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy and parse output file directly
    # ================================================================
    output_content = ""
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/bora_bora_shape_analysis.txt", temp_output.name)
        with open(temp_output.name, 'r') as f:
            output_content = f.read()
        details['output_content'] = output_content
    except Exception as e:
        logger.warning(f"Could not read output file: {e}")
        details['output_file_error'] = str(e)
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
    
    # ================================================================
    # CRITERION 1: Output file exists and created during task (15 pts)
    # ================================================================
    output_info = result.get('output_file', {})
    file_exists = output_info.get('exists', False) or bool(output_content)
    file_created_during_task = output_info.get('created_during_task', False)
    
    if file_exists and file_created_during_task:
        score += 15
        feedback_parts.append("✅ Output file created during task (+15)")
    elif file_exists:
        score += 5
        feedback_parts.append("⚠️ Output file exists but may predate task (+5)")
    else:
        feedback_parts.append("❌ Output file not found (+0)")
        # Early return if no output
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Parse measurements from output content
    # ================================================================
    area_value = None
    perimeter_value = None
    pp_score_value = None
    
    # Try parsing from file content
    if output_content:
        # Area
        area_match = re.search(r'Area:\s*([\d.]+)\s*(?:sq\s*)?km', output_content, re.I)
        if area_match:
            try:
                area_value = float(area_match.group(1))
            except ValueError:
                pass
        
        # Perimeter
        perim_match = re.search(r'Perimeter:\s*([\d.]+)\s*km', output_content, re.I)
        if perim_match:
            try:
                perimeter_value = float(perim_match.group(1))
            except ValueError:
                pass
        
        # Polsby-Popper score
        pp_match = re.search(r'(?:Polsby|compactness|score)[^:]*:\s*([\d.]+)', output_content, re.I)
        if pp_match:
            try:
                pp_score_value = float(pp_match.group(1))
            except ValueError:
                pass
    
    # Fallback to parsed values from export script
    if area_value is None:
        measurements = result.get('measurements', {})
        area_value = measurements.get('area_sq_km', 0)
        if area_value == 0:
            area_value = None
    
    if perimeter_value is None:
        measurements = result.get('measurements', {})
        perimeter_value = measurements.get('perimeter_km', 0)
        if perimeter_value == 0:
            perimeter_value = None
    
    if pp_score_value is None:
        measurements = result.get('measurements', {})
        pp_score_value = measurements.get('polsby_popper_score', 0)
        if pp_score_value == 0:
            pp_score_value = None
    
    details['parsed_measurements'] = {
        'area': area_value,
        'perimeter': perimeter_value,
        'pp_score': pp_score_value
    }
    
    # ================================================================
    # CRITERION 2: Area measurement within valid range (20 pts)
    # ================================================================
    if area_value is not None:
        if expected_area_min <= area_value <= expected_area_max:
            score += 20
            feedback_parts.append(f"✅ Area {area_value:.2f} sq km within expected range (+20)")
        elif 15 <= area_value <= 50:
            score += 10
            feedback_parts.append(f"⚠️ Area {area_value:.2f} sq km plausible but outside expected range (+10)")
        else:
            score += 3
            feedback_parts.append(f"❌ Area {area_value:.2f} sq km seems incorrect (+3)")
    else:
        feedback_parts.append("❌ Area measurement not found (+0)")
    
    # ================================================================
    # CRITERION 3: Perimeter measurement within valid range (20 pts)
    # ================================================================
    if perimeter_value is not None:
        if expected_perimeter_min <= perimeter_value <= expected_perimeter_max:
            score += 20
            feedback_parts.append(f"✅ Perimeter {perimeter_value:.2f} km within expected range (+20)")
        elif 15 <= perimeter_value <= 60:
            score += 10
            feedback_parts.append(f"⚠️ Perimeter {perimeter_value:.2f} km plausible but outside expected range (+10)")
        else:
            score += 3
            feedback_parts.append(f"❌ Perimeter {perimeter_value:.2f} km seems incorrect (+3)")
    else:
        feedback_parts.append("❌ Perimeter measurement not found (+0)")
    
    # ================================================================
    # CRITERION 4: Polsby-Popper calculation correct (20 pts)
    # ================================================================
    if pp_score_value is not None and area_value is not None and perimeter_value is not None:
        # Calculate expected PP score
        expected_pp = (4 * math.pi * area_value) / (perimeter_value ** 2) if perimeter_value > 0 else 0
        calculation_error = abs(pp_score_value - expected_pp)
        
        details['calculation_check'] = {
            'reported_pp': pp_score_value,
            'expected_pp': expected_pp,
            'error': calculation_error
        }
        
        if calculation_error < 0.02:
            score += 20
            feedback_parts.append(f"✅ Polsby-Popper calculation correct: {pp_score_value:.3f} (+20)")
        elif calculation_error < 0.05:
            score += 15
            feedback_parts.append(f"⚠️ Polsby-Popper approximately correct: {pp_score_value:.3f} vs expected {expected_pp:.3f} (+15)")
        elif calculation_error < 0.10:
            score += 8
            feedback_parts.append(f"⚠️ Polsby-Popper has minor errors: {pp_score_value:.3f} vs expected {expected_pp:.3f} (+8)")
        else:
            score += 3
            feedback_parts.append(f"❌ Polsby-Popper calculation incorrect: {pp_score_value:.3f} vs expected {expected_pp:.3f} (+3)")
    elif pp_score_value is not None:
        # Can't verify calculation without area/perimeter, but value exists
        if expected_pp_min <= pp_score_value <= expected_pp_max:
            score += 12
            feedback_parts.append(f"⚠️ Polsby-Popper score {pp_score_value:.3f} in expected range (cannot verify calculation) (+12)")
        else:
            score += 5
            feedback_parts.append(f"⚠️ Polsby-Popper score {pp_score_value:.3f} present but outside expected range (+5)")
    else:
        feedback_parts.append("❌ Polsby-Popper score not found (+0)")
    
    # ================================================================
    # CRITERION 5: Polygon saved to My Places (10 pts)
    # ================================================================
    myplaces_info = result.get('myplaces', {})
    polygon_saved = myplaces_info.get('polygon_saved', False)
    polygon_name_correct = myplaces_info.get('polygon_name_correct', False)
    has_polygon_element = myplaces_info.get('has_polygon_element', False)
    myplaces_modified = myplaces_info.get('modified_during_task', False)
    
    # Also try to verify by copying myplaces.kml
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/home/ga/.googleearth/myplaces.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read().lower()
        
        if 'bora' in kml_content:
            polygon_saved = True
            if 'bora bora main island' in kml_content:
                polygon_name_correct = True
            if '<polygon>' in kml_content or '<coordinates>' in kml_content:
                has_polygon_element = True
    except Exception as e:
        logger.debug(f"Could not read myplaces.kml: {e}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    if polygon_saved and polygon_name_correct and has_polygon_element:
        score += 10
        feedback_parts.append("✅ Polygon saved to My Places with correct name (+10)")
    elif polygon_saved and has_polygon_element:
        score += 7
        feedback_parts.append("⚠️ Polygon saved but name may be different (+7)")
    elif polygon_saved:
        score += 5
        feedback_parts.append("⚠️ Bora Bora entry found in My Places (+5)")
    elif myplaces_modified:
        score += 2
        feedback_parts.append("⚠️ My Places was modified (+2)")
    else:
        feedback_parts.append("❌ Polygon not saved to My Places (+0)")
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (15 pts)
    # ================================================================
    vlm_score = 0
    if query_vlm:
        vlm_score = _verify_with_vlm(traj, query_vlm, details)
        score += vlm_score
        if vlm_score >= 12:
            feedback_parts.append(f"✅ VLM verification: workflow confirmed (+{vlm_score})")
        elif vlm_score >= 6:
            feedback_parts.append(f"⚠️ VLM verification: partial workflow (+{vlm_score})")
        else:
            feedback_parts.append(f"❌ VLM verification: workflow not confirmed (+{vlm_score})")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification (+0)")
    
    # ================================================================
    # Determine pass/fail
    # ================================================================
    # Must have: file created during task AND at least one valid measurement
    key_criteria_met = file_created_during_task and (
        (area_value is not None and expected_area_min <= area_value <= expected_area_max) or
        (perimeter_value is not None and expected_perimeter_min <= perimeter_value <= expected_perimeter_max)
    )
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


def _verify_with_vlm(traj: Dict[str, Any], query_vlm, details: Dict[str, Any]) -> int:
    """
    Use VLM to verify trajectory shows correct workflow.
    
    Checks multiple trajectory frames (NOT just final screenshot).
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("gym_anything.vlm not available")
        return 0
    
    vlm_score = 0
    
    # Sample frames from trajectory
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if final_frame and final_frame not in frames:
            frames.append(final_frame)
        
        if not frames:
            details['vlm_error'] = "No trajectory frames available"
            return 0
        
        details['vlm_frames_count'] = len(frames)
    except Exception as e:
        logger.warning(f"Error sampling trajectory: {e}")
        details['vlm_error'] = str(e)
        return 0
    
    # VLM prompt for trajectory verification
    trajectory_prompt = """You are verifying a computer agent's work in Google Earth Pro.

TASK: The agent should have:
1. Navigated to Bora Bora, French Polynesia (a Pacific island)
2. Created a polygon tracing the main island coastline
3. Measured the polygon's area and perimeter
4. Potentially viewed measurement data

Analyze these chronological screenshots and determine:

1. LOCATION_CORRECT: Do any frames show Bora Bora or a Pacific island atoll (lagoon surrounded by reef with central volcanic island)?
2. POLYGON_VISIBLE: Do any frames show a polygon being drawn or already drawn on the island?
3. MEASUREMENT_ACTIVITY: Is there evidence of using measurement tools or viewing polygon properties?
4. GOOGLE_EARTH_CONFIRMED: Are these clearly Google Earth Pro screenshots (satellite imagery, toolbar)?

Respond in JSON format:
{
    "location_correct": true/false,
    "polygon_visible": true/false,
    "measurement_activity": true/false,
    "google_earth_confirmed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see in the frames"
}
"""
    
    try:
        vlm_result = query_vlm(
            prompt=trajectory_prompt,
            images=frames
        )
        
        details['vlm_result'] = vlm_result
        
        if not vlm_result.get('success'):
            details['vlm_error'] = vlm_result.get('error', 'Unknown VLM error')
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Score based on criteria
        location_correct = parsed.get('location_correct', False)
        polygon_visible = parsed.get('polygon_visible', False)
        measurement_activity = parsed.get('measurement_activity', False)
        ge_confirmed = parsed.get('google_earth_confirmed', False)
        confidence = parsed.get('confidence', 'low')
        
        # Calculate VLM score (max 15 points)
        if ge_confirmed:
            vlm_score += 3
        if location_correct:
            vlm_score += 4
        if polygon_visible:
            vlm_score += 4
        if measurement_activity:
            vlm_score += 4
        
        # Adjust for confidence
        if confidence == 'low':
            vlm_score = int(vlm_score * 0.7)
        elif confidence == 'medium':
            vlm_score = int(vlm_score * 0.85)
        
        details['vlm_criteria'] = {
            'location_correct': location_correct,
            'polygon_visible': polygon_visible,
            'measurement_activity': measurement_activity,
            'google_earth_confirmed': ge_confirmed,
            'confidence': confidence,
            'raw_score': vlm_score
        }
        
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
        details['vlm_error'] = str(e)
        return 0
    
    return min(vlm_score, 15)  # Cap at 15 points