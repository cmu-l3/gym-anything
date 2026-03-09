#!/usr/bin/env python3
"""
Verifier for Embed Video Metadata task
Checks that correct metadata was embedded into the video file
"""

import json
import logging
import os
import sys
import tempfile
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected metadata values
EXPECTED_METADATA = {
    'title': 'Urban Wildlife Behavior Study',
    'artist': 'Dr. Emily Chen',
    'description': 'Observational study of raccoon populations in metropolitan areas, filmed 2023-2024',
    'copyright': 'Creative Commons BY-SA 4.0'
}


def normalize_string(s):
    """Normalize string for comparison (strip, lower, remove extra spaces)"""
    if not s:
        return ""
    return " ".join(s.strip().lower().split())


def verify_embed_video_metadata(traj, env_info, task_info):
    """
    Verify that correct metadata was embedded in the video file.
    
    Args:
        traj: Trajectory information (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with 'passed' (bool), 'score' (int), 'feedback' (str)
    """
    logger.info("Starting metadata verification...")
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            'passed': False,
            'score': 0,
            'feedback': "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 5  # 1 for extraction + 4 for metadata fields
    feedback_parts = []
    
    # Copy the metadata result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    
    try:
        # Copy metadata result from container
        try:
            copy_from_env("/tmp/task_output/metadata_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying metadata result: {e}", exc_info=True)
            return {
                'passed': False,
                'score': 0,
                'feedback': f"Metadata extraction failed - no output file: {str(e)}"
            }
        
        # Load the extracted metadata
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
        
        # Check for errors in extraction
        if 'error' in data:
            error_msg = data['error']
            logger.error(f"Metadata extraction error: {error_msg}")
            return {
                'passed': False,
                'score': 0,
                'feedback': f"Metadata extraction error: {error_msg}"
            }
        
        # Extract tags from ffprobe output
        if 'format' not in data or 'tags' not in data['format']:
            logger.warning("No metadata tags found in video file")
            # Check if tags is just empty vs. not present
            if 'format' in data and not data['format'].get('tags'):
                return {
                    'passed': False,
                    'score': 0,
                    'feedback': "No metadata found in video file. Did you save the metadata in VLC? (Click 'Save Metadata' button)"
                }
            return {
                'passed': False,
                'score': 0,
                'feedback': "Metadata structure invalid - no tags found"
            }
        
        tags = data['format']['tags']
        logger.info(f"Found metadata tags: {tags}")
        
        # Criterion 1: Metadata was successfully extracted
        criteria_met += 1
        feedback_parts.append("✅ Metadata extracted from file")
        
        # Check each required field (Criteria 2-5)
        missing_fields = []
        incorrect_fields = []
        matched_fields = []
        
        for field, expected_value in EXPECTED_METADATA.items():
            expected_norm = normalize_string(expected_value)
            
            if field not in tags:
                missing_fields.append(field)
                logger.warning(f"Missing metadata field: {field}")
                continue
            
            actual_value = tags[field]
            actual_norm = normalize_string(actual_value)
            
            # Check if values match (normalized)
            if actual_norm == expected_norm:
                criteria_met += 1
                matched_fields.append(field)
                logger.info(f"✓ {field}: '{actual_value}'")
            else:
                incorrect_fields.append((field, actual_value, expected_value))
                logger.warning(f"✗ {field}: got '{actual_value}', expected '{expected_value}'")
        
        # Build detailed feedback
        if len(matched_fields) == len(EXPECTED_METADATA):
            feedback_parts.append("✅ All metadata fields correctly embedded")
        else:
            feedback_parts.append(f"Matched {len(matched_fields)}/{len(EXPECTED_METADATA)} metadata fields")
            
            if missing_fields:
                feedback_parts.append(f"❌ Missing: {', '.join(missing_fields)}")
            
            if incorrect_fields:
                for field, actual, expected in incorrect_fields:
                    # Truncate long values for feedback
                    actual_short = actual[:50] + "..." if len(actual) > 50 else actual
                    expected_short = expected[:50] + "..." if len(expected) > 50 else expected
                    feedback_parts.append(
                        f"❌ {field.capitalize()}: got '{actual_short}' but expected '{expected_short}'"
                    )
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse metadata JSON: {e}")
        # Try to read the file content for debugging
        try:
            with open(temp_result.name, 'r') as f:
                content = f.read()
            logger.error(f"File content: {content[:500]}")
        except:
            pass
        
        if temp_result and os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Failed to parse metadata output: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        
        if temp_result and os.path.exists(temp_result.name):
            try:
                os.unlink(temp_result.name)
            except:
                pass
        
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Verification error: {str(e)}"
        }
    
    # Check completion marker (optional, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_metadata_completed.txt", temp_marker.name)
        os.unlink(temp_marker.name)
    except Exception:
        # Completion marker is optional
        pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4/5 criteria
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        'passed': passed,
        'score': score,
        'feedback': feedback
    }
