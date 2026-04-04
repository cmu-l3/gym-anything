#!/usr/bin/env python3
"""
Verifier for UTM Coordinate Navigation task.

VERIFICATION STRATEGY (Multi-Signal, Anti-Gaming):
1. Config file check: UTM format enabled (30 points)
2. Config modification timestamp (10 points) - anti-gaming
3. Trajectory VLM: Shows preferences dialog interaction (10 points)
4. View location check: Near Devils Tower (25 points)
5. Final VLM: Devils Tower visible (15 points)
6. Final VLM: UTM coordinates displayed (10 points)

Total: 100 points
Pass threshold: 70 points with UTM config enabled (mandatory)

Uses copy_from_env (NOT exec_in_env) and trajectory frames for VLM.
"""

import json
import tempfile
import os
import logging
from math import radians, sin, cos, sqrt, atan2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance in km between two coordinate points."""
    R = 6371  # Earth's radius in km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c


# =============================================================================
# VLM PROMPTS
# =============================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring coordinate settings in Google Earth Pro.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For this task, the agent should:
1. Open the Options/Preferences dialog (Tools menu → Options)
2. Navigate to the "3D View" tab in preferences
3. Change coordinate display format to UTM (Universal Transverse Mercator)
4. Apply and close the dialog
5. Navigate to a location using UTM coordinates

Assess these criteria based on what you see across ALL frames:

1. PREFERENCES_DIALOG_VISIBLE: At any point, is a preferences/options dialog window visible?
   (Look for a dialog with tabs like "3D View", settings panels, Apply/OK buttons)

2. COORDINATE_SETTINGS_SHOWN: Is there a dropdown or setting related to coordinate format?
   (Look for "Show Lat/Long", "Decimal Degrees", "UTM" options)

3. UTM_OPTION_SELECTED: Is "Universal Transverse Mercator" or "UTM" visible as selected?

4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (preferences opening, 
   settings being changed, navigation occurring)?

Respond in JSON format:
{
    "preferences_dialog_visible": true/false,
    "coordinate_settings_shown": true/false,
    "utm_option_selected": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list what you see happening"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you observe across frames"
}
"""


FINAL_VIEW_PROMPT = """You are verifying if Google Earth Pro is showing Devils Tower National Monument.

Devils Tower is a distinctive geological formation in Wyoming, USA:
- A tall, columnar rock tower with vertical striations/ridges
- Rises dramatically from relatively flat surrounding terrain
- Located in northeastern Wyoming
- The top is flat, the sides have distinctive vertical grooves
- Surrounded by forest and prairie

Also check for UTM coordinate display:
- UTM coordinates appear in the status bar at the bottom
- Format shows zone (like "13T" or "13N") followed by numbers
- Example: "13T 534350mE 4940750mN" or similar
- This is DIFFERENT from regular lat/long like "44.59°N, 104.71°W"

Analyze this screenshot:

1. IS_GOOGLE_EARTH: Is this Google Earth (satellite/aerial imagery interface)?

2. DEVILS_TOWER_VISIBLE: Is Devils Tower visible? Look for:
   - The distinctive columnar rock formation
   - Vertical striations on the rock face
   - The tower rising from flat/forested terrain
   - Could be close-up (showing rock detail) or wider view (showing tower in landscape)

3. UTM_COORDINATES_DISPLAYED: Are UTM coordinates visible in the status bar?
   Look for format like "13T" or "13N" followed by Easting/Northing values
   NOT regular decimal degrees or degrees-minutes-seconds

4. WYOMING_AREA: Does this look like Wyoming terrain (prairie, badlands, sparse vegetation)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "devils_tower_visible": true/false,
    "utm_coordinates_displayed": true/false,
    "wyoming_area": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_utm_coordinate_navigation(traj, env_info, task_info):
    """
    Verify UTM coordinate navigation task completion.
    
    Multi-criteria scoring with anti-gaming measures.
    Uses copy_from_env and trajectory-based VLM verification.
    """
    # Get required functions
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    target = metadata.get('target_location', {})
    target_lat = target.get('lat', 44.5902)
    target_lon = target.get('lon', -104.7146)
    tolerance_km = target.get('tolerance_km', 5.0)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result file from container
    # ================================================================
    result_data = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_file_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load result file: {e}")
        details['result_file_loaded'] = False
        details['result_file_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: UTM format enabled in config (30 points)
    # ================================================================
    utm_enabled = False
    if result_data:
        config_checks = result_data.get('config_checks', {})
        utm_enabled = config_checks.get('utm_enabled', False)
        config_format = config_checks.get('config_format_value', -1)
        
        details['utm_config'] = {
            'enabled': utm_enabled,
            'format_value': config_format
        }
        
        if utm_enabled:
            score += 30
            feedback_parts.append("✅ UTM format enabled in config (30pts)")
        else:
            feedback_parts.append(f"❌ UTM format not enabled (format={config_format}, expected=2)")
    else:
        feedback_parts.append("❌ Could not read config state")
    
    # ================================================================
    # CRITERION 2: Config modified during task (10 points) - Anti-gaming
    # ================================================================
    config_modified = False
    if result_data:
        config_checks = result_data.get('config_checks', {})
        config_modified = config_checks.get('config_modified_during_task', False)
        
        details['config_modified'] = config_modified
        
        if config_modified:
            score += 10
            feedback_parts.append("✅ Config modified during task (10pts)")
        elif utm_enabled:
            # UTM was enabled but not during this task - suspicious
            score += 3
            feedback_parts.append("⚠️ Config not modified during task (3pts)")
        else:
            feedback_parts.append("❌ Config not modified")
    
    # ================================================================
    # CRITERION 3: View location check (25 points)
    # ================================================================
    view_near_target = False
    if result_data:
        view_info = result_data.get('view_info', {})
        extracted_lat = view_info.get('extracted_lat', 0)
        extracted_lon = view_info.get('extracted_lon', 0)
        
        if extracted_lat != 0 and extracted_lon != 0:
            distance = haversine_distance(target_lat, target_lon, extracted_lat, extracted_lon)
            details['view_distance_km'] = distance
            
            if distance <= tolerance_km:
                view_near_target = True
                score += 25
                feedback_parts.append(f"✅ View near Devils Tower ({distance:.1f}km away) (25pts)")
            elif distance <= tolerance_km * 2:
                score += 15
                feedback_parts.append(f"⚠️ View somewhat near target ({distance:.1f}km away) (15pts)")
            else:
                feedback_parts.append(f"❌ View far from target ({distance:.1f}km away)")
        else:
            details['view_distance_km'] = None
            feedback_parts.append("⚠️ Could not extract view coordinates from files")
    
    # ================================================================
    # CRITERION 4-5: VLM Trajectory Verification (10 points)
    # ================================================================
    trajectory_score = 0
    if query_vlm and traj:
        # Import trajectory frame sampling
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) > 0:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_PROCESS_PROMPT,
                    images=frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['trajectory_vlm'] = parsed
                    
                    prefs_visible = parsed.get('preferences_dialog_visible', False)
                    coord_settings = parsed.get('coordinate_settings_shown', False)
                    utm_selected = parsed.get('utm_option_selected', False)
                    progression = parsed.get('meaningful_progression', False)
                    
                    if prefs_visible:
                        trajectory_score += 4
                    if coord_settings or utm_selected:
                        trajectory_score += 4
                    if progression:
                        trajectory_score += 2
                    
                    score += trajectory_score
                    
                    if trajectory_score >= 8:
                        feedback_parts.append(f"✅ Trajectory shows preferences interaction ({trajectory_score}pts)")
                    elif trajectory_score > 0:
                        feedback_parts.append(f"⚠️ Partial trajectory evidence ({trajectory_score}pts)")
                    else:
                        feedback_parts.append("❌ No preferences interaction in trajectory")
                else:
                    details['trajectory_vlm_error'] = vlm_result.get('error', 'Unknown')
                    feedback_parts.append("⚠️ Trajectory VLM query failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except ImportError:
            feedback_parts.append("⚠️ Trajectory frame sampling not available")
    else:
        feedback_parts.append("⚠️ VLM or trajectory not available")
    
    # ================================================================
    # CRITERION 6-7: Final Screenshot VLM (25 points total)
    # ================================================================
    final_vlm_score = 0
    if query_vlm:
        # Copy final screenshot
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/task_final_state.png", temp_screenshot.name)
            
            # Check file size
            if os.path.getsize(temp_screenshot.name) > 1000:
                vlm_result = query_vlm(
                    prompt=FINAL_VIEW_PROMPT,
                    image=temp_screenshot.name
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['final_vlm'] = parsed
                    
                    is_ge = parsed.get('is_google_earth', False)
                    devils_tower = parsed.get('devils_tower_visible', False)
                    utm_displayed = parsed.get('utm_coordinates_displayed', False)
                    wyoming = parsed.get('wyoming_area', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Devils Tower visible (15 points)
                    if devils_tower:
                        if confidence == 'high':
                            final_vlm_score += 15
                        elif confidence == 'medium':
                            final_vlm_score += 12
                        else:
                            final_vlm_score += 8
                        feedback_parts.append(f"✅ Devils Tower visible ({confidence} conf)")
                    elif wyoming and is_ge:
                        final_vlm_score += 5
                        feedback_parts.append("⚠️ Wyoming area visible but Devils Tower unclear")
                    else:
                        feedback_parts.append("❌ Devils Tower not visible")
                    
                    # UTM coordinates displayed (10 points)
                    if utm_displayed:
                        final_vlm_score += 10
                        feedback_parts.append("✅ UTM coordinates displayed in status bar")
                    else:
                        feedback_parts.append("❌ UTM coordinates not visible in status bar")
                    
                    score += final_vlm_score
                else:
                    details['final_vlm_error'] = vlm_result.get('error', 'Unknown')
                    feedback_parts.append("⚠️ Final VLM query failed")
            else:
                feedback_parts.append("⚠️ Final screenshot too small or empty")
        except Exception as e:
            logger.warning(f"Could not process final screenshot: {e}")
            feedback_parts.append(f"⚠️ Could not load final screenshot: {str(e)}")
        finally:
            if os.path.exists(temp_screenshot.name):
                os.unlink(temp_screenshot.name)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['score_breakdown'] = {
        'utm_config': 30 if utm_enabled else 0,
        'config_modified': 10 if config_modified else (3 if utm_enabled else 0),
        'view_location': 25 if view_near_target else 0,
        'trajectory_vlm': trajectory_score,
        'final_vlm': final_vlm_score
    }
    
    # Pass criteria:
    # - Must have UTM enabled (mandatory)
    # - Score >= 70
    passed = utm_enabled and score >= 70
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/100"
    
    if passed:
        feedback = f"✅ PASSED - {feedback}"
    else:
        if not utm_enabled:
            feedback = f"❌ FAILED (UTM not enabled - mandatory) - {feedback}"
        else:
            feedback = f"❌ FAILED (score {score} < 70) - {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }