#!/usr/bin/env python3
"""
Verifier for Chrome Video Playback Speed Control Task (video_playback_speed@1)
Task: Navigate to video page and adjust playback speed to 1.5x

Verification Strategy:
- Use Chrome DevTools Protocol (CDP) over WebSocket to execute JavaScript
- Query video element's playbackRate property directly from the DOM
- Verify URL is correct video page
- Validate playback rate is 1.5 (±0.01 tolerance)
- Check video element exists and is accessible
"""

import logging
import sys
import os
import json
import tempfile
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import websocket for CDP communication
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    logger.warning("websocket-client not available, will try alternative methods")

# Try to import requests for HTTP-based CDP
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False
    logger.warning("requests not available")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for video_playback_speed@1.
    
    Verifies that video playback speed has been set to 1.5x.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get tab information
        tab_info = get_tab_info(copy_from_env)
        if not tab_info:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not retrieve tab information from Chrome"
            }
        
        # Verify correct page is loaded
        tab_url = tab_info.get('url', '')
        if 'video_test_page' not in tab_url and 'video' not in tab_url.lower():
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Not on video page. Current URL: {tab_url}"
            }
        
        # Query video playback rate via CDP
        playback_info = query_video_playback_rate(tab_info)
        
        if not playback_info.get('success', False):
            error_msg = playback_info.get('error', 'Unknown error')
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to query video playback rate: {error_msg}"
            }
        
        # Validate playback rate
        playback_rate = playback_info.get('playbackRate')
        if playback_rate is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Video element not found or playbackRate not accessible"
            }
        
        # Evaluate the playback rate
        is_valid, score, feedback = validate_playback_rate(playback_rate, playback_info)
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "playback_rate": playback_rate,
                "target": 1.5,
                "video_found": playback_info.get('videoFound', False),
                "video_duration": playback_info.get('duration'),
                "video_paused": playback_info.get('paused'),
                "current_time": playback_info.get('currentTime')
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_tab_info(copy_from_env):
    """
    Get active tab information from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with tab information or None
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try to copy tab info file
        try:
            copy_from_env("/tmp/active_tab.json", temp_file.name)
        except Exception as e:
            logger.warning(f"Failed to copy active_tab.json: {e}")
            # Try alternative
            try:
                copy_from_env("/tmp/video_tab_info.json", temp_file.name)
            except Exception as e2:
                logger.error(f"Failed to copy video_tab_info.json: {e2}")
                return None
        
        with open(temp_file.name, 'r') as f:
            tab_info = json.load(f)
        
        logger.info(f"Retrieved tab info: {tab_info.get('url', 'unknown')}")
        return tab_info
        
    except Exception as e:
        logger.error(f"Error getting tab info: {e}")
        return None
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def query_video_playback_rate(tab_info):
    """
    Query video element's playback rate using CDP.
    
    Args:
        tab_info: Dict containing tab information including WebSocket URL
        
    Returns:
        Dict with playback rate information
    """
    ws_url = tab_info.get('webSocketDebuggerUrl', '')
    
    if not ws_url:
        logger.warning("No WebSocket URL available, cannot query video element")
        return {
            "success": False,
            "error": "No WebSocket debugger URL available"
        }
    
    if not HAS_WEBSOCKET:
        logger.warning("websocket-client library not available")
        return {
            "success": False,
            "error": "WebSocket library not available (install websocket-client)"
        }
    
    try:
        # Connect to Chrome DevTools via WebSocket
        ws = websocket.create_connection(ws_url, timeout=10)
        
        # JavaScript code to query video element
        js_code = """
        (function() {
            const video = document.querySelector('video');
            if (!video) {
                return { videoFound: false };
            }
            return {
                videoFound: true,
                playbackRate: video.playbackRate,
                paused: video.paused,
                currentTime: video.currentTime,
                duration: video.duration,
                readyState: video.readyState,
                src: video.currentSrc || video.src
            };
        })()
        """
        
        # Send CDP command to evaluate JavaScript
        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": js_code,
                "returnByValue": True
            }
        }
        
        ws.send(json.dumps(command))
        
        # Wait for response
        response_text = ws.recv()
        response = json.loads(response_text)
        
        ws.close()
        
        # Parse response
        if 'result' in response and 'result' in response['result']:
            result_value = response['result']['result'].get('value', {})
            
            if not result_value.get('videoFound', False):
                return {
                    "success": False,
                    "error": "Video element not found on page"
                }
            
            return {
                "success": True,
                "playbackRate": result_value.get('playbackRate'),
                "videoFound": True,
                "paused": result_value.get('paused'),
                "currentTime": result_value.get('currentTime'),
                "duration": result_value.get('duration'),
                "readyState": result_value.get('readyState'),
                "src": result_value.get('src', '')
            }
        else:
            return {
                "success": False,
                "error": f"Unexpected CDP response: {response}"
            }
        
    except Exception as e:
        logger.error(f"Error querying video via CDP WebSocket: {e}")
        return {
            "success": False,
            "error": f"CDP WebSocket error: {str(e)}"
        }


def validate_playback_rate(playback_rate, playback_info):
    """
    Validate that playback rate is correctly set to 1.5x.
    
    Args:
        playback_rate: Float playback rate value
        playback_info: Additional video information
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    TARGET_RATE = 1.5
    TOLERANCE = 0.01
    
    try:
        rate = float(playback_rate)
    except (TypeError, ValueError):
        return False, 0, f"Invalid playback rate value: {playback_rate}"
    
    # Check if rate is exactly at target (with tolerance)
    rate_diff = abs(rate - TARGET_RATE)
    
    # Perfect match
    if rate_diff < TOLERANCE:
        feedback_parts = [
            f"✓ Playback rate correctly set to {rate:.2f}x",
            f"✓ Video element found and accessible",
        ]
        
        # Additional positive feedback
        if not playback_info.get('paused', True):
            feedback_parts.append("✓ Video is playing")
        
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nTarget: {TARGET_RATE}x | Actual: {rate:.2f}x | Difference: {rate_diff:.3f}"
        feedback += f"\nResult: PASSED ✓"
        
        return True, 100, feedback
    
    # Close but not exact (1.45-1.55, excluding exact 1.5)
    if 1.45 <= rate <= 1.55:
        return True, 85, f"Playback rate at {rate:.2f}x (close to target 1.5x, difference: {rate_diff:.3f})"
    
    # Wrong but reasonable speed
    if rate > 1.0 and rate != TARGET_RATE:
        return False, 40, f"Playback rate is {rate:.2f}x, but target is {TARGET_RATE}x (difference: {rate_diff:.2f})"
    
    # Still at default
    if rate == 1.0:
        return False, 0, f"Playback rate unchanged at 1.0x (default). Please set to {TARGET_RATE}x."
    
    # Slower than normal
    if rate < 1.0:
        return False, 20, f"Playback rate is {rate:.2f}x (slower than normal). Target is {TARGET_RATE}x."
    
    # Any other case
    return False, 30, f"Playback rate is {rate:.2f}x, expected {TARGET_RATE}x"
