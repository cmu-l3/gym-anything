#!/usr/bin/env python3
"""
Verifier for yellowstone_kml_import task.

VERIFICATION STRATEGY:
1. File-based checks (programmatic):
   - KML file was accessed (15 pts)
   - Screenshot exists at expected path (15 pts)
   - Screenshot created during task (10 pts)
   - Screenshot valid size (10 pts)
   - Google Earth myplaces modified/import evidence (15 pts)

2. VLM verification using TRAJECTORY frames (35 pts total):
   - Process verification across trajectory (20 pts)
   - Final state shows Yellowstone/thermal feature (15 pts)

Total: 100 points
Pass threshold: 60 points AND key criteria met
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots showing an agent importing a KML file into Google Earth Pro.

The agent's task was to:
1. Import a KML file with trail waypoints for Yellowstone National Park
2. Navigate to view the imported placemarks at Grand Prismatic Spring
3. Save a screenshot

Look at these screenshots (in chronological order) and assess:

1. FILE_IMPORT_ATTEMPTED: Does any screenshot show a file open dialog, file browser, or evidence of importing a file?

2. PLACES_PANEL_USED: Does any screenshot show the Google Earth Places panel on the left side, possibly with expanded folders or new items?

3. NAVIGATION_OCCURRED: Do the screenshots show the view changing - flying to a new location or zooming into an area?

4. YELLOWSTONE_VISIBLE: Does any screenshot show thermal features (colorful hot springs), Yellowstone terrain, or the Grand Prismatic Spring area?

5. MEANINGFUL_WORKFLOW: Do the frames show real progression through the import-and-navigate workflow?

Respond in JSON format:
{
    "file_import_attempted": true/false,
    "places_panel_used": true/false,
    "navigation_occurred": true/false,
    "yellowstone_visible": true/false,
    "meaningful_workflow": true/false,
    "stages_observed": ["list what you see happening"],
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of the workflow progression"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth navigation task.

TASK: Import a KML file and navigate to Grand Prismatic Spring in Yellowstone National Park.

Grand Prismatic Spring is distinctive - it's a large hot spring with vivid colors (blue center, orange/yellow/brown rings from thermophilic bacteria). It's located in Midway Geyser Basin, Yellowstone.

Look at this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this clearly Google Earth (satellite imagery interface, not a web browser or other app)?

2. SHOWS_YELLOWSTONE: Does this show the Yellowstone area? Look for:
   - Thermal features (colorful hot springs, steam vents)
   - Grand Prismatic Spring (large, colorful thermal pool)
   - Midway Geyser Basin terrain
   - Yellowstone's characteristic landscape

3. PLACEMARKS_VISIBLE: Are there any placemark icons (pushpins, markers) visible on the map?

4. APPROPRIATE_VIEW: Is the view zoomed to show the trail/thermal feature area (not a global view)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_yellowstone": true/false,
    "thermal_features_visible": true/false,
    "placemarks_visible": true/false,
    "appropriate_view": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe what you see in the image"
}
"""


def verify_yellowstone_kml_import(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent imported a KML file and navigated to Yellowstone.
    
    Uses MULTIPLE INDEPENDENT SIGNALS:
    1. File-based checks via copy_from_env
    2. VLM verification using trajectory frames
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "details": {"error": "copy_from_env not provided"}
        }
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/grand_prismatic_imported.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 100)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file was accessed (15 points)
    # ================================================================
    kml_info = result_data.get('kml_file', {})
    kml_accessed = kml_info.get('accessed', False)
    
    if kml_accessed:
        score += 15
        feedback_parts.append("✅ KML file accessed")
    else:
        feedback_parts.append("❌ KML file not accessed")
    details['kml_accessed'] = kml_accessed
    
    # ================================================================
    # CRITERION 2: Screenshot exists (15 points)
    # ================================================================
    screenshot_info = result_data.get('screenshot', {})
    screenshot_exists = screenshot_info.get('exists', False)
    
    if screenshot_exists:
        score += 15
        feedback_parts.append("✅ Screenshot file created")
    else:
        feedback_parts.append("❌ Screenshot file not found")
    details['screenshot_exists'] = screenshot_exists
    
    # ================================================================
    # CRITERION 3: Screenshot created during task (10 points)
    # Anti-gaming: prevents pre-existing files
    # ================================================================
    screenshot_during_task = screenshot_info.get('created_during_task', False)
    
    if screenshot_during_task:
        score += 10
        feedback_parts.append("✅ Screenshot created during task")
    else:
        if screenshot_exists:
            feedback_parts.append("⚠️ Screenshot may predate task")
        # Don't add feedback if screenshot doesn't exist
    details['screenshot_during_task'] = screenshot_during_task
    
    # ================================================================
    # CRITERION 4: Screenshot valid size (10 points)
    # Anti-gaming: prevents empty/tiny placeholder files
    # ================================================================
    screenshot_size = screenshot_info.get('size_bytes', 0)
    screenshot_size_kb = screenshot_size / 1024
    
    if screenshot_size_kb >= min_size_kb:
        score += 10
        feedback_parts.append(f"✅ Screenshot size OK ({screenshot_size_kb:.1f}KB)")
    elif screenshot_size_kb > 10:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot small ({screenshot_size_kb:.1f}KB)")
    else:
        if screenshot_exists:
            feedback_parts.append(f"❌ Screenshot too small ({screenshot_size_kb:.1f}KB)")
    details['screenshot_size_kb'] = screenshot_size_kb
    
    # ================================================================
    # CRITERION 5: Google Earth import evidence (15 points)
    # ================================================================
    ge_info = result_data.get('google_earth', {})
    myplaces_modified = ge_info.get('myplaces_modified', False)
    import_evidence = ge_info.get('import_evidence', False)
    ge_running = ge_info.get('running', False)
    cache_activity = ge_info.get('cache_activity', False)
    
    import_score = 0
    if import_evidence:
        import_score += 10
        feedback_parts.append("✅ Import evidence in myplaces.kml")
    if myplaces_modified:
        import_score += 3
    if cache_activity:
        import_score += 2
    
    import_score = min(import_score, 15)  # Cap at 15
    score += import_score
    
    if import_score >= 10:
        pass  # Already added feedback
    elif import_score > 0:
        feedback_parts.append("⚠️ Partial import evidence")
    else:
        feedback_parts.append("❌ No import evidence found")
    
    details['import_evidence'] = import_evidence
    details['myplaces_modified'] = myplaces_modified
    details['ge_running'] = ge_running
    
    # ================================================================
    # VLM VERIFICATION: Trajectory Process (20 points)
    # Uses MULTIPLE trajectory frames to verify workflow
    # ================================================================
    vlm_trajectory_score = 0
    trajectory_result = {}
    
    if query_vlm:
        # Get trajectory frames
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            
            if trajectory_frames and len(trajectory_frames) > 0:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_PROCESS_PROMPT,
                    images=trajectory_frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    trajectory_result = parsed
                    details['vlm_trajectory'] = parsed
                    
                    # Score based on workflow evidence
                    if parsed.get('file_import_attempted'):
                        vlm_trajectory_score += 5
                    if parsed.get('places_panel_used'):
                        vlm_trajectory_score += 3
                    if parsed.get('navigation_occurred'):
                        vlm_trajectory_score += 5
                    if parsed.get('yellowstone_visible'):
                        vlm_trajectory_score += 4
                    if parsed.get('meaningful_workflow'):
                        vlm_trajectory_score += 3
                    
                    confidence = parsed.get('confidence', 'low')
                    if confidence == 'low':
                        vlm_trajectory_score = int(vlm_trajectory_score * 0.8)
                else:
                    details['vlm_trajectory_error'] = vlm_result.get('error', 'Unknown')
            else:
                details['vlm_trajectory_error'] = 'No trajectory frames available'
        except ImportError:
            details['vlm_trajectory_error'] = 'VLM module not available'
        except Exception as e:
            details['vlm_trajectory_error'] = str(e)
    
    score += vlm_trajectory_score
    if vlm_trajectory_score >= 15:
        feedback_parts.append("✅ VLM: Workflow progression verified")
    elif vlm_trajectory_score >= 8:
        feedback_parts.append("⚠️ VLM: Partial workflow evidence")
    elif query_vlm:
        feedback_parts.append("❌ VLM: Workflow not verified")
    
    details['vlm_trajectory_score'] = vlm_trajectory_score
    
    # ================================================================
    # VLM VERIFICATION: Final State (15 points)
    # ================================================================
    vlm_final_score = 0
    final_result = {}
    
    if query_vlm:
        try:
            # Try to get final screenshot from trajectory
            final_screenshot = None
            try:
                from gym_anything.vlm import get_final_screenshot
                final_screenshot = get_final_screenshot(traj)
            except:
                pass
            
            # Fallback: copy final screenshot from container
            if not final_screenshot:
                temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_final_screenshot.png", temp_final.name)
                    if os.path.exists(temp_final.name) and os.path.getsize(temp_final.name) > 1000:
                        final_screenshot = temp_final.name
                except:
                    pass
            
            if final_screenshot:
                vlm_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    final_result = parsed
                    details['vlm_final'] = parsed
                    
                    if parsed.get('is_google_earth'):
                        vlm_final_score += 3
                    if parsed.get('shows_yellowstone'):
                        vlm_final_score += 5
                    if parsed.get('thermal_features_visible'):
                        vlm_final_score += 3
                    if parsed.get('placemarks_visible'):
                        vlm_final_score += 2
                    if parsed.get('appropriate_view'):
                        vlm_final_score += 2
                    
                    confidence = parsed.get('confidence', 'low')
                    if confidence == 'low':
                        vlm_final_score = int(vlm_final_score * 0.8)
                else:
                    details['vlm_final_error'] = vlm_result.get('error', 'Unknown')
                
                # Clean up temp file if we created one
                if isinstance(final_screenshot, str) and final_screenshot.startswith('/tmp/'):
                    try:
                        os.unlink(final_screenshot)
                    except:
                        pass
            else:
                details['vlm_final_error'] = 'No final screenshot available'
        except Exception as e:
            details['vlm_final_error'] = str(e)
    
    score += vlm_final_score
    if vlm_final_score >= 12:
        feedback_parts.append("✅ VLM: Yellowstone location confirmed")
    elif vlm_final_score >= 6:
        feedback_parts.append("⚠️ VLM: Partial location confirmation")
    elif query_vlm:
        feedback_parts.append("❌ VLM: Location not confirmed")
    
    details['vlm_final_score'] = vlm_final_score
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    
    # Key criteria for passing:
    # - Screenshot must exist
    # - Either KML was accessed OR import evidence found OR VLM confirms workflow
    # - Either screenshot created during task OR VLM confirms location
    
    has_file_evidence = screenshot_exists and (screenshot_during_task or screenshot_size_kb > 50)
    has_import_evidence = kml_accessed or import_evidence or vlm_trajectory_score >= 10
    has_location_evidence = vlm_final_score >= 8 or (trajectory_result.get('yellowstone_visible', False))
    
    key_criteria_met = has_file_evidence and (has_import_evidence or has_location_evidence)
    
    # Minimum score threshold is 60
    passed = score >= 60 and key_criteria_met
    
    # Generate feedback summary
    feedback = " | ".join(feedback_parts)
    feedback += f" | Score: {score}/100"
    
    if passed:
        feedback = "✅ PASS: " + feedback
    else:
        if score < 60:
            feedback = f"❌ FAIL (score {score} < 60): " + feedback
        else:
            feedback = "❌ FAIL (key criteria not met): " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }