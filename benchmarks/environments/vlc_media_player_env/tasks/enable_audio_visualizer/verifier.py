#!/usr/bin/env python3
"""
Verifier for Enable Audio Visualizer task (enable_audio_visualizer@1)

Checks:
1. Screenshot file exists and is valid
2. Screenshot has sufficient size (>100 KB suggests actual visualization content)
3. Screenshot has reasonable resolution (>640x480 suggests full window capture)
"""

import sys
import os
import logging
import tempfile
import json

# Use relative path to utils - verifier runs on host, not container
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)


def verify_audio_visualizer(traj, env_info, task_info):
    """
    Verify audio visualizer task completion.
    
    Primary verification: Screenshot exists and has properties consistent with
    captured visualization (file size, resolution).
    
    Returns:
        dict with keys: passed (bool), score (int 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # ============================================================
    # Criterion 1: Screenshot file exists
    # ============================================================
    screenshot_path = "/tmp/vlc_audio_viz_screenshot.png"
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        copy_from_env(screenshot_path, temp_screenshot.name)
        
        if not os.path.exists(temp_screenshot.name):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Screenshot file not found - visualization was not captured"
            }
        
        file_size = os.path.getsize(temp_screenshot.name)
        file_size_kb = file_size / 1024
        
        criteria_met += 1
        feedback_parts.append(f"✅ Screenshot exists ({file_size_kb:.1f} KB)")
        
        # ============================================================
        # Criterion 2: Screenshot has reasonable file size
        # ============================================================
        # Visualization screenshots typically >100 KB due to complex graphics
        # If too small, likely a blank screen or error
        MIN_SIZE_KB = 100
        
        if file_size_kb >= MIN_SIZE_KB:
            criteria_met += 1
            feedback_parts.append(f"✅ Screenshot size suggests content (≥{MIN_SIZE_KB} KB)")
        elif file_size_kb >= 50:
            # Partial credit for smaller but not tiny files
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Screenshot size acceptable but small ({file_size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"❌ Screenshot too small ({file_size_kb:.1f} KB) - may be blank or corrupted")
        
        # ============================================================
        # Criterion 3: Screenshot has reasonable resolution
        # ============================================================
        try:
            from PIL import Image
            
            img = Image.open(temp_screenshot.name)
            width, height = img.size
            img_format = img.format
            
            feedback_parts.append(f"📐 Resolution: {width}×{height} ({img_format})")
            
            MIN_WIDTH = 640
            MIN_HEIGHT = 480
            
            if width >= MIN_WIDTH and height >= MIN_HEIGHT:
                criteria_met += 1
                feedback_parts.append(f"✅ Resolution sufficient for window capture")
            else:
                feedback_parts.append(f"⚠️ Resolution low ({width}×{height}) - may not capture full window")
        
        except ImportError:
            logger.warning("PIL not available - skipping resolution check")
            # Give partial credit if PIL unavailable but file size is good
            if file_size_kb >= MIN_SIZE_KB:
                criteria_met += 0.5
                feedback_parts.append("⚠️ Resolution check skipped (PIL unavailable)")
            else:
                feedback_parts.append("⚠️ Cannot verify resolution (PIL unavailable)")
        
        except Exception as e:
            logger.error(f"Error checking image properties: {e}")
            feedback_parts.append(f"⚠️ Could not validate image properties: {str(e)}")
        
        finally:
            # Clean up temp file
            try:
                os.unlink(temp_screenshot.name)
            except:
                pass
    
    except Exception as e:
        logger.error(f"Error copying screenshot: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to access screenshot: {str(e)}"
        }
    
    # ============================================================
    # Supplementary: Check metadata
    # ============================================================
    temp_metadata = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_audio_viz_metadata.json", temp_metadata.name)
        
        with open(temp_metadata.name, 'r') as f:
            metadata = json.load(f)
        
        screenshot_found = metadata.get('screenshot_found', False)
        original_path = metadata.get('screenshot_path', 'unknown')
        
        if screenshot_found:
            feedback_parts.append(f"📁 Original location: {os.path.basename(original_path)}")
        
        os.unlink(temp_metadata.name)
    
    except Exception as e:
        logger.warning(f"Could not read metadata: {e}")
        # Not critical for scoring
    
    # ============================================================
    # Supplementary: Check completion marker
    # ============================================================
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_viz_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completion marker found")
        
        os.unlink(temp_marker.name)
    
    except Exception:
        # Completion marker is not critical if we have screenshot
        if criteria_met >= 2:
            feedback_parts.append("⚠️ Completion marker not found (but screenshot exists)")
        else:
            feedback_parts.append("⚠️ Completion marker not found")
    
    # ============================================================
    # Calculate final score
    # ============================================================
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback += "\n\n✅ TASK SUCCESSFUL!"
        feedback += "\n   Agent successfully enabled audio visualization and captured screenshot."
        feedback += "\n   Screenshot shows sufficient size/resolution consistent with visualization display."
    else:
        feedback += "\n\n❌ TASK FAILED"
        if criteria_met == 0:
            feedback += "\n   No screenshot was captured."
        elif criteria_met < 2:
            feedback += "\n   Screenshot quality insufficient (too small or low resolution)."
        feedback += "\n   Required: VLC window with audio visualization (spectrum/waveform) visible."
    
    # Additional context
    feedback += "\n\nNote: Actual visual inspection of screenshot recommended to confirm"
    feedback += "\n      visualization type and quality (spectrum analyzer, waveform, etc.)."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
