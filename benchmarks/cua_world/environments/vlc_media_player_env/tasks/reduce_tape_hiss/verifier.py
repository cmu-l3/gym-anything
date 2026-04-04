#!/usr/bin/env python3
"""
Verifier for reduce_tape_hiss@1 task
Checks if VLC audio filters have been properly configured for noise reduction
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


def parse_audio_filters(filter_string):
    """
    Parse the audio-filter string from VLC config.
    Format is typically: "filter1:filter2:filter3"
    
    Returns:
        List of filter names
    """
    if not filter_string or filter_string == '':
        return []
    
    # Split by colon and filter out empty strings
    filters = [f.strip() for f in filter_string.split(':') if f.strip()]
    return filters


def is_noise_reduction_filter(filter_name):
    """
    Check if a filter is typically used for noise reduction.
    
    Returns:
        Boolean indicating if filter is noise-reduction related
    """
    noise_reduction_filters = [
        'compressor',      # Dynamic range compressor
        'normvol',         # Volume normalizer
        'norm',            # Another normalizer variant
        'spatializer',     # Spatializer (can help reduce noise)
        'param_eq',        # Parametric equalizer
        'equalizer',       # Graphic equalizer
        'gain',            # Gain control
    ]
    
    filter_lower = filter_name.lower()
    return any(nr_filter in filter_lower for nr_filter in noise_reduction_filters)


def verify_noise_reduction(traj, env_info, task_info):
    """
    Verify noise reduction task completion.
    
    Checks:
    1. Result file exists and is accessible
    2. Audio filters are enabled in VLC configuration
    3. Appropriate noise reduction filters are configured
    
    Args:
        traj: Trajectory information (not used in this verifier)
        env_info: Environment info including copy_from_env function
        task_info: Task information (not used in this verifier)
    
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
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
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Criterion 1: Check if result file exists
        try:
            copy_from_env("/tmp/vlc_noise_reduction_result.json", temp_result.name)
            criteria_met += 1
            feedback_parts.append("✅ Result file accessible")
        except Exception as e:
            logger.error(f"Error copying result file: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Result file not found: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        logger.info(f"Result data: {result}")
        
        # Extract result data
        config_found = result.get('config_found', False)
        audio_filters_str = result.get('audio_filters', '')
        filter_count = result.get('filter_count', 0)
        filter_details = result.get('filter_details', {})
        
        if not config_found:
            return {
                "passed": False,
                "score": 33,
                "feedback": "❌ VLC configuration file not found"
            }
        
        # Parse audio filters
        audio_filters = parse_audio_filters(audio_filters_str)
        
        logger.info(f"Parsed audio filters: {audio_filters}")
        logger.info(f"Filter count: {filter_count}")
        
        # Criterion 2: Check if any audio filters are enabled
        if audio_filters and len(audio_filters) > 0:
            criteria_met += 1
            filter_list = ', '.join(audio_filters)
            feedback_parts.append(f"✅ Audio filters enabled: {filter_list}")
            logger.info(f"Audio filters found: {filter_list}")
        else:
            feedback_parts.append("❌ No audio filters enabled")
            logger.warning("No audio filters found in configuration")
        
        # Criterion 3: Check if noise reduction filters are configured
        noise_reduction_filters = [f for f in audio_filters if is_noise_reduction_filter(f)]
        
        if noise_reduction_filters:
            criteria_met += 1
            nr_filter_list = ', '.join(noise_reduction_filters)
            feedback_parts.append(f"✅ Noise reduction filters active: {nr_filter_list}")
            logger.info(f"Noise reduction filters: {nr_filter_list}")
        elif audio_filters:
            # Give partial credit if ANY audio filter is enabled
            # (user might have found a creative solution)
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Audio filters present but not typical noise reduction filters")
            logger.info("Non-standard filters used, giving partial credit")
        else:
            feedback_parts.append("❌ No noise reduction filters configured")
            logger.warning("No noise reduction filters found")
        
        # Additional info: Check for filter settings
        if isinstance(filter_details, dict) and filter_details:
            setting_count = sum(v for k, v in filter_details.items() if isinstance(v, int))
            if setting_count > 0:
                feedback_parts.append(f"📊 Filter parameters configured: {setting_count} settings")
                logger.info(f"Filter settings found: {setting_count}")
        
        # Cleanup temp file
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check completion marker (optional bonus)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_noise_reduction_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.info("Completion marker not found (not critical)")
        # Don't penalize for missing marker
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        summary = f"🎉 TASK PASSED (Score: {score}/100) - Audio filters configured for noise reduction"
    else:
        summary = f"❌ TASK FAILED (Score: {score}/100) - Audio filters not properly configured"
    
    final_feedback = f"{summary} | {feedback}"
    
    logger.info(f"Final verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }
