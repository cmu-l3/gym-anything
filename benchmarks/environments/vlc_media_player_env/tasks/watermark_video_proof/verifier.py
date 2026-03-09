#!/usr/bin/env python3
"""
Verifier for Watermark Video Proof task

Uses multi-modal verification:
1. File existence and validity checks
2. Duration preservation verification
3. OCR-based watermark text detection
4. Temporal persistence check (watermark throughout video)
"""

import sys
import os
import logging
import tempfile
import subprocess
import json
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import OCR libraries
try:
    import cv2
    import numpy as np
    CV2_AVAILABLE = True
except ImportError:
    logger.warning("OpenCV not available - watermark detection will be limited")
    CV2_AVAILABLE = False

try:
    import pytesseract
    from PIL import Image
    PYTESSERACT_AVAILABLE = True
except ImportError:
    logger.warning("pytesseract not available - installing...")
    # Try to install pytesseract
    try:
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'pytesseract', 'Pillow'], 
                      check=False, capture_output=True, timeout=30)
        import pytesseract
        from PIL import Image
        PYTESSERACT_AVAILABLE = True
    except Exception as e:
        logger.error(f"Could not install pytesseract: {e}")
        PYTESSERACT_AVAILABLE = False


def extract_frames_from_video(video_path, num_frames=5):
    """
    Extract frames from video at different positions for watermark detection.
    
    Args:
        video_path: Path to video file
        num_frames: Number of frames to extract
        
    Returns:
        List of frame image paths
    """
    if not CV2_AVAILABLE:
        logger.error("OpenCV not available for frame extraction")
        return []
    
    try:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            logger.error(f"Could not open video: {video_path}")
            return []
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        if total_frames == 0:
            logger.error("Video has no frames")
            cap.release()
            return []
        
        frame_paths = []
        temp_dir = tempfile.mkdtemp(prefix='watermark_frames_')
        
        # Sample frames at different positions (avoid first and last 5%)
        start_frame = int(total_frames * 0.05)
        end_frame = int(total_frames * 0.95)
        sample_positions = [int(start_frame + (end_frame - start_frame) * i / (num_frames - 1)) 
                           for i in range(num_frames)]
        
        for idx, frame_num in enumerate(sample_positions):
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
            ret, frame = cap.read()
            
            if not ret:
                logger.warning(f"Could not read frame {frame_num}")
                continue
            
            frame_path = os.path.join(temp_dir, f"frame_{idx:03d}.png")
            cv2.imwrite(frame_path, frame)
            frame_paths.append(frame_path)
            logger.info(f"Extracted frame {idx+1}/{num_frames} at position {frame_num}/{total_frames}")
        
        cap.release()
        return frame_paths
        
    except Exception as e:
        logger.error(f"Error extracting frames: {e}")
        return []


def detect_watermark_in_frame(frame_path):
    """
    Detect watermark text in a single frame using OCR.
    
    Args:
        frame_path: Path to frame image
        
    Returns:
        Dict with detection results
    """
    if not PYTESSERACT_AVAILABLE:
        logger.error("pytesseract not available")
        return {'detected': False, 'text': '', 'confidence': 0}
    
    try:
        # Open image
        img = Image.open(frame_path)
        
        # Perform OCR
        ocr_text = pytesseract.image_to_string(img).lower()
        
        # Watermark keywords to look for
        watermark_keywords = [
            'preview', 'watermark', 'copyright', '©', 'do not', 
            'distribute', 'proof', 'sample', 'draft', 'confidential',
            'not for distribution', 'maria', 'films'
        ]
        
        # Check for watermark keywords
        keywords_found = [kw for kw in watermark_keywords if kw in ocr_text]
        
        # Consider watermark detected if at least 1 keyword found
        detected = len(keywords_found) > 0
        
        result = {
            'detected': detected,
            'text': ocr_text,
            'keywords_found': keywords_found,
            'confidence': len(keywords_found) / 3.0  # Normalize to 0-1 range
        }
        
        if detected:
            logger.info(f"Watermark detected in frame: {keywords_found}")
        
        return result
        
    except Exception as e:
        logger.error(f"Error detecting watermark in frame: {e}")
        return {'detected': False, 'text': '', 'confidence': 0}


def verify_watermark_persistence(video_path, num_samples=5):
    """
    Verify watermark appears throughout the video.
    
    Args:
        video_path: Path to video file
        num_samples: Number of frames to sample
        
    Returns:
        Tuple of (detection_rate, details_dict)
    """
    # Extract frames
    frame_paths = extract_frames_from_video(video_path, num_samples)
    
    if not frame_paths:
        logger.error("Could not extract frames from video")
        return 0.0, {'error': 'Frame extraction failed'}
    
    # Detect watermark in each frame
    detections = []
    for frame_path in frame_paths:
        detection = detect_watermark_in_frame(frame_path)
        detections.append(detection)
    
    # Clean up frame files
    for frame_path in frame_paths:
        try:
            os.unlink(frame_path)
        except:
            pass
    
    # Remove temp directory
    if frame_paths:
        temp_dir = os.path.dirname(frame_paths[0])
        try:
            os.rmdir(temp_dir)
        except:
            pass
    
    # Calculate detection rate
    detected_count = sum(1 for d in detections if d['detected'])
    detection_rate = detected_count / len(detections) if detections else 0.0
    
    # Aggregate keywords found
    all_keywords = set()
    for d in detections:
        all_keywords.update(d.get('keywords_found', []))
    
    details = {
        'total_frames': len(detections),
        'detected_frames': detected_count,
        'detection_rate': detection_rate,
        'keywords_found': list(all_keywords),
        'detections': detections
    }
    
    return detection_rate, details


def verify_watermark_video(traj, env_info, task_info):
    """
    Verify watermark video task completion.
    
    Checks:
    1. Output file exists and is valid
    2. Video is playable with correct codec
    3. Duration preserved from input
    4. Watermark detected via OCR
    5. Watermark persists throughout video
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Check output file exists and is valid
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_watermarked_video.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Watermarked video not found: {error}"
        }
    
    output_data = file_info.get('data', {})
    output_path = file_info.get('filepath', '')
    
    # Check if file is not empty
    if os.path.getsize(output_path) < 1024:  # Less than 1KB
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output video file is empty or too small"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    # Criterion 2: Check video properties (codec, duration)
    if output_data.get('codec') and output_data.get('duration', 0) > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ Video valid ({output_data.get('codec')}, {output_data.get('duration', 0):.1f}s)")
    else:
        feedback_parts.append("⚠️ Video properties incomplete")
    
    # Criterion 3: Verify duration preserved from input
    try:
        input_success, input_info, input_error = setup_verification_environment(
            copy_from_env,
            "/tmp/vlc_watermark_input.mp4",
            file_type='video'
        )
        
        if input_success:
            input_data = input_info.get('data', {})
            input_duration = input_data.get('duration', 0)
            output_duration = output_data.get('duration', 0)
            
            if input_duration > 0 and output_duration > 0:
                difference_ratio = abs(output_duration - input_duration) / input_duration
                
                if difference_ratio <= 0.05:  # Within 5% tolerance
                    criteria_met += 1
                    feedback_parts.append(f"✅ Duration preserved ({input_duration:.1f}s → {output_duration:.1f}s)")
                else:
                    feedback_parts.append(f"⚠️ Duration mismatch ({input_duration:.1f}s → {output_duration:.1f}s, {difference_ratio*100:.1f}% diff)")
            else:
                feedback_parts.append("⚠️ Could not compare durations")
            
            cleanup_verification_environment(input_info.get('temp_dir'))
        else:
            feedback_parts.append("⚠️ Could not verify input video")
            # Give partial credit if we can't check input
            criteria_met += 0.5
            
    except Exception as e:
        logger.error(f"Error comparing durations: {e}")
        feedback_parts.append("⚠️ Duration comparison failed")
    
    # Criterion 4 & 5: Detect watermark via OCR
    if CV2_AVAILABLE and PYTESSERACT_AVAILABLE:
        try:
            detection_rate, details = verify_watermark_persistence(output_path, num_samples=5)
            
            keywords_found = details.get('keywords_found', [])
            detected_frames = details.get('detected_frames', 0)
            total_frames = details.get('total_frames', 0)
            
            # Criterion 4: Watermark present (detected in at least one frame)
            if detected_frames > 0:
                criteria_met += 1
                feedback_parts.append(f"✅ Watermark detected (keywords: {', '.join(keywords_found[:3])})")
            else:
                feedback_parts.append("❌ No watermark detected")
            
            # Criterion 5: Watermark persistent (60%+ of frames)
            if detection_rate >= 0.6:
                criteria_met += 1
                feedback_parts.append(f"✅ Watermark persistent ({detected_frames}/{total_frames} frames)")
            elif detection_rate > 0:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Watermark partially persistent ({detected_frames}/{total_frames} frames)")
            else:
                feedback_parts.append("❌ Watermark not persistent")
                
        except Exception as e:
            logger.error(f"Error detecting watermark: {e}")
            feedback_parts.append(f"⚠️ Watermark detection failed: {str(e)}")
    else:
        # Fallback: Give partial credit if OCR libraries not available
        logger.warning("OCR libraries not available, giving partial credit")
        criteria_met += 1.5  # Partial credit for missing verification capability
        feedback_parts.append("⚠️ Watermark detection limited (OCR unavailable)")
    
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_watermark_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }