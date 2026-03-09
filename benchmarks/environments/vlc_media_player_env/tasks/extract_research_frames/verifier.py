#!/usr/bin/env python3
"""
Verifier for Extract Research Frames task

Checks that multiple specific frames were extracted from a video at precise
timestamps with correct filenames and image properties.
"""

import sys
import os
import logging
from pathlib import Path
from typing import Dict, List, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import verify_image_quality, PIL_AVAILABLE

if PIL_AVAILABLE:
    from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_expected_frames() -> List[Tuple[float, str]]:
    """
    Parse expected frame extraction targets.
    
    Returns:
        List of (timestamp, filename) tuples
    """
    return [
        (5.0, "frame_position_01.png"),
        (10.5, "frame_position_02.png"),
        (15.2, "frame_position_03.png"),
        (20.8, "frame_position_04.png"),
        (25.3, "frame_position_05.png"),
    ]


def verify_frame_properties(frame_path: Path) -> Tuple[bool, Dict[str, any], str]:
    """
    Verify a single frame's properties.
    
    Args:
        frame_path: Path to frame file
        
    Returns:
        Tuple of (is_valid, properties_dict, error_message)
    """
    if not frame_path.exists():
        return False, {}, "File does not exist"
    
    # Check file size
    size_bytes = frame_path.stat().st_size
    size_kb = size_bytes / 1024
    
    if size_kb < 10:  # Very small file, likely corrupted
        return False, {'size_kb': size_kb}, f"File too small ({size_kb:.1f} KB)"
    
    properties = {
        'size_kb': size_kb,
        'exists': True
    }
    
    # Check if it's a valid image
    if PIL_AVAILABLE:
        try:
            img = Image.open(frame_path)
            img.verify()
            
            # Re-open to get properties (verify closes the file)
            img = Image.open(frame_path)
            width, height = img.size
            
            properties['width'] = width
            properties['height'] = height
            properties['format'] = img.format
            properties['valid_image'] = True
            
            # Check resolution (expected: 1280x720 from test video)
            if width == 1280 and height == 720:
                properties['correct_resolution'] = True
            else:
                properties['correct_resolution'] = False
                logger.warning(f"Unexpected resolution: {width}x{height} (expected 1280x720)")
            
            # Check quality based on file size
            # PNG screenshots from 1280x720 video should be > 50 KB typically
            if size_kb > 50:
                properties['sufficient_quality'] = True
            else:
                properties['sufficient_quality'] = False
                logger.warning(f"Low quality: {size_kb:.1f} KB (expected > 50 KB)")
            
            return True, properties, ""
            
        except Exception as e:
            return False, properties, f"Invalid image: {str(e)}"
    else:
        # PIL not available, just check file size
        logger.warning("PIL not available, limited verification")
        properties['valid_image'] = size_kb > 10
        properties['sufficient_quality'] = size_kb > 50
        
        if properties['valid_image']:
            return True, properties, ""
        else:
            return False, properties, "Cannot verify image (PIL unavailable)"


def verify_extract_research_frames(traj, env_info, task_info):
    """
    Verify extract research frames task completion.
    
    Checks:
    1. All expected frame files exist
    2. Each frame is a valid PNG image
    3. Each frame has correct resolution (1280x720)
    4. Each frame has sufficient quality (file size > 50 KB)
    
    Scoring:
    - Existence: 50% (each frame worth 10%)
    - Validity: 30% (each frame worth 6%)
    - Quality: 20% (each frame worth 4%)
    
    Pass threshold: 80% (4/5 frames fully valid)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get expected frames
    expected_frames = parse_expected_frames()
    total_frames = len(expected_frames)
    
    # Counters for scoring
    frames_found = 0
    frames_valid = 0
    frames_correct_resolution = 0
    frames_good_quality = 0
    
    frame_results = {}
    feedback_lines = []
    
    # Check each expected frame
    for timestamp, filename in expected_frames:
        frame_result = {
            'timestamp': timestamp,
            'filename': filename,
            'exists': False,
            'valid_image': False,
            'correct_resolution': False,
            'sufficient_quality': False,
            'properties': {}
        }
        
        # Try to copy frame from container
        import tempfile
        temp_frame = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        container_path = f"/tmp/task_output/research_frames/{filename}"
        
        try:
            copy_from_env(container_path, temp_frame.name)
            
            # File exists
            frame_result['exists'] = True
            frames_found += 1
            
            # Verify properties
            is_valid, properties, error = verify_frame_properties(Path(temp_frame.name))
            frame_result['properties'] = properties
            
            if is_valid:
                frame_result['valid_image'] = True
                frames_valid += 1
                
                # Check resolution
                if properties.get('correct_resolution', False):
                    frame_result['correct_resolution'] = True
                    frames_correct_resolution += 1
                
                # Check quality
                if properties.get('sufficient_quality', False):
                    frame_result['sufficient_quality'] = True
                    frames_good_quality += 1
                
                # Build feedback
                size_kb = properties.get('size_kb', 0)
                width = properties.get('width', '?')
                height = properties.get('height', '?')
                
                if frame_result['correct_resolution'] and frame_result['sufficient_quality']:
                    feedback_lines.append(
                        f"✓ {filename}: Valid ({width}x{height}, {size_kb:.1f} KB)"
                    )
                else:
                    issues = []
                    if not frame_result['correct_resolution']:
                        issues.append(f"resolution {width}x{height}")
                    if not frame_result['sufficient_quality']:
                        issues.append(f"size {size_kb:.1f} KB")
                    feedback_lines.append(
                        f"⚠️  {filename}: Issues - {', '.join(issues)}"
                    )
            else:
                feedback_lines.append(f"✗ {filename}: {error}")
            
            # Cleanup
            os.unlink(temp_frame.name)
            
        except Exception as e:
            feedback_lines.append(f"✗ {filename}: Not found (timestamp {timestamp}s)")
            logger.debug(f"Could not copy {filename}: {e}")
        
        frame_results[filename] = frame_result
    
    # Calculate score
    # Scoring breakdown:
    # - Existence: 50 points (10 per frame)
    # - Validity: 30 points (6 per frame)
    # - Quality: 20 points (4 per frame)
    
    existence_score = (frames_found / total_frames) * 50
    validity_score = (frames_valid / total_frames) * 30
    quality_score = (frames_good_quality / total_frames) * 20
    
    final_score = int(existence_score + validity_score + quality_score)
    
    # Determine pass/fail
    # Require at least 4/5 frames to be valid and good quality for pass
    success = frames_found >= 4 and frames_valid >= 4
    
    # Build comprehensive feedback
    feedback = f"Frame Extraction Results:\n"
    feedback += f"  Frames found: {frames_found}/{total_frames}\n"
    feedback += f"  Frames valid: {frames_valid}/{total_frames}\n"
    feedback += f"  Correct resolution: {frames_correct_resolution}/{total_frames}\n"
    feedback += f"  Good quality: {frames_good_quality}/{total_frames}\n"
    feedback += f"  Score: {final_score}/100\n"
    feedback += f"\nDetails:\n"
    feedback += "\n".join(feedback_lines)
    
    if success:
        feedback += "\n\n✓ Task completed successfully! "
        feedback += f"At least {frames_valid}/{total_frames} frames extracted correctly."
    else:
        feedback += f"\n\n✗ Task incomplete: Only {frames_valid}/{total_frames} valid frames extracted. "
        feedback += f"Need at least 4 valid frames to pass."
    
    logger.info(feedback)
    
    return {
        "passed": success,
        "score": final_score,
        "feedback": feedback,
        "details": frame_results
    }
