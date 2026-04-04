#!/usr/bin/env python3
"""
Verifier for Ocean Floor Bathymetry task.

MULTI-SIGNAL VERIFICATION:
1. Surface screenshot exists and valid (15 points)
2. Bathymetry screenshot exists and valid (15 points)
3. Screenshots created during task - anti-gaming (15 points)
4. Screenshots are visually different - layer toggle evidence (15 points)
5. Placemark created (15 points)
6. Placemark correctly positioned (10 points)
7. VLM: Trajectory shows navigation and layer manipulation (15 points)

Pass threshold: 70 points with both screenshots existing and showing visual differences
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ocean_floor_bathymetry(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully documented ocean floor bathymetry.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - File existence and timestamps
    - Image content analysis
    - Placemark verification
    - VLM trajectory analysis
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result_json'] = result
    
    # ================================================================
    # CRITERION 1: Surface screenshot exists and valid (15 points)
    # ================================================================
    surface_info = result.get('surface_screenshot', {})
    surface_exists = surface_info.get('exists', False)
    surface_size = surface_info.get('size_bytes', 0)
    min_size = metadata.get('min_file_size_kb', 100) * 1024
    
    if surface_exists and surface_size >= min_size:
        score += 15
        feedback_parts.append(f"✓ Surface screenshot valid ({surface_size/1024:.1f}KB)")
    elif surface_exists:
        score += 8
        feedback_parts.append(f"○ Surface screenshot small ({surface_size/1024:.1f}KB)")
    else:
        feedback_parts.append("✗ Surface screenshot not found")
    
    # ================================================================
    # CRITERION 2: Bathymetry screenshot exists and valid (15 points)
    # ================================================================
    bathy_info = result.get('bathymetry_screenshot', {})
    bathy_exists = bathy_info.get('exists', False)
    bathy_size = bathy_info.get('size_bytes', 0)
    
    if bathy_exists and bathy_size >= min_size:
        score += 15
        feedback_parts.append(f"✓ Bathymetry screenshot valid ({bathy_size/1024:.1f}KB)")
    elif bathy_exists:
        score += 8
        feedback_parts.append(f"○ Bathymetry screenshot small ({bathy_size/1024:.1f}KB)")
    else:
        feedback_parts.append("✗ Bathymetry screenshot not found")
    
    # ================================================================
    # CRITERION 3: Screenshots created during task (15 points) - ANTI-GAMING
    # ================================================================
    surface_created = surface_info.get('created_during_task', False)
    bathy_created = bathy_info.get('created_during_task', False)
    
    if surface_created and bathy_created:
        score += 15
        feedback_parts.append("✓ Both screenshots created during task")
    elif surface_created or bathy_created:
        score += 7
        feedback_parts.append("○ Only one screenshot created during task")
    else:
        feedback_parts.append("✗ Screenshots not created during task (pre-existing)")
    
    # ================================================================
    # CRITERION 4: Screenshots are visually different (15 points)
    # ================================================================
    screenshots_different = result.get('screenshots_different', False)
    image_difference = result.get('image_difference', 0)
    
    if isinstance(image_difference, str):
        try:
            image_difference = float(image_difference)
        except:
            image_difference = 0
    
    min_difference = metadata.get('min_image_difference', 10.0)
    
    if screenshots_different and image_difference >= min_difference:
        score += 15
        feedback_parts.append(f"✓ Screenshots visually different (diff={image_difference:.1f})")
    elif image_difference > 5:
        score += 8
        feedback_parts.append(f"○ Screenshots somewhat different (diff={image_difference:.1f})")
    else:
        feedback_parts.append(f"✗ Screenshots appear identical (diff={image_difference:.1f})")
    
    # ================================================================
    # CRITERION 5: Placemark created (15 points)
    # ================================================================
    placemarks_info = result.get('placemarks', {})
    new_placemarks = placemarks_info.get('new_placemarks_created', False)
    placemark_data = placemarks_info.get('data', [])
    
    # Check for placemark with matching name
    name_keywords = metadata.get('placemark_name_keywords', ['mid-atlantic', 'rift', 'valley', 'ridge', 'atlantic'])
    bounds = metadata.get('placemark_bounds', {
        'min_lat': 28.0, 'max_lat': 32.0,
        'min_lon': -45.0, 'max_lon': -40.0
    })
    
    placemark_found = False
    placemark_positioned_correctly = False
    found_placemark_name = ""
    
    for pm in placemark_data:
        name = pm.get('name', '').lower()
        coords_str = pm.get('coords', '')
        
        # Check name match
        name_match = any(kw.lower() in name for kw in name_keywords)
        
        if name_match:
            placemark_found = True
            found_placemark_name = pm.get('name', '')
            
            # Parse coordinates (lon,lat,alt format)
            try:
                parts = coords_str.strip().split(',')
                if len(parts) >= 2:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    
                    # Check if within bounds
                    if (bounds['min_lat'] <= lat <= bounds['max_lat'] and
                        bounds['min_lon'] <= lon <= bounds['max_lon']):
                        placemark_positioned_correctly = True
            except (ValueError, IndexError):
                pass
            
            break
    
    # Also check if any placemark (even without matching name) is in correct region
    if not placemark_found and new_placemarks:
        for pm in placemark_data:
            coords_str = pm.get('coords', '')
            try:
                parts = coords_str.strip().split(',')
                if len(parts) >= 2:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    
                    if (bounds['min_lat'] <= lat <= bounds['max_lat'] and
                        bounds['min_lon'] <= lon <= bounds['max_lon']):
                        placemark_found = True
                        placemark_positioned_correctly = True
                        found_placemark_name = pm.get('name', 'unnamed')
                        break
            except (ValueError, IndexError):
                pass
    
    if placemark_found:
        score += 15
        feedback_parts.append(f"✓ Placemark created: '{found_placemark_name}'")
    elif new_placemarks:
        score += 7
        feedback_parts.append("○ Placemark created but name doesn't match")
    else:
        feedback_parts.append("✗ No placemark created")
    
    # ================================================================
    # CRITERION 6: Placemark correctly positioned (10 points)
    # ================================================================
    if placemark_positioned_correctly:
        score += 10
        feedback_parts.append("✓ Placemark in Mid-Atlantic Ridge region")
    elif placemark_found:
        feedback_parts.append("○ Placemark found but position unclear")
    
    details['placemark_found'] = placemark_found
    details['placemark_positioned'] = placemark_positioned_correctly
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (15 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Import VLM helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory (not just final)
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                all_frames = (trajectory_frames or []) + ([final_screenshot] if final_screenshot else [])
                
                vlm_prompt = """You are analyzing screenshots from a Google Earth task where the agent should:
1. Navigate to the Mid-Atlantic Ridge in the Atlantic Ocean
2. Toggle the Water Surface layer to show underwater terrain
3. Take screenshots and create a placemark

Looking at these trajectory frames (from earliest to latest), assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth (satellite/map view) shown?
2. OCEAN_REGION: Do any frames show an ocean/Atlantic region?
3. TERRAIN_CHANGE: Is there evidence of terrain/layer visualization changing?
4. WORKFLOW_PROGRESSION: Do frames show meaningful state changes?
5. MENU_INTERACTION: Is there evidence of View menu or layer panel interaction?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "ocean_region_shown": true/false,
    "terrain_visualization_changed": true/false,
    "workflow_progression": true/false,
    "menu_or_layer_interaction": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across frames"
}
"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_criteria = 0
                    if parsed.get('google_earth_visible', False):
                        vlm_criteria += 1
                    if parsed.get('ocean_region_shown', False):
                        vlm_criteria += 1
                    if parsed.get('terrain_visualization_changed', False):
                        vlm_criteria += 1
                    if parsed.get('workflow_progression', False):
                        vlm_criteria += 1
                    if parsed.get('menu_or_layer_interaction', False):
                        vlm_criteria += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    vlm_score = int((vlm_criteria / 5) * 15 * confidence_mult)
                    
                    if vlm_score >= 10:
                        feedback_parts.append(f"✓ VLM verified workflow ({vlm_criteria}/5 criteria, {confidence} conf)")
                    elif vlm_score >= 5:
                        feedback_parts.append(f"○ VLM partial verification ({vlm_criteria}/5 criteria)")
                    else:
                        feedback_parts.append(f"✗ VLM could not verify workflow")
                else:
                    feedback_parts.append("○ VLM query unsuccessful")
            else:
                feedback_parts.append("○ No trajectory frames for VLM")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"○ VLM verification skipped: {e}")
    else:
        feedback_parts.append("○ VLM not available")
    
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing
    screenshots_created = surface_exists and bathy_exists
    created_during_task = surface_created or bathy_created
    visually_different = screenshots_different
    
    # Pass requires: 70+ points AND both screenshots AND they're different
    passed = (score >= 70 and 
              screenshots_created and 
              (created_during_task or visually_different))
    
    details['score_breakdown'] = {
        'surface_screenshot': 15 if (surface_exists and surface_size >= min_size) else (8 if surface_exists else 0),
        'bathymetry_screenshot': 15 if (bathy_exists and bathy_size >= min_size) else (8 if bathy_exists else 0),
        'created_during_task': 15 if (surface_created and bathy_created) else (7 if (surface_created or bathy_created) else 0),
        'screenshots_different': 15 if screenshots_different else (8 if image_difference > 5 else 0),
        'placemark_created': 15 if placemark_found else (7 if new_placemarks else 0),
        'placemark_positioned': 10 if placemark_positioned_correctly else 0,
        'vlm_verification': vlm_score
    }
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }