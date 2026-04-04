#!/usr/bin/env python3
"""
Verifier for Stabilize Shaky Video task
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


def verify_stabilize_shaky_video(traj, env_info, task_info):
    """
    Verify stabilize shaky video task completion.
    
    Checks:
    1. VLC config file exists and is accessible
    2. Video filter setting is present
    3. Filter contains stabilization-related keywords
    
    VLC can use several approaches for stabilization:
    - video-filter=transform (basic geometric transform)
    - video-filter=motiondetect (motion detection)
    - video-filter=stabilize (direct stabilization if available)
    - Any combination or custom filter
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy stabilization result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_stabilize_result.json", temp_result.name)
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Get filter information
        video_filter = result.get('video_filter', '').strip()
        filter_found = result.get('filter_found', False)
        transform_type = result.get('transform_type', '').strip()
        config_exists = result.get('config_file_exists', False)
        
        if not config_exists:
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 33,
                "feedback": "❌ VLC config file not found. Have you launched VLC at least once?"
            }
        
        # Criterion 2: Check if video filter setting exists
        if not filter_found or not video_filter:
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 33,
                "feedback": (
                    "❌ No video filters enabled in VLC.\n\n"
                    "💡 **How to enable stabilization**:\n"
                    "1. Open VLC Media Player\n"
                    "2. Go to Tools → Effects and Filters (or Ctrl+E)\n"
                    "3. Click on 'Video Effects' tab\n"
                    "4. Enable 'Geometry' or 'Transform' filter\n"
                    "5. OR enable any stabilization/motion filter if available\n"
                    "6. The setting should persist in VLC's configuration"
                )
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Video filter present: '{video_filter}'")
        
        # Criterion 3: Check if filter is stabilization-related
        # Accept various stabilization approaches
        stabilization_keywords = [
            'transform',      # VLC's transform filter can help with stabilization
            'stabilize',      # Direct stabilization filter
            'motion',         # Motion detection/smoothing
            'geometry',       # Geometry adjustments
            'rotate',         # Rotation correction
            'deshake'         # Deshake filter (if available)
        ]
        
        video_filter_lower = video_filter.lower()
        has_stabilization = any(keyword in video_filter_lower for keyword in stabilization_keywords)
        
        if not has_stabilization:
            feedback_parts.append(
                f"❌ Filter '{video_filter}' doesn't appear to provide stabilization"
            )
            feedback_parts.append(
                "💡 Expected filters: transform, stabilize, motion, or geometry-related"
            )
            os.unlink(temp_result.name)
            
            feedback = "\n".join(feedback_parts)
            score = int((criteria_met / total_criteria) * 100)
            
            return {
                "passed": False,
                "score": score,
                "feedback": feedback
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Stabilization filter enabled!")
        
        # Add transform type info if available
        if transform_type:
            feedback_parts.append(f"   Transform type: {transform_type}")
        
        # Success feedback
        feedback_parts.append("")
        feedback_parts.append("🎯 **Task Complete!**")
        feedback_parts.append("The shaky video will now play with real-time motion smoothing.")
        feedback_parts.append("This makes it more comfortable to watch without re-encoding.")
        
        os.unlink(temp_result.name)
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found. Task may not have completed."
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error parsing result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check completion marker (optional, gives additional confidence)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_stabilize_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completion verified")
        os.unlink(temp_marker.name)
    except Exception:
        # Completion marker is optional
        feedback_parts.append("⚠️ Completion marker not found (non-critical)")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
