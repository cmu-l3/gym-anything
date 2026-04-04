#!/usr/bin/env python3
"""
Verifier for sf_map_overlay_rotation task.

TASK: Create a ground overlay in Google Earth Pro using a historical 1906 
San Francisco map, rotate it 9-11 degrees to align with modern streets, 
and set transparency to 50-60%.

VERIFICATION STRATEGY (Multi-signal):
1. KMZ file exists and was created during task (15 pts)
2. Contains GroundOverlay element (15 pts)
3. Overlay name is correct (10 pts)
4. Rotation is in expected range 8-12 degrees (20 pts)
5. Opacity/transparency is in expected range 35-65% (15 pts)
6. Location bounds are in San Francisco area (10 pts)
7. VLM: Trajectory shows overlay creation workflow (15 pts)

Pass threshold: 60 points with rotation OR opacity criterion met
"""

import json
import tempfile
import os
import logging
import zipfile
import xml.etree.ElementTree as ET
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sf_map_overlay_rotation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the historical map overlay was created with correct parameters.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - Programmatic: KMZ file analysis
    - Temporal: File timestamp validation
    - Visual: VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/sf_overlay.kmz')
    expected_rotation_min = metadata.get('expected_rotation_min', 8)
    expected_rotation_max = metadata.get('expected_rotation_max', 12)
    expected_opacity_min = metadata.get('expected_opacity_min', 0.35)
    expected_opacity_max = metadata.get('expected_opacity_max', 0.65)
    target_lat_min = metadata.get('target_lat_min', 37.76)
    target_lat_max = metadata.get('target_lat_max', 37.81)
    target_lon_min = metadata.get('target_lon_min', -122.43)
    target_lon_max = metadata.get('target_lon_max', -122.38)
    
    feedback_parts = []
    result_details = {}
    score = 0
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KMZ file exists and was created during task (15 pts)
    # ================================================================
    kmz_exists = result.get('kmz_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    kmz_size = result.get('kmz_size_bytes', 0)
    
    if kmz_exists and file_created_during_task:
        score += 15
        feedback_parts.append(f"✅ KMZ file created during task ({kmz_size} bytes)")
        result_details['kmz_created'] = True
    elif kmz_exists:
        score += 5
        feedback_parts.append("⚠️ KMZ exists but not created during task")
        result_details['kmz_created'] = False
    else:
        feedback_parts.append("❌ KMZ file not found")
        result_details['kmz_created'] = False
        # Early exit - can't verify further without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: Contains GroundOverlay element (15 pts)
    # ================================================================
    has_ground_overlay = result.get('has_ground_overlay', False)
    
    if has_ground_overlay:
        score += 15
        feedback_parts.append("✅ GroundOverlay element present")
        result_details['has_overlay'] = True
    else:
        feedback_parts.append("❌ No GroundOverlay in KMZ")
        result_details['has_overlay'] = False
    
    # ================================================================
    # CRITERION 3: Overlay name is correct (10 pts)
    # ================================================================
    overlay_name = result.get('overlay_name', '')
    expected_name_keywords = ['sf', '1906', 'historical', 'map']
    
    name_match_count = sum(1 for kw in expected_name_keywords if kw.lower() in overlay_name.lower())
    
    if name_match_count >= 3 or 'SF 1906 Historical Map' in overlay_name:
        score += 10
        feedback_parts.append(f"✅ Correct overlay name: '{overlay_name}'")
        result_details['name_correct'] = True
    elif name_match_count >= 1:
        score += 5
        feedback_parts.append(f"⚠️ Partial name match: '{overlay_name}'")
        result_details['name_correct'] = False
    else:
        feedback_parts.append(f"❌ Incorrect name: '{overlay_name}'")
        result_details['name_correct'] = False
    
    # ================================================================
    # CRITERION 4: Rotation is in expected range (20 pts)
    # ================================================================
    rotation_str = result.get('rotation_value', '')
    rotation_correct = False
    rotation_value = None
    
    try:
        if rotation_str:
            rotation_value = float(rotation_str)
            result_details['rotation_value'] = rotation_value
            
            # Accept positive or negative rotation in the expected range
            # Google Earth may use different conventions
            abs_rotation = abs(rotation_value)
            if expected_rotation_min <= abs_rotation <= expected_rotation_max:
                rotation_correct = True
                score += 20
                feedback_parts.append(f"✅ Rotation correct: {rotation_value}°")
            elif expected_rotation_min - 3 <= abs_rotation <= expected_rotation_max + 3:
                # Close but not exact
                score += 10
                feedback_parts.append(f"⚠️ Rotation close: {rotation_value}° (expected {expected_rotation_min}-{expected_rotation_max}°)")
            else:
                feedback_parts.append(f"❌ Rotation out of range: {rotation_value}° (expected {expected_rotation_min}-{expected_rotation_max}°)")
        else:
            feedback_parts.append("❌ No rotation value found")
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"❌ Invalid rotation value: {rotation_str}")
    
    result_details['rotation_correct'] = rotation_correct
    
    # ================================================================
    # CRITERION 5: Opacity/transparency is in expected range (15 pts)
    # ================================================================
    opacity_str = result.get('opacity_value', '')
    opacity_correct = False
    opacity_value = None
    
    try:
        if opacity_str:
            opacity_value = float(opacity_str)
            result_details['opacity_value'] = opacity_value
            
            if expected_opacity_min <= opacity_value <= expected_opacity_max:
                opacity_correct = True
                score += 15
                feedback_parts.append(f"✅ Opacity correct: {opacity_value:.2f}")
            elif expected_opacity_min - 0.1 <= opacity_value <= expected_opacity_max + 0.1:
                score += 8
                feedback_parts.append(f"⚠️ Opacity close: {opacity_value:.2f} (expected {expected_opacity_min}-{expected_opacity_max})")
            else:
                feedback_parts.append(f"❌ Opacity out of range: {opacity_value:.2f} (expected {expected_opacity_min}-{expected_opacity_max})")
        else:
            # Check if there's any color value - some opacity is better than none
            feedback_parts.append("⚠️ No explicit opacity value found")
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"❌ Invalid opacity value: {opacity_str}")
    
    result_details['opacity_correct'] = opacity_correct
    
    # ================================================================
    # CRITERION 6: Location bounds are in San Francisco area (10 pts)
    # ================================================================
    location_correct = False
    
    try:
        north = result.get('north_bound', '')
        south = result.get('south_bound', '')
        east = result.get('east_bound', '')
        west = result.get('west_bound', '')
        
        if north and south and east and west:
            north_val = float(north)
            south_val = float(south)
            east_val = float(east)
            west_val = float(west)
            
            result_details['bounds'] = {
                'north': north_val, 'south': south_val,
                'east': east_val, 'west': west_val
            }
            
            # Check if bounds are within San Francisco area
            lat_ok = (target_lat_min <= north_val <= target_lat_max + 0.05 and 
                     target_lat_min - 0.05 <= south_val <= target_lat_max)
            lon_ok = (target_lon_min - 0.05 <= west_val <= target_lon_max and 
                     target_lon_min <= east_val <= target_lon_max + 0.05)
            
            if lat_ok and lon_ok:
                location_correct = True
                score += 10
                feedback_parts.append("✅ Location bounds in San Francisco")
            else:
                # Check if at least partially overlapping
                lat_overlap = not (north_val < target_lat_min or south_val > target_lat_max)
                lon_overlap = not (east_val < target_lon_min or west_val > target_lon_max)
                
                if lat_overlap and lon_overlap:
                    score += 5
                    feedback_parts.append("⚠️ Location partially in San Francisco")
                else:
                    feedback_parts.append(f"❌ Location outside San Francisco: {south_val:.3f}-{north_val:.3f}N, {west_val:.3f}-{east_val:.3f}W")
        else:
            feedback_parts.append("⚠️ Incomplete location bounds")
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"❌ Invalid location bounds: {e}")
    
    result_details['location_correct'] = location_correct
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (15 pts)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Get trajectory frames - use multiple frames across the episode
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5) if hasattr(traj, '__iter__') else []
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                # Use trajectory frames if available, otherwise fall back to final screenshot
                images_to_check = trajectory_frames if trajectory_frames else ([final_screenshot] if final_screenshot else [])
                
                if images_to_check:
                    vlm_prompt = """You are analyzing screenshots from an agent creating a ground overlay in Google Earth Pro.

The task was to:
1. Create an Image Overlay with a historical map
2. Position it over San Francisco
3. Rotate the overlay to align streets
4. Set transparency to ~50%
5. Save and export as KMZ

Analyze these images and determine:
1. Is Google Earth Pro visible?
2. Can you see an Image Overlay dialog or properties panel?
3. Is there a semi-transparent overlay visible on the map?
4. Does the view show San Francisco area?
5. Are there signs of overlay manipulation (rotation/transparency controls)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "overlay_dialog_visible": true/false,
    "transparent_overlay_visible": true/false,
    "san_francisco_area": true/false,
    "overlay_manipulation_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
                    vlm_result = query_vlm(
                        prompt=vlm_prompt,
                        images=images_to_check if len(images_to_check) > 1 else None,
                        image=images_to_check[0] if len(images_to_check) == 1 else None
                    )
                    
                    result_details['vlm_result'] = vlm_result
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        vlm_criteria = [
                            parsed.get('google_earth_visible', False),
                            parsed.get('overlay_dialog_visible', False) or parsed.get('transparent_overlay_visible', False),
                            parsed.get('san_francisco_area', False),
                            parsed.get('overlay_manipulation_evidence', False)
                        ]
                        
                        criteria_met = sum(vlm_criteria)
                        confidence = parsed.get('confidence', 'low')
                        
                        # Score based on criteria met and confidence
                        base_vlm_score = (criteria_met / len(vlm_criteria)) * 15
                        confidence_multiplier = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                        vlm_score = int(base_vlm_score * confidence_multiplier)
                        
                        score += vlm_score
                        
                        if vlm_score >= 10:
                            feedback_parts.append(f"✅ VLM verification passed ({vlm_score}/15 pts)")
                        elif vlm_score >= 5:
                            feedback_parts.append(f"⚠️ VLM verification partial ({vlm_score}/15 pts)")
                        else:
                            feedback_parts.append(f"❌ VLM verification low ({vlm_score}/15 pts)")
                        
                        observations = parsed.get('observations', '')
                        if observations:
                            result_details['vlm_observations'] = observations
                    else:
                        feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
                else:
                    feedback_parts.append("⚠️ No trajectory frames available for VLM")
            else:
                feedback_parts.append("⚠️ No screenshots available for VLM verification")
        except ImportError:
            logger.warning("VLM utilities not available")
            feedback_parts.append("⚠️ VLM verification skipped (utilities not available)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
    else:
        feedback_parts.append("⚠️ VLM query function not available")
    
    result_details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    max_score = 100
    result_details['final_score'] = score
    result_details['max_score'] = max_score
    
    # Key criteria: Must have created the KMZ file AND either rotation or opacity must be correct
    key_criteria_met = (
        file_created_during_task and 
        has_ground_overlay and 
        (rotation_correct or opacity_correct)
    )
    
    # Pass threshold: 60 points with key criteria
    passed = score >= 60 and key_criteria_met
    
    # Add summary
    feedback_parts.append(f"Score: {score}/{max_score}")
    if passed:
        feedback_parts.insert(0, "🎉 TASK PASSED")
    else:
        if not file_created_during_task:
            feedback_parts.insert(0, "❌ FAILED: KMZ not created during task")
        elif not has_ground_overlay:
            feedback_parts.insert(0, "❌ FAILED: No GroundOverlay in export")
        elif not (rotation_correct or opacity_correct):
            feedback_parts.insert(0, "❌ FAILED: Neither rotation nor opacity criteria met")
        else:
            feedback_parts.insert(0, "❌ FAILED: Score below threshold")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }