#!/usr/bin/env python3
"""
Verifier for Flight Simulator Grand Canyon task.

VERIFICATION STRATEGY:
1. File existence and validity (25 points)
2. Timestamp anti-gaming check (15 points)  
3. VLM trajectory analysis - workflow verification (30 points)
4. VLM final screenshot - content verification (30 points)

Uses TRAJECTORY FRAMES (not just final screenshot) to verify the agent
actually progressed through the flight simulator workflow.

Pass threshold: 60 points AND (cockpit OR canyon visible in VLM)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_flight_simulator_grand_canyon(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully used the flight simulator and captured
    a screenshot showing the Grand Canyon from a cockpit view.
    
    Uses multiple independent verification signals.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/grand_canyon_flight.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
    feedback_parts = []
    result_details = {}
    score = 0
    
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
        logger.warning(f"Failed to read task_result.json: {e}")
        result = {}
        result_details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists and is valid (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    image_format = result.get('image_format', 'none')
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    
    if output_exists and output_size > 0:
        score += 10
        feedback_parts.append(f"✅ Output file exists ({output_size} bytes)")
        
        # Check if valid image
        if image_width > 800 and image_height > 600:
            score += 5
            feedback_parts.append(f"✅ Valid image dimensions ({image_width}x{image_height})")
        elif image_width > 0:
            score += 2
            feedback_parts.append(f"⚠️ Small image dimensions ({image_width}x{image_height})")
    else:
        feedback_parts.append("❌ Output file not found or empty")
        result_details['file_missing'] = True
    
    # ================================================================
    # CRITERION 2: File size check (10 points)
    # ================================================================
    if output_size > min_file_size_kb * 1024:
        score += 10
        feedback_parts.append(f"✅ Good file size ({output_size // 1024}KB)")
    elif output_size > 10 * 1024:
        score += 5
        feedback_parts.append(f"⚠️ Small file size ({output_size // 1024}KB)")
    elif output_exists:
        feedback_parts.append(f"❌ File too small ({output_size} bytes)")
    
    # ================================================================
    # CRITERION 3: Timestamp verification - anti-gaming (15 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task execution")
    elif output_exists and output_mtime > 0 and task_start > 0:
        if output_mtime >= task_start - 60:  # Allow 1 minute tolerance
            score += 10
            feedback_parts.append("⚠️ File timestamp close to task start")
        else:
            feedback_parts.append("❌ File predates task execution (possible pre-existing file)")
    elif output_exists:
        score += 5  # Give partial credit if we can't verify timestamp
        feedback_parts.append("⚠️ Could not verify file timestamp")
    
    # ================================================================
    # CRITERION 4: Google Earth state checks (bonus, up to 5 points)
    # ================================================================
    ge_running = result.get('google_earth_running', False)
    flight_sim_detected = result.get('flight_simulator_detected', False)
    
    if ge_running:
        score += 2
        feedback_parts.append("✅ Google Earth was running")
    
    if flight_sim_detected:
        score += 3
        feedback_parts.append("✅ Flight simulator mode detected")
    
    # ================================================================
    # CRITERION 5: VLM Trajectory Analysis (30 points)
    # Uses MULTIPLE frames from trajectory to verify workflow
    # ================================================================
    vlm_trajectory_score = 0
    vlm_trajectory_details = {}
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames across the trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            
            if trajectory_frames and len(trajectory_frames) > 0:
                # Analyze trajectory for flight simulator workflow
                trajectory_prompt = """You are analyzing a sequence of screenshots showing an agent using Google Earth Pro's flight simulator.

The images are in chronological order from the agent's interaction.

For a successful flight simulator task, look for these stages:
1. GOOGLE_EARTH_VISIBLE: Google Earth Pro interface is visible
2. FLIGHT_SIM_DIALOG: The "Enter Flight Simulator" dialog appeared (shows aircraft selection)
3. COCKPIT_VIEW: A first-person cockpit view with instruments/HUD elements
4. TERRAIN_VISIBLE: Terrain is visible (especially canyon/red rock formations)
5. GRAND_CANYON_FEATURES: Distinctive Grand Canyon features (layered red/brown cliffs, deep gorge)

Assess what you see across ALL the images:

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "flight_sim_dialog_seen": true/false,
    "cockpit_view_present": true/false,
    "terrain_visible": true/false,
    "canyon_features_visible": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list the stages you identified"],
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across frames"
}
"""
                
                vlm_result = query_vlm(
                    prompt=trajectory_prompt,
                    images=trajectory_frames
                )
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    vlm_trajectory_details = parsed
                    
                    # Score trajectory evidence
                    if parsed.get('google_earth_visible'):
                        vlm_trajectory_score += 5
                    if parsed.get('flight_sim_dialog_seen'):
                        vlm_trajectory_score += 8
                    if parsed.get('cockpit_view_present'):
                        vlm_trajectory_score += 8
                    if parsed.get('terrain_visible'):
                        vlm_trajectory_score += 4
                    if parsed.get('canyon_features_visible'):
                        vlm_trajectory_score += 5
                    
                    confidence = parsed.get('confidence', 'low')
                    if confidence == 'low':
                        vlm_trajectory_score = int(vlm_trajectory_score * 0.7)
                    elif confidence == 'medium':
                        vlm_trajectory_score = int(vlm_trajectory_score * 0.85)
                    
                    feedback_parts.append(f"📹 Trajectory VLM: {vlm_trajectory_score}/30 points")
                else:
                    feedback_parts.append("⚠️ Trajectory VLM analysis failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
                
        except ImportError:
            logger.warning("Could not import trajectory sampling utilities")
            feedback_parts.append("⚠️ Trajectory analysis unavailable")
        except Exception as e:
            logger.warning(f"Trajectory VLM analysis error: {e}")
            feedback_parts.append(f"⚠️ Trajectory analysis error")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory analysis")
    
    score += vlm_trajectory_score
    result_details['vlm_trajectory'] = vlm_trajectory_details
    
    # ================================================================
    # CRITERION 6: VLM Final Screenshot Analysis (30 points)
    # Verify the actual output screenshot content
    # ================================================================
    vlm_content_score = 0
    vlm_content_details = {}
    cockpit_visible = False
    canyon_visible = False
    
    if query_vlm and output_exists:
        # Copy the output screenshot from container
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_screenshot.name)
            
            # Verify the file is valid
            if os.path.getsize(temp_screenshot.name) > 1000:
                content_prompt = """Analyze this screenshot that should show Google Earth's flight simulator view over the Grand Canyon.

Look for these specific elements:

1. COCKPIT ELEMENTS: Is this a first-person cockpit view? Look for:
   - Flight instruments (altimeter, airspeed, artificial horizon)
   - HUD overlay elements (heading, altitude numbers)
   - Aircraft frame/canopy edges
   - Joystick/control indicators

2. GRAND CANYON TERRAIN: Does this show the Grand Canyon? Look for:
   - Layered red/brown/orange rock formations
   - Deep canyon gorge with steep cliffs
   - Colorado River (if visible)
   - Desert terrain with distinctive geological layers

3. VIEW PERSPECTIVE: Is this from inside an aircraft looking out (not satellite view)?

Respond in JSON format:
{
    "is_cockpit_view": true/false,
    "cockpit_elements_visible": ["list any cockpit/HUD elements you see"],
    "shows_canyon_terrain": true/false,
    "canyon_features": ["list canyon features visible"],
    "is_first_person_perspective": true/false,
    "is_satellite_view": true/false,
    "overall_assessment": "flight_sim_canyon" / "flight_sim_other" / "regular_view" / "unclear",
    "confidence": "low"/"medium"/"high",
    "description": "brief description of what you see"
}
"""
                
                vlm_result = query_vlm(
                    prompt=content_prompt,
                    image=temp_screenshot.name
                )
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    vlm_content_details = parsed
                    
                    is_cockpit = parsed.get('is_cockpit_view', False)
                    shows_canyon = parsed.get('shows_canyon_terrain', False)
                    is_first_person = parsed.get('is_first_person_perspective', False)
                    is_satellite = parsed.get('is_satellite_view', False)
                    overall = parsed.get('overall_assessment', 'unclear')
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score content
                    if is_cockpit:
                        vlm_content_score += 12
                        cockpit_visible = True
                        feedback_parts.append("✅ Cockpit view confirmed")
                    
                    if shows_canyon:
                        vlm_content_score += 10
                        canyon_visible = True
                        feedback_parts.append("✅ Grand Canyon terrain visible")
                    
                    if is_first_person and not is_satellite:
                        vlm_content_score += 5
                        feedback_parts.append("✅ First-person perspective")
                    elif is_satellite:
                        feedback_parts.append("❌ Satellite view (not cockpit)")
                    
                    if overall == 'flight_sim_canyon':
                        vlm_content_score += 3
                    
                    # Adjust for confidence
                    if confidence == 'low':
                        vlm_content_score = int(vlm_content_score * 0.7)
                    elif confidence == 'medium':
                        vlm_content_score = int(vlm_content_score * 0.85)
                    
                    feedback_parts.append(f"🖼️ Content VLM: {vlm_content_score}/30 points")
                else:
                    feedback_parts.append("⚠️ Content VLM analysis failed")
        except Exception as e:
            logger.warning(f"Could not analyze output screenshot: {e}")
            feedback_parts.append(f"⚠️ Screenshot analysis error")
        finally:
            if os.path.exists(temp_screenshot.name):
                os.unlink(temp_screenshot.name)
    else:
        feedback_parts.append("⚠️ Cannot analyze output (no file or no VLM)")
    
    score += vlm_content_score
    result_details['vlm_content'] = vlm_content_details
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = 100
    
    # Key criteria for passing:
    # - Must have file created during task
    # - Must have EITHER cockpit view OR canyon terrain visible
    key_criteria_met = (
        (result.get('file_created_during_task', False) or output_exists) and
        (cockpit_visible or canyon_visible or vlm_trajectory_score >= 15)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    result_details['score_breakdown'] = {
        'file_checks': score - vlm_trajectory_score - vlm_content_score,
        'vlm_trajectory': vlm_trajectory_score,
        'vlm_content': vlm_content_score,
        'total': score
    }
    
    if passed:
        summary = f"✅ PASSED: Score {score}/{max_score} - Flight simulator cockpit view captured"
    else:
        reasons = []
        if not output_exists:
            reasons.append("no output file")
        if not file_created_during_task and output_exists:
            reasons.append("file may predate task")
        if not cockpit_visible and not canyon_visible:
            reasons.append("cockpit/canyon not verified")
        if score < 60:
            reasons.append(f"score below threshold ({score}<60)")
        summary = f"❌ FAILED: Score {score}/{max_score} - {', '.join(reasons)}"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }