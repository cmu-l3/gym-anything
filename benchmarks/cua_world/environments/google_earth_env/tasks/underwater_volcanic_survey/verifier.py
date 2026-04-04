#!/usr/bin/env python3
"""
Verifier for Underwater Volcanic Survey task.

Task: Disable water surface visualization, navigate to Axial Seamount,
      create a placemark, and save a screenshot.

Verification Strategy:
1. Screenshot file exists and was created during task (20 pts)
2. Screenshot has reasonable size (10 pts)
3. Placemark exists with correct name (15 pts)
4. Placemark location is near target coordinates (15 pts)
5. Placemark has appropriate description (10 pts)
6. VLM trajectory verification - water surface toggle (15 pts)
7. VLM verification - underwater terrain visible (15 pts)

Pass threshold: 60 points with screenshot existence required
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_underwater_volcanic_survey(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the underwater volcanic survey task completion.
    
    Uses multiple independent signals:
    - Programmatic checks on files and timestamps
    - VLM verification on trajectory and final state
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
    target_lat = metadata.get('target_latitude', 45.95)
    target_lon = metadata.get('target_longitude', -130.01)
    tolerance = metadata.get('coordinate_tolerance_degrees', 0.5)
    expected_screenshot = metadata.get('expected_screenshot_path', '/home/ga/Documents/axial_seamount_survey.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 50)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Load task result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['task_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Screenshot file exists (10 pts)
    # ================================================================
    output_info = result.get('output_screenshot', {})
    output_exists = output_info.get('exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ Screenshot file exists")
    else:
        feedback_parts.append("❌ Screenshot file NOT found")
        # Early exit if no screenshot
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Screenshot created during task - anti-gaming (10 pts)
    # ================================================================
    created_during_task = output_info.get('created_during_task', False)
    
    if created_during_task:
        score += 10
        feedback_parts.append("✅ Screenshot created during task")
    else:
        feedback_parts.append("⚠️ Screenshot may predate task (gaming check failed)")
    
    # ================================================================
    # CRITERION 3: Screenshot has reasonable size (10 pts)
    # ================================================================
    output_size = output_info.get('size_bytes', 0) / 1024  # KB
    
    if output_size >= 100:  # Good quality image
        score += 10
        feedback_parts.append(f"✅ Screenshot size good ({output_size:.1f} KB)")
    elif output_size >= min_size_kb:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot size acceptable ({output_size:.1f} KB)")
    else:
        feedback_parts.append(f"❌ Screenshot too small ({output_size:.1f} KB)")
    
    # ================================================================
    # CRITERION 4: Placemark exists with correct name (15 pts)
    # ================================================================
    placemark_info = result.get('placemark', {})
    placemark_found = placemark_info.get('found', False)
    placemark_name = placemark_info.get('name', '')
    
    if placemark_found and 'axial' in placemark_name.lower() and 'seamount' in placemark_name.lower():
        score += 15
        feedback_parts.append(f"✅ Placemark found: '{placemark_name}'")
    elif placemark_found:
        score += 8
        feedback_parts.append(f"⚠️ Placemark found but name differs: '{placemark_name}'")
    else:
        feedback_parts.append("❌ Placemark 'Axial Seamount' not found")
    
    # ================================================================
    # CRITERION 5: Placemark location near target (15 pts)
    # ================================================================
    placemark_coords = placemark_info.get('coordinates', '')
    location_correct = False
    
    if placemark_coords:
        try:
            # KML format: lon,lat,alt
            parts = placemark_coords.split(',')
            if len(parts) >= 2:
                pm_lon = float(parts[0].strip())
                pm_lat = float(parts[1].strip())
                
                lat_diff = abs(pm_lat - target_lat)
                lon_diff = abs(pm_lon - target_lon)
                
                if lat_diff <= tolerance and lon_diff <= tolerance:
                    score += 15
                    location_correct = True
                    feedback_parts.append(f"✅ Placemark location correct ({pm_lat:.2f}°N, {pm_lon:.2f}°W)")
                elif lat_diff <= tolerance * 2 and lon_diff <= tolerance * 2:
                    score += 8
                    feedback_parts.append(f"⚠️ Placemark location close ({pm_lat:.2f}°N, {pm_lon:.2f}°W)")
                else:
                    feedback_parts.append(f"❌ Placemark location off ({pm_lat:.2f}°N, {pm_lon:.2f}°W)")
                
                details['placemark_location'] = {'lat': pm_lat, 'lon': pm_lon}
        except Exception as e:
            feedback_parts.append(f"⚠️ Could not parse placemark coordinates: {e}")
    else:
        feedback_parts.append("❌ No placemark coordinates found")
    
    # ================================================================
    # CRITERION 6: Placemark description contains keywords (10 pts)
    # ================================================================
    placemark_desc = placemark_info.get('description', '').lower()
    desc_keywords = ['submarine', 'volcano', 'juan de fuca', 'underwater', 'seamount', 'ridge']
    keywords_found = sum(1 for kw in desc_keywords if kw in placemark_desc)
    
    if keywords_found >= 2:
        score += 10
        feedback_parts.append(f"✅ Description has relevant keywords ({keywords_found} found)")
    elif keywords_found >= 1:
        score += 5
        feedback_parts.append(f"⚠️ Description partially relevant ({keywords_found} keyword)")
    elif placemark_desc:
        score += 2
        feedback_parts.append("⚠️ Description exists but no relevant keywords")
    else:
        feedback_parts.append("❌ No description found")
    
    # ================================================================
    # CRITERION 7 & 8: VLM verification (30 pts total)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        # Try to get trajectory frames for process verification
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            # Process verification using trajectory
            if trajectory_frames and len(trajectory_frames) >= 3:
                process_prompt = """You are analyzing screenshots from an agent using Google Earth Pro to explore underwater volcanic terrain.

The task required:
1. Disabling water surface visualization (View > Water Surface unchecked)
2. Navigating to the Axial Seamount (off Oregon coast, ~45.95°N, 130.01°W)
3. Creating a placemark

Analyze these chronological screenshots and determine:

1. WATER_SURFACE_TOGGLED: At any point, is the ocean floor terrain visible where ocean water would normally appear? (Brown/gray underwater terrain instead of blue water)

2. NAVIGATION_TO_PACIFIC: Do the screenshots show navigation to a Pacific Ocean region (west of North America)?

3. UNDERWATER_TERRAIN_VISIBLE: Is submarine volcanic ridge terrain visible? (Ridges, valleys, seamount structures on the ocean floor)

4. MEANINGFUL_PROGRESSION: Do the frames show actual navigation/interaction progression (not just static screens)?

Respond in JSON:
{
    "water_surface_toggled": true/false,
    "navigation_to_pacific": true/false,
    "underwater_terrain_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see across the frames"
}
"""
                
                vlm_result = query_vlm(prompt=process_prompt, images=trajectory_frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    if parsed.get('water_surface_toggled'):
                        vlm_score += 8
                        feedback_parts.append("✅ VLM: Water surface toggle detected")
                    
                    if parsed.get('underwater_terrain_visible'):
                        vlm_score += 7
                        feedback_parts.append("✅ VLM: Underwater terrain visible")
                    
                    if parsed.get('meaningful_progression'):
                        vlm_score += 5
                        feedback_parts.append("✅ VLM: Navigation progression observed")
                    
                    confidence = parsed.get('confidence', 'low')
                    if confidence == 'high':
                        vlm_score = int(vlm_score * 1.1)  # Bonus for high confidence
            
            # Final screenshot verification
            if final_screenshot:
                final_prompt = """Analyze this Google Earth Pro screenshot to verify underwater volcanic exploration.

Check:
1. Is the water surface visualization DISABLED? (Ocean floor terrain visible as brown/gray instead of blue water)
2. Does it show a submarine volcanic feature or ridge system?
3. Is this the Pacific Ocean region (off North American west coast)?

Respond in JSON:
{
    "water_surface_off": true/false,
    "volcanic_terrain_visible": true/false,
    "pacific_region": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "what you see"
}
"""
                
                final_vlm = query_vlm(prompt=final_prompt, image=final_screenshot)
                
                if final_vlm.get('success'):
                    final_parsed = final_vlm.get('parsed', {})
                    details['vlm_final'] = final_parsed
                    
                    if final_parsed.get('water_surface_off') and final_parsed.get('volcanic_terrain_visible'):
                        vlm_score += 10
                        feedback_parts.append("✅ VLM: Final state shows underwater terrain correctly")
                    elif final_parsed.get('water_surface_off') or final_parsed.get('volcanic_terrain_visible'):
                        vlm_score += 5
                        feedback_parts.append("⚠️ VLM: Partial underwater terrain evidence")
                        
        except ImportError:
            feedback_parts.append("⚠️ VLM trajectory functions not available")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
            details['vlm_error'] = str(e)
    else:
        feedback_parts.append("⚠️ VLM not available for verification")
    
    # Cap VLM score at 30
    vlm_score = min(vlm_score, 30)
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Check if Google Earth was running
    ge_running = result.get('google_earth_running', False)
    if not ge_running:
        feedback_parts.append("⚠️ Google Earth not running at export time")
        score = max(0, score - 5)
    
    details['final_score_breakdown'] = {
        'screenshot_exists': 10 if output_exists else 0,
        'screenshot_during_task': 10 if created_during_task else 0,
        'screenshot_size': 10 if output_size >= 100 else (5 if output_size >= min_size_kb else 0),
        'placemark_name': 15 if (placemark_found and 'axial' in placemark_name.lower()) else 0,
        'placemark_location': 15 if location_correct else 0,
        'placemark_description': min(10, keywords_found * 5) if keywords_found > 0 else 0,
        'vlm_verification': vlm_score
    }
    
    # Determine pass/fail
    # Must have: screenshot exists AND (created during task OR reasonable size)
    key_criteria = output_exists and (created_during_task or output_size >= min_size_kb)
    passed = score >= 60 and key_criteria
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }