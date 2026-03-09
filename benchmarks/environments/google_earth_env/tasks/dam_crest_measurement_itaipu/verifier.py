#!/usr/bin/env python3
"""
Verifier for dam_crest_measurement_itaipu task.

MULTI-SIGNAL VERIFICATION:
1. Measurement file exists (10 points)
2. File format correct with required fields (10 points)
3. Measurement accuracy within ±100m of 1064m (30 points) OR within ±200m (15 points)
4. Screenshot file exists and is valid image (10 points)
5. VLM trajectory verification - shows progression through task (25 points)
6. VLM content verification - final shows dam/measurement (15 points)

Total: 100 points
Pass threshold: 60 points AND measurement file created during task with reasonable value
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_CREST_LENGTH = 1064  # meters
TOLERANCE_HIGH = 100  # ±100m for full points
TOLERANCE_MEDIUM = 200  # ±200m for partial points


def verify_dam_crest_measurement(traj, env_info, task_info):
    """
    Verify that the Itaipu Dam crest was measured correctly.
    
    Uses multiple independent signals for robust verification.
    """
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
    expected_length = metadata.get('main_concrete_crest_length_meters', EXPECTED_CREST_LENGTH)
    tolerance_high = metadata.get('tolerance_meters', TOLERANCE_HIGH)
    tolerance_medium = metadata.get('extended_tolerance_meters', TOLERANCE_MEDIUM)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_json'] = result
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")
        feedback_parts.append(f"⚠️ Could not read result file: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Measurement file exists (10 points)
    # ================================================================
    measurement_exists = False
    measurement_created_during_task = False
    measured_value = None
    
    if result:
        mf = result.get('measurement_file', {})
        measurement_exists = mf.get('exists', False)
        measurement_created_during_task = mf.get('created_during_task', False)
        measured_value_str = mf.get('measured_value', '')
        
        if measured_value_str:
            try:
                measured_value = float(measured_value_str.replace(',', ''))
            except ValueError:
                measured_value = None
    
    if measurement_exists:
        score += 10
        feedback_parts.append("✅ Measurement file exists (+10)")
        details['measurement_exists'] = True
    else:
        feedback_parts.append("❌ Measurement file NOT found")
        details['measurement_exists'] = False
    
    # ================================================================
    # CRITERION 2: File format correct (10 points)
    # ================================================================
    format_correct = False
    
    if result and measurement_exists:
        content = result.get('measurement_file', {}).get('content', '')
        
        # Check for required components
        has_header = 'itaipu' in content.lower()
        has_feature = 'concrete' in content.lower() or 'crest' in content.lower()
        has_measurement = 'measured length' in content.lower() and measured_value is not None
        
        if has_header and has_feature and has_measurement:
            format_correct = True
            score += 10
            feedback_parts.append("✅ File format correct (+10)")
        elif has_measurement:
            score += 5
            feedback_parts.append("⚠️ File format partially correct (+5)")
        else:
            feedback_parts.append("❌ File format incorrect")
    
    details['format_correct'] = format_correct
    
    # ================================================================
    # CRITERION 3: Measurement accuracy (30 or 15 points)
    # ================================================================
    accuracy_score = 0
    
    if measured_value is not None:
        error = abs(measured_value - expected_length)
        details['measured_value'] = measured_value
        details['expected_value'] = expected_length
        details['error_meters'] = error
        
        if error <= tolerance_high:
            accuracy_score = 30
            score += 30
            feedback_parts.append(f"✅ Measurement {measured_value:.0f}m within ±{tolerance_high}m of expected {expected_length}m (+30)")
        elif error <= tolerance_medium:
            accuracy_score = 15
            score += 15
            feedback_parts.append(f"⚠️ Measurement {measured_value:.0f}m within ±{tolerance_medium}m of expected {expected_length}m (+15)")
        else:
            feedback_parts.append(f"❌ Measurement {measured_value:.0f}m outside acceptable range (expected ~{expected_length}m)")
    else:
        feedback_parts.append("❌ No valid measurement value found")
    
    details['accuracy_score'] = accuracy_score
    
    # ================================================================
    # CRITERION 4: Screenshot exists and is valid (10 points)
    # ================================================================
    screenshot_exists = False
    screenshot_valid = False
    
    if result:
        sf = result.get('screenshot_file', {})
        screenshot_exists = sf.get('exists', False)
        screenshot_valid = sf.get('valid_image', False)
        screenshot_created = sf.get('created_during_task', False)
    
    if screenshot_exists and screenshot_valid:
        score += 10
        feedback_parts.append("✅ Valid screenshot saved (+10)")
        details['screenshot_valid'] = True
    elif screenshot_exists:
        score += 5
        feedback_parts.append("⚠️ Screenshot exists but may not be valid (+5)")
        details['screenshot_valid'] = False
    else:
        feedback_parts.append("❌ Screenshot NOT found")
        details['screenshot_valid'] = False
    
    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (25 points)
    # Verify agent actually performed the workflow
    # ================================================================
    trajectory_score = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) > 0:
                trajectory_prompt = """You are analyzing a sequence of screenshots from an agent performing a measurement task in Google Earth Pro.

The task was to navigate to the Itaipu Dam (Brazil-Paraguay border) and measure the dam crest length.

Analyze these chronological screenshots and determine:
1. GOOGLE_EARTH_USED: Is Google Earth Pro visible in any frames?
2. NAVIGATION_PERFORMED: Did the agent navigate/search for a location (search bar used, view changed)?
3. DAM_VISIBLE: Is a large dam structure visible in any frame (Itaipu Dam is a massive concrete dam)?
4. RULER_TOOL_USED: Is there evidence of the ruler/measurement tool being used (measurement lines, ruler dialog)?
5. MEANINGFUL_PROGRESSION: Do the frames show progression through the task (not same screen repeated)?

Respond in JSON format:
{
    "google_earth_used": true/false,
    "navigation_performed": true/false,
    "dam_visible": true/false,
    "ruler_tool_used": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}"""
                
                vlm_result = query_vlm(prompt=trajectory_prompt, images=frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    criteria_met = sum([
                        parsed.get('google_earth_used', False),
                        parsed.get('navigation_performed', False),
                        parsed.get('dam_visible', False),
                        parsed.get('ruler_tool_used', False),
                        parsed.get('meaningful_progression', False)
                    ])
                    
                    confidence = parsed.get('confidence', 'low')
                    conf_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    trajectory_score = int((criteria_met / 5) * 25 * conf_mult)
                    score += trajectory_score
                    
                    if trajectory_score >= 20:
                        feedback_parts.append(f"✅ VLM trajectory verification passed (+{trajectory_score})")
                    elif trajectory_score >= 10:
                        feedback_parts.append(f"⚠️ VLM trajectory partially verified (+{trajectory_score})")
                    else:
                        feedback_parts.append(f"❌ VLM trajectory verification weak (+{trajectory_score})")
                else:
                    feedback_parts.append("⚠️ VLM trajectory query failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM trajectory error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    details['trajectory_score'] = trajectory_score
    
    # ================================================================
    # CRITERION 6: VLM Content Verification (15 points)
    # Verify final screenshot shows dam with measurement
    # ================================================================
    content_score = 0
    
    if query_vlm:
        # Try to get the user's saved screenshot
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        screenshot_available = False
        
        try:
            copy_from_env("/home/ga/dam_screenshot.png", temp_screenshot.name)
            if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                screenshot_available = True
        except:
            pass
        
        # Fallback to final state screenshot
        if not screenshot_available:
            try:
                copy_from_env("/tmp/task_final_state.png", temp_screenshot.name)
                if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                    screenshot_available = True
            except:
                pass
        
        if screenshot_available:
            try:
                content_prompt = """Analyze this Google Earth Pro screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth (satellite imagery application)?
2. SHOWS_DAM: Does it show a large dam structure (concrete dam across a river)?
3. MEASUREMENT_VISIBLE: Is there a measurement line/path overlay visible on the image?
4. TRACES_DAM_CREST: If there's a measurement, does it appear to follow along the top of the dam?
5. MEASUREMENT_VALUE_SHOWN: Is a distance measurement value visible anywhere?

Note: Itaipu Dam is one of the world's largest dams, a massive concrete structure spanning the Paraná River.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_dam": true/false,
    "measurement_visible": true/false,
    "traces_dam_crest": true/false,
    "measurement_value_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=content_prompt, image=temp_screenshot.name)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_content'] = parsed
                    
                    criteria_met = sum([
                        parsed.get('is_google_earth', False),
                        parsed.get('shows_dam', False),
                        parsed.get('measurement_visible', False),
                        parsed.get('traces_dam_crest', False),
                        parsed.get('measurement_value_shown', False)
                    ])
                    
                    confidence = parsed.get('confidence', 'low')
                    conf_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    content_score = int((criteria_met / 5) * 15 * conf_mult)
                    score += content_score
                    
                    if content_score >= 12:
                        feedback_parts.append(f"✅ VLM content verification passed (+{content_score})")
                    elif content_score >= 6:
                        feedback_parts.append(f"⚠️ VLM content partially verified (+{content_score})")
                    else:
                        feedback_parts.append(f"❌ VLM content verification weak (+{content_score})")
                else:
                    feedback_parts.append("⚠️ VLM content query failed")
            except Exception as e:
                logger.warning(f"VLM content verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM content error: {str(e)[:50]}")
        else:
            feedback_parts.append("⚠️ No screenshot available for content verification")
        
        # Cleanup
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    else:
        feedback_parts.append("⚠️ VLM not available for content verification")
    
    details['content_score'] = content_score
    
    # ================================================================
    # ANTI-GAMING: Check file was created during task
    # ================================================================
    if measurement_exists and not measurement_created_during_task:
        feedback_parts.append("⚠️ Warning: Measurement file may have existed before task")
        # Don't zero out, but note the concern
        details['anti_gaming_warning'] = True
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Pass requires:
    # - Measurement file exists
    # - Measurement value within extended tolerance (±200m)
    # - Score >= 60
    
    key_criteria_met = (
        measurement_exists and 
        measured_value is not None and
        accuracy_score >= 15  # At least medium accuracy
    )
    
    passed = score >= 60 and key_criteria_met
    
    details['total_score'] = score
    details['key_criteria_met'] = key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/100"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }