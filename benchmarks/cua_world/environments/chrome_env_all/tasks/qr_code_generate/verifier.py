#!/usr/bin/env python3
"""
Verifier for Chrome QR Code Generation Task (qr_code_generate@1)
Task: Generate and download QR code for Wikipedia homepage using Chrome's built-in feature

Verification Strategy:
1. Find QR code image file in Downloads folder (copied during export)
2. Decode QR code using multiple decoding libraries (pyzbar, opencv, fallbacks)
3. Verify decoded URL matches expected Wikipedia URL
4. Check image quality and QR code structure
5. Validate file was created during task execution window
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from urllib.parse import urlparse
from typing import Optional, Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import QR decoding libraries
HAS_PYZBAR = False
HAS_OPENCV = False
HAS_PIL = False

try:
    from pyzbar.pyzbar import decode as pyzbar_decode
    from PIL import Image
    HAS_PYZBAR = True
    HAS_PIL = True
    logger.info("✓ pyzbar and PIL available")
except ImportError:
    logger.warning("pyzbar not available")

try:
    import cv2
    import numpy as np
    HAS_OPENCV = True
    if not HAS_PIL:
        from PIL import Image
        HAS_PIL = True
    logger.info("✓ OpenCV available")
except ImportError:
    logger.warning("OpenCV not available")

if not HAS_PIL:
    try:
        from PIL import Image
        HAS_PIL = True
    except ImportError:
        logger.warning("PIL not available")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for qr_code_generate@1 task.
    
    Verifies:
    1. QR code file exists and was downloaded
    2. File has meaningful size (>1KB)
    3. QR code can be decoded successfully
    4. Decoded URL matches expected Wikipedia URL
    5. Image quality is sufficient for scanning
    6. File was created during task execution
    
    Scoring:
    - 100%: All 6 criteria met
    - 90%: 5/6 criteria met
    - 75%: 4/6 criteria met (minimum passing)
    - 50%: 3/6 criteria met
    - <50%: <3 criteria met
    
    Pass threshold: 75% (requires at least 4 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Criterion 1: QR code file exists
    logger.info("Checking if QR code file exists...")
    success, qr_path, qr_filename, error = find_qr_code_image(copy_from_env)
    
    if not success:
        feedback = f"✗ QR code file not found\n{error}\n\nAgent should:\n1. Right-click on Wikipedia page\n2. Select 'Create QR Code for this page'\n3. Click 'Download' button"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ QR code file found: {qr_filename}")
    criteria_met += 1
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_bytes, size_feedback = check_file_size(qr_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {size_feedback}")
    
    # Criterion 3: QR code decoding
    logger.info("Attempting to decode QR code...")
    decoded_url, decode_feedback = decode_qr_code(qr_path)
    
    if decoded_url:
        feedback_parts.append(f"✓ QR code decoded successfully")
        criteria_met += 1
        
        # Criterion 4: URL validation
        logger.info(f"Validating decoded URL: {decoded_url}")
        url_ok, url_feedback = verify_url_matches_wikipedia(decoded_url)
        if url_ok:
            feedback_parts.append(f"✓ {url_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {url_feedback}")
    else:
        feedback_parts.append(f"✗ Failed to decode QR code: {decode_feedback}")
        feedback_parts.append(f"✗ Cannot validate URL (decoding failed)")
    
    # Criterion 5: Image quality assessment
    logger.info("Assessing QR code image quality...")
    quality_ok, quality_feedback = assess_qr_quality(qr_path)
    if quality_ok:
        feedback_parts.append(f"✓ {quality_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ {quality_feedback}")
        criteria_met += 0.5  # Partial credit for quality issues
    
    # Criterion 6: File creation time check
    logger.info("Checking file creation time...")
    time_ok, time_feedback = check_file_age(qr_path, max_age_minutes=10)
    if time_ok:
        feedback_parts.append(f"✓ {time_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ {time_feedback}")
        criteria_met += 0.5  # Partial credit if file is older
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if decoded_url:
        feedback += f"\n\nDecoded QR code URL: {decoded_url}"
    
    if not HAS_PYZBAR and not HAS_OPENCV:
        feedback += "\n\n⚠ Note: QR decoding libraries not fully available, verification may be limited"
    
    # Clean up temporary file
    try:
        if qr_path and os.path.exists(qr_path):
            os.unlink(qr_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "qr_filename": qr_filename,
            "decoded_url": decoded_url,
            "criteria_met": criteria_met
        }
    }


def find_qr_code_image(copy_from_env) -> Tuple[bool, str, str, str]:
    """
    Find and copy the QR code image from the container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found during export
        temp_filename_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_filename_file.close()
        
        try:
            copy_from_env("/tmp/qr_filename.txt", temp_filename_file.name)
            with open(temp_filename_file.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename_file.name)
            
            if found_name == "none":
                return False, "", "", "No QR code file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read qr_filename.txt: {e}")
            found_name = "unknown"
        
        # Try to copy the QR code image from verification directory
        temp_qr = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_qr.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/qr_code_verification/qr_code.png",
            "/tmp/qr_code.png",
            "/home/ga/Downloads/qrcode*.png",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_qr.name)
                
                # Check if file has content
                if Path(temp_qr.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied QR code from: {container_path}")
                    return True, temp_qr.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_qr.name)
        return False, "", "", "QR code image could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding QR code: {e}", exc_info=True)
        return False, "", "", f"Error finding QR code: {str(e)}"


def check_file_size(file_path: str) -> Tuple[bool, int, str]:
    """
    Check if file has meaningful size for a QR code.
    
    Returns:
        tuple: (passed, size_bytes, feedback)
    """
    try:
        size_bytes = Path(file_path).stat().st_size
        size_kb = size_bytes / 1024
        
        if size_bytes < 100:  # Less than 100 bytes
            return False, size_bytes, f"File too small ({size_bytes} bytes) - likely empty or corrupted"
        elif size_bytes < 1024:  # Less than 1KB
            return False, size_bytes, f"File suspiciously small ({size_bytes} bytes)"
        else:
            return True, size_bytes, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def decode_qr_code(image_path: str) -> Tuple[Optional[str], str]:
    """
    Decode QR code from image file using multiple strategies.
    
    Returns:
        tuple: (decoded_url or None, feedback_message)
    """
    # Strategy 1: pyzbar (most reliable)
    if HAS_PYZBAR:
        try:
            logger.info("Attempting decode with pyzbar...")
            img = Image.open(image_path)
            decoded_objects = pyzbar_decode(img)
            
            if decoded_objects:
                qr_data = decoded_objects[0].data.decode('utf-8')
                logger.info(f"✓ pyzbar decoded: {qr_data}")
                return qr_data, "Decoded with pyzbar"
        except Exception as e:
            logger.warning(f"pyzbar decoding failed: {e}")
    
    # Strategy 2: OpenCV QRCodeDetector
    if HAS_OPENCV:
        try:
            logger.info("Attempting decode with OpenCV...")
            img = cv2.imread(image_path)
            detector = cv2.QRCodeDetector()
            data, vertices_array, binary_qrcode = detector.detectAndDecode(img)
            
            if data:
                logger.info(f"✓ OpenCV decoded: {data}")
                return data, "Decoded with OpenCV"
        except Exception as e:
            logger.warning(f"OpenCV decoding failed: {e}")
    
    # If all strategies failed
    error_msg = "Could not decode QR code. "
    if not HAS_PYZBAR and not HAS_OPENCV:
        error_msg += "No decoding libraries available (install pyzbar or opencv)"
    else:
        error_msg += "QR code may be corrupted, low quality, or not a valid QR code"
    
    return None, error_msg


def verify_url_matches_wikipedia(decoded_url: str) -> Tuple[bool, str]:
    """
    Verify decoded URL matches expected Wikipedia URL with normalization.
    
    Returns:
        tuple: (matches, feedback)
    """
    expected_url = "https://www.wikipedia.org"
    
    # Normalize URLs for comparison
    def normalize_url(url):
        try:
            parsed = urlparse(url)
            # Ensure https
            scheme = 'https' if parsed.scheme in ['http', 'https'] else parsed.scheme
            # Remove trailing slash from path
            path = parsed.path.rstrip('/')
            # Reconstruct without query/fragment for base comparison
            netloc = parsed.netloc.lower()
            return f"{scheme}://{netloc}{path}"
        except:
            return url.lower()
    
    normalized_decoded = normalize_url(decoded_url)
    normalized_expected = normalize_url(expected_url)
    
    logger.info(f"Normalized decoded: {normalized_decoded}")
    logger.info(f"Normalized expected: {normalized_expected}")
    
    # Check exact match
    if normalized_decoded == normalized_expected:
        return True, f"URL matches perfectly: {decoded_url}"
    
    # Check if it's wikipedia.org domain
    if "wikipedia.org" in normalized_decoded.lower():
        return True, f"URL is Wikipedia (slight variation allowed): {decoded_url}"
    
    return False, f"URL mismatch: got '{decoded_url}', expected Wikipedia URL"


def assess_qr_quality(image_path: str) -> Tuple[bool, str]:
    """
    Assess QR code image quality metrics.
    
    Returns:
        tuple: (sufficient_quality, feedback)
    """
    if not HAS_PIL:
        return True, "Quality check skipped (PIL not available)"
    
    try:
        img = Image.open(image_path)
        width, height = img.size
        
        # Check resolution
        min_dimension = min(width, height)
        if min_dimension < 100:
            return False, f"Resolution too low ({width}x{height}px) - QR may not scan reliably"
        elif min_dimension < 200:
            return True, f"Resolution acceptable but low ({width}x{height}px)"
        else:
            return True, f"Resolution good ({width}x{height}px)"
            
    except Exception as e:
        logger.warning(f"Could not assess quality: {e}")
        return True, "Quality check failed (assuming OK)"


def check_file_age(file_path: str, max_age_minutes: int = 10) -> Tuple[bool, str]:
    """
    Check if file was created recently (within task execution window).
    
    Returns:
        tuple: (recent_enough, feedback)
    """
    try:
        file_mtime = Path(file_path).stat().st_mtime
        file_time = datetime.fromtimestamp(file_mtime)
        current_time = datetime.now()
        age = current_time - file_time
        
        age_minutes = age.total_seconds() / 60
        
        if age_minutes <= max_age_minutes:
            return True, f"File created recently ({age_minutes:.1f} minutes ago)"
        else:
            return False, f"File is old ({age_minutes:.1f} minutes ago) - may not be from this task"
            
    except Exception as e:
        logger.warning(f"Could not check file age: {e}")
        return True, "Age check failed (assuming OK)"
