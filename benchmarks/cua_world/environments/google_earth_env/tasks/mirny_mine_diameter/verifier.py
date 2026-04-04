#!/usr/bin/env python3
"""
Verifier for Mirny Mine Diameter Measurement task.

VERIFICATION STRATEGY:
1. File-based: Check if screenshot exists and was created during task (25 pts)
2. Anti-gaming: Verify file timestamps and reasonable size (15 pts)
3. Google Earth state: Check if GE was running and active (15 pts)
4. VLM trajectory: Verify workflow progression through frames (25 pts)
5. VLM content: Verify final screenshot shows measurement (20 pts)

PASS THRESHOLD: 60 points with key criteria met
(screenshot created during task OR VLM confirms measurement)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a measurement task in Google Earth Pro.

TASK: Navigate to Mirny Diamond Mine in Russia and measure the pit diameter.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful completion, the agent should progress through these stages:
1. Google Earth open - the globe/satellite view interface is visible
2. Navigation - searching or flying to Mirny, Russia
3. Location found - a large circular open-pit mine visible (distinctive spiral-terraced pit)
4. Measurement tool - Ruler tool opened and measurement line placed across the pit
5. Result shown - measurement distance displayed (approximately 1.1-1.3 km)

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth interface visible in any frame?
2. CIRCULAR_PIT_VISIBLE: Is a large circular open-pit mine (Mirny Mine) visible?
3. MEASUREMENT_TOOL_USED: Is the Ruler/measurement tool visible with a line drawn?
4. MEANINGFUL_PROGRESSION: Do frames show state changes (not same screen repeated)?

The Mirny Mine is distinctive: a massive circular excavation with spiral terraces carved into the sides, located in flat Siberian terrain.

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "circular_pit_visible": true/false,
    "measurement_tool_used": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying that a measurement task was completed in Google Earth Pro.

TASK: Measure the diameter of the Mirny Diamond Mine pit in Russia.

Look at this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro interface (satellite imagery, toolbar, search panel)?

2. MIRNY_MINE_VISIBLE: Is the Mirny Diamond Mine visible?
   - Large circular open-pit mine with spiral/terraced walls
   - Located in flat terrain (Siberian landscape)
   - Roughly 1.2 km in diameter
   - Distinctive inverted cone shape

3. MEASUREMENT_DISPLAYED: Is a measurement shown?
   - Ruler tool window or dialog visible
   - A measurement line drawn across the pit
   - Distance value displayed (should be approximately 1,100-1,300 meters or 1.1-1.3 km)

4. MEASUREMENT_CORRECT: If a measurement is visible:
   - Does the line span the pit diameter (not a partial chord)?
   - Is the measurement value in the expected range?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "mirny_mine_visible": true/false,
    "measurement_displayed": true/false,
    "measurement_line_spans_pit": true/false,
    "measurement_value_reasonable": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe what you observe"
}
"""


def verify_mirny_mine_diameter(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Mirny Mine diameter measurement task completion.
    
    Uses multi-signal verification:
    1. File existence and timestamp checks
    2. Google Earth state verification
    3. VLM trajectory analysis
    4. VLM final screenshot verification
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification",
            "details": {"error": "copy_from_env not provided"}
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # CRITERION 1: Load task result JSON (25 points for file checks)
    # ================================================================
    result_data = None
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
    # CRITERION 1a: Output file exists (10 points)
    # ================================================================
    output_exists = False
    file_created_during_task = False
    output_size = 0
    
    if result_data:
        output_info = result_data.get('output_file', {})
        output_exists = output_info.get('exists', False)
        file_created_during_task = output_info.get('created_during_task', False)
        output_size = output_info.get('size_bytes', 0)
        
        if output_exists:
            score += 10
            feedback_parts.append("✅ Screenshot file exists")
            details['output_exists'] = True
        else:
            feedback_parts.append("❌ Screenshot file not found")
            details['output_exists'] = False
    else:
        feedback_parts.append("⚠️ Could not verify output file (no result data)")
    
    # ================================================================
    # CRITERION 1b: File created during task (15 points - anti-gaming)
    # ================================================================
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task execution")
        details['created_during_task'] = True
    elif output_exists:
        feedback_parts.append("⚠️ File may have existed before task")
        details['created_during_task'] = False
        score += 5  # Partial credit
    
    # ================================================================
    # CRITERION 2: File size and format (10 points)
    # ================================================================
    min_size = metadata.get('min_screenshot_size_bytes', 10000)
    
    if output_size >= min_size:
        score += 10
        feedback_parts.append(f"✅ Valid file size ({output_size / 1024:.1f}KB)")
        details['file_size_valid'] = True
    elif output_size > 0:
        score += 3
        feedback_parts.append(f"⚠️ Small file size ({output_size / 1024:.1f}KB)")
        details['file_size_valid'] = False
    
    # Check image dimensions
    if result_data:
        width = result_data.get('output_file', {}).get('image_width', 0)
        height = result_data.get('output_file', {}).get('image_height', 0)
        if width > 100 and height > 100:
            score += 5
            feedback_parts.append(f"✅ Valid image dimensions ({width}x{height})")
        details['image_dimensions'] = f"{width}x{height}"
    
    # ================================================================
    # CRITERION 3: Google Earth state (15 points)
    # ================================================================
    ge_running = False
    ruler_visible = False
    
    if result_data:
        ge_info = result_data.get('google_earth', {})
        ge_running = ge_info.get('running', False)
        ruler_visible = ge_info.get('ruler_window_visible', False)
        cache_activity = ge_info.get('cache_activity', False)
        
        if ge_running:
            score += 8
            feedback_parts.append("✅ Google Earth was running")
            details['ge_running'] = True
        else:
            feedback_parts.append("❌ Google Earth not running")
            details['ge_running'] = False
        
        if ruler_visible:
            score += 7
            feedback_parts.append("✅ Ruler tool window detected")
            details['ruler_used'] = True
        elif cache_activity:
            score += 3
            feedback_parts.append("⚠️ Cache activity detected (navigation occurred)")
            details['cache_activity'] = True
    
    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (25 points)
    # ================================================================
    trajectory_score = 0
    
    if query_vlm and traj:
        # Sample trajectory frames
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames:
                details['trajectory_frames_count'] = len(frames)
                
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['trajectory_vlm_response'] = parsed
                    
                    ge_visible = parsed.get('google_earth_visible', False)
                    pit_visible = parsed.get('circular_pit_visible', False)
                    measurement_used = parsed.get('measurement_tool_used', False)
                    progression = parsed.get('meaningful_progression', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score trajectory criteria
                    if ge_visible:
                        trajectory_score += 5
                    if pit_visible:
                        trajectory_score += 10
                    if measurement_used:
                        trajectory_score += 7
                    if progression:
                        trajectory_score += 3
                    
                    # Confidence adjustment
                    if confidence == 'high':
                        trajectory_score = min(25, int(trajectory_score * 1.1))
                    elif confidence == 'low':
                        trajectory_score = int(trajectory_score * 0.8)
                    
                    stages = parsed.get('stages_observed', [])
                    feedback_parts.append(f"✅ Trajectory analysis: {len(stages)} stages identified")
                else:
                    feedback_parts.append("⚠️ Trajectory VLM analysis failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except ImportError:
            # Fallback if vlm module not available
            feedback_parts.append("⚠️ Trajectory analysis unavailable")
        except Exception as e:
            logger.warning(f"Trajectory verification error: {e}")
            feedback_parts.append(f"⚠️ Trajectory analysis error")
            details['trajectory_error'] = str(e)
    
    score += trajectory_score
    details['trajectory_score'] = trajectory_score
    
    # ================================================================
    # CRITERION 5: VLM Final Screenshot Verification (20 points)
    # ================================================================
    final_score = 0
    
    if query_vlm:
        # Try to get final screenshot
        final_screenshot = None
        
        # First try from task result
        if result_data and result_data.get('screenshots', {}).get('final_exists'):
            temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final.png", temp_final.name)
                final_screenshot = temp_final.name
            except Exception as e:
                logger.warning(f"Could not copy final screenshot: {e}")
            finally:
                # Note: don't delete yet, needed for VLM
                pass
        
        # Also try from trajectory
        if not final_screenshot:
            try:
                from gym_anything.vlm import get_final_screenshot
                final_screenshot = get_final_screenshot(traj)
            except:
                pass
        
        if final_screenshot:
            vlm_result = query_vlm(
                prompt=FINAL_SCREENSHOT_PROMPT,
                image=final_screenshot
            )
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['final_vlm_response'] = parsed
                
                is_ge = parsed.get('is_google_earth', False)
                mine_visible = parsed.get('mirny_mine_visible', False)
                measurement_shown = parsed.get('measurement_displayed', False)
                line_correct = parsed.get('measurement_line_spans_pit', False)
                value_reasonable = parsed.get('measurement_value_reasonable', False)
                confidence = parsed.get('confidence', 'low')
                
                # Score final screenshot criteria
                if is_ge:
                    final_score += 4
                if mine_visible:
                    final_score += 6
                if measurement_shown:
                    final_score += 5
                if line_correct:
                    final_score += 3
                if value_reasonable:
                    final_score += 2
                
                # Confidence adjustment
                if confidence == 'high':
                    final_score = min(20, int(final_score * 1.1))
                elif confidence == 'low':
                    final_score = int(final_score * 0.8)
                
                reasoning = parsed.get('reasoning', '')
                if mine_visible and measurement_shown:
                    feedback_parts.append("✅ Final screenshot shows mine with measurement")
                elif mine_visible:
                    feedback_parts.append("⚠️ Mine visible but measurement unclear")
                else:
                    feedback_parts.append("⚠️ Could not confirm mine visibility")
            else:
                feedback_parts.append("⚠️ Final screenshot VLM analysis failed")
            
            # Clean up temp file
            if final_screenshot and os.path.exists(final_screenshot) and final_screenshot.startswith('/tmp'):
                try:
                    os.unlink(final_screenshot)
                except:
                    pass
        else:
            feedback_parts.append("⚠️ No final screenshot available for verification")
    
    score += final_score
    details['final_screenshot_score'] = final_score
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    
    # Key criteria for passing:
    # - Must have screenshot file created during task OR strong VLM confirmation
    key_criteria_met = (
        (output_exists and file_created_during_task) or
        (trajectory_score >= 15) or
        (final_score >= 12)
    )
    
    # Minimum score threshold
    passed = score >= 60 and key_criteria_met
    
    # Cap score at max
    score = min(score, max_score)
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    details['key_criteria_met'] = key_criteria_met
    details['total_score'] = score
    details['max_score'] = max_score
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }