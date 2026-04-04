#!/usr/bin/env python3
"""
Verifier for Historical Imagery Dubai task.

TASK: Navigate to Palm Jumeirah, Dubai in Google Earth Pro, enable Historical
Imagery mode, set timeline to 2002 or earlier, and save a screenshot showing
the undeveloped coastline before the artificial palm islands were constructed.

VERIFICATION STRATEGY (Multi-Signal):
1. Output file exists and is valid image (15 points)
2. File was created during task - anti-gaming (15 points)
3. VLM: Location is Dubai/Persian Gulf area (20 points)
4. VLM: Historical imagery slider is visible (20 points)
5. VLM: Year displayed is 2002 or earlier (15 points)
6. VLM: No artificial palm islands visible (15 points)

Uses TRAJECTORY FRAMES for process verification to ensure agent actually
performed the workflow (navigation → historical mode → screenshot).

Pass threshold: 60 points AND file was created during task
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

# Trajectory process verification - uses multiple frames
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro to view historical satellite imagery.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For this task, the agent should progress through these stages:
1. Google Earth open - the application interface is visible
2. Navigation to Dubai - search performed or coordinates entered
3. Historical Imagery enabled - time slider appears (clock icon clicked)
4. Time slider adjusted - moved to show earlier years
5. Screenshot saved - file save dialog or confirmation

Assess the trajectory:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro interface visible in any frame?
2. NAVIGATION_PERFORMED: Does any frame show Dubai/Persian Gulf area?
3. HISTORICAL_MODE_ACTIVATED: Is a time slider visible in any frame?
4. MEANINGFUL_PROGRESSION: Do frames show different states (not same screen)?
5. WORKFLOW_STAGES: List which stages you can identify

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "navigation_performed": true/false,
    "historical_mode_activated": true/false,
    "meaningful_progression": true/false,
    "workflow_stages": ["list stages observed"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression across frames"
}
"""

# Screenshot content verification - uses saved screenshot
SCREENSHOT_CONTENT_PROMPT = """You are verifying a screenshot saved from Google Earth Pro showing historical satellite imagery.

CONTEXT: The task was to view Palm Jumeirah, Dubai from 2002 or earlier - BEFORE the artificial palm-shaped islands were built. Construction started in 2001, so imagery from 2002 or earlier should show only natural coastline.

Analyze this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this a Google Earth satellite/aerial view (not a photo)?

2. SHOWS_DUBAI_AREA: Does this show the Dubai/UAE/Persian Gulf region?
   - Look for: desert terrain, Persian Gulf coastline, urban areas
   - The specific area is where Palm Jumeirah is now located

3. HISTORICAL_SLIDER_VISIBLE: Is there a historical imagery time slider?
   - Usually appears at top of screen as a horizontal timeline
   - Has dates/years marked on it

4. YEAR_DISPLAYED: What year is shown on the time slider (if visible)?
   - Look for 4-digit year (e.g., 2002, 2001, 2000, 1999)
   - Report the exact year if you can read it

5. NO_PALM_ISLANDS: Are there NO artificial palm-shaped islands visible?
   - Palm Jumeirah is a distinctive palm tree shape in the water
   - If the coastline is natural (no palm shapes), this is CORRECT for historical imagery
   - If you see palm-shaped artificial islands, this is modern imagery (INCORRECT)

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_dubai_area": true/false,
    "historical_slider_visible": true/false,
    "year_displayed": null or integer (e.g., 2002),
    "no_palm_islands": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe what you see and how you determined each answer"
}
"""

# Final state verification - uses final trajectory frame
FINAL_STATE_PROMPT = """You are verifying the final state of Google Earth Pro after the agent attempted to view historical imagery of Dubai.

Look at this screenshot and determine:
1. Is Google Earth Pro visible and active?
2. Is the view showing an aerial/satellite image (not just the interface)?
3. Is there a historical imagery time slider visible?
4. Does the view appear to show a coastal/gulf region?

Respond in JSON format:
{
    "google_earth_active": true/false,
    "satellite_view_visible": true/false,
    "time_slider_visible": true/false,
    "coastal_region_shown": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def _vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    if not image and not images:
        logger.warning("No images provided for VLM query")
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def verify_historical_imagery_dubai(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that agent navigated to Dubai, enabled historical imagery mode,
    selected 2002 or earlier, and saved a screenshot.
    
    Uses multiple independent signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/palm_jumeirah_2002.jpg')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    max_year = metadata.get('max_year', 2002)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists and is valid (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    image_format = result.get('image_format', 'none')
    
    if output_exists and output_size >= min_file_size_kb * 1024:
        score += 15
        feedback_parts.append(f"✅ Output file exists ({output_size/1024:.1f}KB)")
        result_details['file_valid'] = True
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ Output file exists but small ({output_size/1024:.1f}KB)")
        result_details['file_valid'] = False
    else:
        feedback_parts.append("❌ Output file NOT found")
        result_details['file_valid'] = False
    
    # ================================================================
    # CRITERION 2: File was created during task - ANTI-GAMING (15 points)
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    
    if file_created:
        score += 15
        feedback_parts.append("✅ File created during task")
        result_details['anti_gaming_pass'] = True
    elif file_modified:
        score += 10
        feedback_parts.append("⚠️ File modified during task")
        result_details['anti_gaming_pass'] = True
    else:
        feedback_parts.append("❌ File NOT created during task (anti-gaming fail)")
        result_details['anti_gaming_pass'] = False
    
    # ================================================================
    # STEP 2: Copy the saved screenshot for VLM analysis
    # ================================================================
    saved_screenshot = None
    if output_exists:
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        try:
            copy_from_env(expected_output_path, temp_screenshot.name)
            if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                saved_screenshot = temp_screenshot.name
                result_details['saved_screenshot_copied'] = True
        except Exception as e:
            logger.warning(f"Could not copy saved screenshot: {e}")
            result_details['saved_screenshot_copied'] = False
    
    # ================================================================
    # STEP 3: Get trajectory frames for process verification
    # ================================================================
    trajectory_frames = []
    try:
        # Import from gym_anything if available
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        result_details['trajectory_frames_count'] = len(trajectory_frames)
        result_details['final_frame_available'] = final_frame is not None
    except ImportError:
        logger.warning("Could not import trajectory frame utilities")
        # Fallback: try to get final screenshot from container
        temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/task_final.png", temp_final.name)
            if os.path.exists(temp_final.name) and os.path.getsize(temp_final.name) > 1000:
                final_frame = temp_final.name
        except:
            final_frame = None
    
    # ================================================================
    # VLM CRITERION 3: Trajectory shows proper workflow (process verification)
    # ================================================================
    trajectory_score = 0
    if query_vlm and trajectory_frames:
        traj_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=trajectory_frames)
        result_details['trajectory_vlm'] = traj_result
        
        if traj_result:
            ge_visible = traj_result.get('google_earth_visible', False)
            nav_done = traj_result.get('navigation_performed', False)
            hist_mode = traj_result.get('historical_mode_activated', False)
            progression = traj_result.get('meaningful_progression', False)
            
            if ge_visible and nav_done:
                trajectory_score += 10
            if hist_mode:
                trajectory_score += 10
            if progression:
                trajectory_score += 5
            
            if trajectory_score > 0:
                feedback_parts.append(f"✅ Trajectory shows workflow ({trajectory_score}/25 pts)")
            else:
                feedback_parts.append("❌ Trajectory does not show expected workflow")
    else:
        feedback_parts.append("⚠️ Trajectory verification skipped (no VLM or frames)")
    
    # ================================================================
    # VLM CRITERIA 4-6: Verify saved screenshot content
    # ================================================================
    screenshot_score = 0
    location_correct = False
    historical_slider = False
    year_correct = False
    no_palm_islands = False
    
    if query_vlm and saved_screenshot:
        content_result = _vlm_query(query_vlm, SCREENSHOT_CONTENT_PROMPT, image=saved_screenshot)
        result_details['screenshot_vlm'] = content_result
        
        if content_result:
            # CRITERION 4: Location is Dubai area (20 points)
            if content_result.get('is_google_earth', False) and content_result.get('shows_dubai_area', False):
                score += 20
                location_correct = True
                feedback_parts.append("✅ Location: Dubai/UAE area confirmed")
            else:
                feedback_parts.append("❌ Location: Not clearly Dubai area")
            
            # CRITERION 5: Historical slider visible (20 points)
            if content_result.get('historical_slider_visible', False):
                score += 20
                historical_slider = True
                feedback_parts.append("✅ Historical imagery slider visible")
            else:
                feedback_parts.append("❌ Historical imagery slider NOT visible")
            
            # CRITERION 6: Year is 2002 or earlier (15 points)
            year_displayed = content_result.get('year_displayed')
            if year_displayed is not None:
                try:
                    year_int = int(year_displayed)
                    if year_int <= max_year:
                        score += 15
                        year_correct = True
                        feedback_parts.append(f"✅ Year {year_int} shown (≤{max_year})")
                    else:
                        feedback_parts.append(f"❌ Year {year_int} shown (need ≤{max_year})")
                except (ValueError, TypeError):
                    feedback_parts.append(f"⚠️ Could not parse year: {year_displayed}")
            else:
                feedback_parts.append("⚠️ Year not detected in screenshot")
            
            # CRITERION 7: No palm islands visible (15 points) 
            if content_result.get('no_palm_islands', False):
                score += 15
                no_palm_islands = True
                feedback_parts.append("✅ No artificial palm islands (historical imagery)")
            elif content_result.get('no_palm_islands') is False:
                feedback_parts.append("❌ Palm islands visible (modern imagery)")
            else:
                feedback_parts.append("⚠️ Could not determine if palm islands present")
            
            # Adjust for confidence
            confidence = content_result.get('confidence', 'low')
            result_details['vlm_confidence'] = confidence
    elif not saved_screenshot:
        feedback_parts.append("❌ No screenshot to verify")
    else:
        feedback_parts.append("⚠️ Screenshot VLM verification skipped (no VLM)")
    
    # Clean up temporary screenshot file
    if saved_screenshot and os.path.exists(saved_screenshot):
        try:
            os.unlink(saved_screenshot)
        except:
            pass
    
    # ================================================================
    # CHECK GOOGLE EARTH WAS RUNNING
    # ================================================================
    ge_running = result.get('google_earth_running', False)
    if ge_running:
        feedback_parts.append("✅ Google Earth was running")
    else:
        feedback_parts.append("⚠️ Google Earth not detected running")
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    # Key criteria: file must be created during task AND either historical mode or correct location
    key_criteria_met = (
        result_details.get('anti_gaming_pass', False) and
        output_exists and
        (historical_slider or location_correct or year_correct)
    )
    
    # Pass threshold: 60 points AND key criteria
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    result_details['final_score'] = score
    result_details['key_criteria_met'] = key_criteria_met
    result_details['location_correct'] = location_correct
    result_details['historical_slider'] = historical_slider
    result_details['year_correct'] = year_correct
    result_details['no_palm_islands'] = no_palm_islands
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }