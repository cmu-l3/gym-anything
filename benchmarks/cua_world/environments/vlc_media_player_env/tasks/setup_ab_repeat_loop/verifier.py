#!/usr/bin/env python3
"""
Verifier for A-B Repeat Loop task

This task is challenging to verify programmatically because:
1. VLC's A-B loop state is not easily exposed via RC interface
2. The loop points are set interactively and may not persist in config
3. We need to infer loop activity from multiple signals

Verification strategy:
- Check VLC is running
- Check correct video is loaded
- Look for any indicators of loop configuration
- Use screenshot analysis as fallback if available
- Apply lenient scoring given verification difficulty
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ab_repeat_loop(traj, env_info, task_info):
    """
    Verify A-B repeat loop task completion.
    
    Verification criteria:
    1. VLC process was running
    2. Correct video file was loaded
    3. Some indication of loop configuration exists
    4. Task completion marker present
    
    Given the difficulty of programmatically verifying A-B loop state,
    we use a combination of signals and apply lenient scoring.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    try:
        # Load task result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        
        try:
            copy_from_env("/tmp/vlc_ab_loop_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result file: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Result file not found: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        vlc_running = result.get('vlc_running', False)
        video_loaded = result.get('video_loaded', False)
        ab_loop_active = result.get('ab_loop_active', False)
        runtime_captured = result.get('runtime_captured', False)
        screenshot_available = result.get('screenshot_available', False)
        
        # Criterion 1: VLC was running
        if vlc_running or vlc_running == "true":
            criteria_met += 1
            feedback_parts.append("✅ VLC was running")
            logger.info("VLC process was active")
        else:
            feedback_parts.append("❌ VLC was not running")
            logger.warning("VLC process was not detected")
        
        # Criterion 2: Correct video loaded
        if video_loaded or video_loaded == "true":
            criteria_met += 1
            feedback_parts.append("✅ Interview video loaded")
            logger.info("Research interview video was loaded")
        else:
            feedback_parts.append("⚠️ Interview video not detected")
            logger.warning("Could not confirm video was loaded")
        
        # Criterion 3: Loop configuration indicators
        # This is the hardest to verify, so we look for any positive signals
        loop_indicators = 0
        
        if ab_loop_active or ab_loop_active == "true":
            loop_indicators += 1
            logger.info("A-B loop indicator found in VLC status")
        
        if runtime_captured or runtime_captured == "true":
            loop_indicators += 1
            logger.info("Runtime state was captured successfully")
        
        # Check if trajectory shows loop-related actions
        # (This would require analyzing the actual trajectory, which we can't do fully here)
        # As a proxy, if we got this far, the agent likely attempted the task
        
        if loop_indicators > 0:
            criteria_met += 1
            feedback_parts.append(f"✅ Loop configuration detected ({loop_indicators} indicators)")
            logger.info(f"Found {loop_indicators} loop indicators")
        else:
            # Give partial credit if VLC was running with correct video
            # The agent may have configured the loop but we can't detect it
            if vlc_running and video_loaded:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Loop state unclear, but VLC was active with video")
                logger.warning("Could not confirm A-B loop, giving partial credit")
            else:
                feedback_parts.append("❌ No loop configuration detected")
                logger.warning("No evidence of A-B loop configuration")
        
        # Criterion 4: Task completion marker
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_ab_loop_completed.txt", temp_marker.name)
            
            with open(temp_marker.name, 'r') as f:
                marker_content = f.read()
            
            if marker_content and len(marker_content) > 10:
                criteria_met += 1
                feedback_parts.append("✅ Task completion confirmed")
                logger.info("Task completion marker found")
            
            os.unlink(temp_marker.name)
        except Exception as e:
            feedback_parts.append("⚠️ Completion marker not found")
            logger.warning(f"Could not read completion marker: {e}")
        
        # Clean up temp result file
        os.unlink(temp_result.name)
        
        # Optionally: Copy screenshot for manual inspection
        if screenshot_available:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/vlc_ab_loop_screenshot.png", temp_screenshot.name)
                logger.info(f"Screenshot available for manual verification: {temp_screenshot.name}")
                feedback_parts.append("📸 Screenshot captured for review")
                # Don't delete screenshot - it may be useful for debugging
            except Exception as e:
                logger.warning(f"Could not copy screenshot: {e}")
        
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing result JSON: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Calculate score
    # Use total_criteria as denominator, but criteria_met may be fractional
    score = int((criteria_met / total_criteria) * 100)
    
    # Pass threshold is 70%
    passed = score >= 70
    
    # Construct feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add contextual feedback based on score
    if passed:
        feedback += " | ✅ A-B repeat loop task completed successfully!"
    elif score >= 50:
        feedback += " | ⚠️ Partial completion - loop configuration uncertain"
    else:
        feedback += " | ❌ Task not completed - please configure A-B loop"
    
    logger.info(f"Final score: {score}/100 (passed: {passed})")
    logger.info(f"Criteria met: {criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
