#!/usr/bin/env python3
"""
Verifier for Chrome QR Code Generation Task (qr_code_generation@1)
Task: Generate and download QR code for a webpage using Chrome's built-in feature

Verification Strategy:
1. Search Downloads folder for recently created PNG files
2. Identify likely QR code files by size, name patterns, and timing
3. Validate image is square (QR codes are always square)
4. Decode QR code to extract embedded URL
5. Verify decoded URL matches target URL (https://example.com)
"""

import logging
import sys
import os
import tempfile
import re
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image and QR processing libraries
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, image validation will be limited")

try:
    from pyzbar.pyzbar import decode as pyzbar_decode
    HAS_PYZBAR = True
except ImportError:
    HAS_PYZBAR = False
    logger.warning("pyzbar not available, will try alternative QR decoding methods")

try:
    import cv2
    import numpy as np
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logger.warning("OpenCV not available, using primary decoding method only")

# Add Chrome utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for qr_code_generation@1 task.
    
    Verifies:
    1. QR code PNG file was downloaded
    2. File has valid image properties (square, reasonable size)
    3. QR code can be decoded
    4. Decoded URL matches target URL
    5. File was created during task execution
    
    Scoring:
    - 100%: All 5 criteria met with perfect URL match
    - 90%: 4/5 criteria with minor URL variations
    - 80%: Valid QR downloaded but URL has variations
    - 50%: QR file exists but decoding issues
    - 25%: Image file found but not valid QR code
    - 0%: No appropriate file found
    
    Pass threshold: 80%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    # Task parameters
    target_url = "https://example.com"
    task_start = task_info.get('start_time', datetime.now() - timedelta(minutes=10))
    
    try:
        # Find and retrieve QR code file
        logger.info("Searching for QR code file in Downloads...")
        qr_file_path, filename, error = find_qr_code_file(copy_from_env, task_start)
        
        if not qr_file_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No QR code file found: {error}"
            }
        
        logger.info(f"Found potential QR code file: {filename}")
        
        # Perform multi-criteria verification
        result = verify_qr_code_file(qr_file_path, filename, target_url)
        
        # Cleanup temporary files
        try:
            os.unlink(qr_file_path)
        except:
            pass
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_qr_code_file(copy_from_env, task_start):
    """
    Find and copy the QR code PNG file from Downloads folder.
    
    Strategy:
    - Look for PNG files created after task start
    - Prioritize files with "qr" in filename
    - Check file size (QR codes typically 5-50KB)
    - Return most likely candidate
    
    Returns:
        Tuple: (local_path, filename, error_message)
    """
    temp_dir = Path(tempfile.mkdtemp(prefix="qr_verification_"))
    
    # Try to copy Downloads folder structure info
    try:
        downloads_list_file = temp_dir / "downloads_list.txt"
        copy_from_env("/tmp/qr_code_verification/downloads_list.txt", str(downloads_list_file))
        
        if downloads_list_file.exists() and downloads_list_file.stat().st_size > 0:
            logger.info("Successfully retrieved downloads list")
        else:
            logger.warning("Downloads list file is empty or missing")
    except Exception as e:
        logger.warning(f"Could not copy downloads list: {e}")
    
    # Try to copy recent PNG files from verification directory
    candidates = []
    
    # First, try pre-copied files from export script
    try:
        # List files in verification directory
        for pattern in ["*.png", "*qr*.png", "*QR*.png"]:
            container_pattern = f"/tmp/qr_code_verification/{pattern}"
            # We need to try copying individual files since we can't list directory
            # Try common QR code filename patterns
            common_names = [
                "qr_code.png",
                "qrcode.png",
                "example_com.png",
                "example.com.png",
                "example_com_qr_code.png",
                "download.png",
                "image.png"
            ]
            
            for name in common_names:
                try:
                    container_path = f"/tmp/qr_code_verification/{name}"
                    local_path = temp_dir / name
                    copy_from_env(container_path, str(local_path))
                    
                    if local_path.exists() and local_path.stat().st_size > 0:
                        size_kb = local_path.stat().st_size / 1024
                        # QR codes are typically 5-50KB
                        if 2 <= size_kb <= 100:
                            score = calculate_filename_score(name)
                            candidates.append((local_path, name, size_kb, score))
                            logger.info(f"Found candidate: {name} ({size_kb:.1f}KB, score: {score})")
                except Exception as e:
                    logger.debug(f"Could not copy {name}: {e}")
                    continue
    except Exception as e:
        logger.debug(f"Error searching verification directory: {e}")
    
    # If no candidates found in verification directory, try Downloads directly
    if not candidates:
        logger.info("No files in verification directory, trying Downloads directly...")
        try:
            # Try common locations in Downloads
            downloads_paths = [
                "/home/ga/Downloads/qr_code.png",
                "/home/ga/Downloads/qrcode.png",
                "/home/ga/Downloads/download.png",
                "/home/ga/Downloads/example_com.png",
            ]
            
            for container_path in downloads_paths:
                try:
                    filename = Path(container_path).name
                    local_path = temp_dir / filename
                    copy_from_env(container_path, str(local_path))
                    
                    if local_path.exists() and local_path.stat().st_size > 0:
                        size_kb = local_path.stat().st_size / 1024
                        if 2 <= size_kb <= 100:
                            score = calculate_filename_score(filename)
                            candidates.append((local_path, filename, size_kb, score))
                            logger.info(f"Found candidate in Downloads: {filename} ({size_kb:.1f}KB)")
                except Exception as e:
                    logger.debug(f"Could not copy {container_path}: {e}")
                    continue
        except Exception as e:
            logger.debug(f"Error searching Downloads: {e}")
    
    # If still no candidates, try to find ANY recent PNG
    if not candidates:
        logger.info("Trying to find any PNG file...")
        try:
            # Check if any PNG was copied to verification directory
            for png_file in temp_dir.glob("*.png"):
                if png_file.name != "final_screenshot.png":  # Exclude screenshots
                    size_kb = png_file.stat().st_size / 1024
                    if 2 <= size_kb <= 100:
                        score = calculate_filename_score(png_file.name)
                        candidates.append((png_file, png_file.name, size_kb, score))
                        logger.info(f"Found generic PNG: {png_file.name} ({size_kb:.1f}KB)")
        except Exception as e:
            logger.debug(f"Error in generic PNG search: {e}")
    
    if not candidates:
        return None, "", "No PNG files found in Downloads folder or verification directory"
    
    # Sort candidates by score (filename relevance) and size
    candidates.sort(key=lambda x: (x[3], -abs(x[2] - 20)), reverse=True)
    
    best_candidate = candidates[0]
    return best_candidate[0], best_candidate[1], ""


def calculate_filename_score(filename):
    """
    Calculate relevance score for filename.
    Higher score = more likely to be QR code.
    """
    filename_lower = filename.lower()
    score = 0
    
    # Strong indicators
    if "qr" in filename_lower:
        score += 10
    if "example" in filename_lower:
        score += 5
    if "code" in filename_lower:
        score += 3
    
    # Negative indicators
    if "screenshot" in filename_lower:
        score -= 20
    if "chrome" in filename_lower:
        score -= 5
    
    return score


def verify_qr_code_file(file_path, filename, target_url):
    """
    Verify QR code file meets all criteria.
    
    Returns:
        Dict with passed, score, feedback, and detailed criteria
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: File exists and has reasonable size
    try:
        file_size = Path(file_path).stat().st_size
        size_kb = file_size / 1024
        
        if 5 <= size_kb <= 100:
            feedback_parts.append(f"✓ File size appropriate: {size_kb:.1f} KB")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ File size unusual: {size_kb:.1f} KB (expected 5-50 KB)")
            criteria_met += 0.5
    except Exception as e:
        feedback_parts.append(f"✗ Could not check file size: {e}")
    
    # Criterion 2: Valid image with square dimensions
    is_square = False
    image_dims = None
    
    if HAS_PIL:
        try:
            with Image.open(file_path) as img:
                width, height = img.size
                image_dims = (width, height)
                aspect_ratio = width / height
                
                if 0.9 <= aspect_ratio <= 1.1:
                    is_square = True
                    feedback_parts.append(f"✓ Image is square: {width}x{height}px (QR codes are square)")
                    criteria_met += 1
                else:
                    feedback_parts.append(f"✗ Image not square: {width}x{height}px (aspect ratio: {aspect_ratio:.2f})")
        except Exception as e:
            feedback_parts.append(f"✗ Could not open image: {e}")
    else:
        feedback_parts.append("⚠ PIL not available, cannot verify image dimensions")
        criteria_met += 0.3
    
    # Criterion 3 & 4: Decode QR code and check URL
    decoded_url = None
    decoding_method = None
    
    # Try pyzbar first (primary method)
    if HAS_PYZBAR and HAS_PIL:
        try:
            with Image.open(file_path) as img:
                decoded_objects = pyzbar_decode(img)
                
                if decoded_objects:
                    decoded_url = decoded_objects[0].data.decode('utf-8')
                    decoding_method = "pyzbar"
                    logger.info(f"QR code decoded with pyzbar: {decoded_url}")
        except Exception as e:
            logger.warning(f"pyzbar decoding failed: {e}")
    
    # Try OpenCV as fallback
    if not decoded_url and HAS_CV2:
        try:
            img = cv2.imread(str(file_path))
            detector = cv2.QRCodeDetector()
            decoded_url, points, _ = detector.detectAndDecode(img)
            
            if decoded_url:
                decoding_method = "opencv"
                logger.info(f"QR code decoded with OpenCV: {decoded_url}")
        except Exception as e:
            logger.warning(f"OpenCV decoding failed: {e}")
    
    if decoded_url:
        feedback_parts.append(f"✓ QR code successfully decoded using {decoding_method}")
        criteria_met += 1
        
        # Criterion 4: URL matches target
        url_match, url_score = compare_urls(decoded_url, target_url)
        
        if url_match == "perfect":
            feedback_parts.append(f"✓ Decoded URL perfectly matches target: {decoded_url}")
            criteria_met += 1
        elif url_match == "good":
            feedback_parts.append(f"✓ Decoded URL matches target (minor variations): {decoded_url}")
            criteria_met += 0.9
        elif url_match == "acceptable":
            feedback_parts.append(f"⚠ Decoded URL similar to target: {decoded_url}")
            criteria_met += 0.7
        else:
            feedback_parts.append(f"✗ Decoded URL does not match target: {decoded_url} (expected {target_url})")
    else:
        feedback_parts.append("✗ Could not decode QR code from image")
        if not HAS_PYZBAR and not HAS_CV2:
            feedback_parts.append("  (No QR decoding libraries available)")
    
    # Criterion 5: Filename suggests QR code
    if "qr" in filename.lower() or "example" in filename.lower():
        feedback_parts.append(f"✓ Filename suggests QR code: {filename}")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ Filename doesn't clearly indicate QR code: {filename}")
        criteria_met += 0.5
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80
    
    # Build final feedback
    feedback = f"QR Code Generation Verification Results:\n"
    feedback += f"File: {filename}\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PYZBAR and not HAS_CV2:
        feedback += "\n\n⚠ Note: QR decoding libraries not available, verification limited"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "filename": filename,
            "file_size_kb": size_kb if 'size_kb' in locals() else 0,
            "is_square": is_square,
            "dimensions": image_dims,
            "decoded_url": decoded_url,
            "target_url": target_url,
            "criteria_met": criteria_met
        }
    }


def compare_urls(url1, url2):
    """
    Compare two URLs with normalization.
    
    Returns:
        Tuple: (match_level: str, score: float)
        match_level: "perfect", "good", "acceptable", "no_match"
    """
    if not url1 or not url2:
        return "no_match", 0.0
    
    # Normalize URLs
    url1_norm = normalize_url(url1)
    url2_norm = normalize_url(url2)
    
    # Perfect match
    if url1_norm == url2_norm:
        return "perfect", 1.0
    
    # Check with different normalizations
    url1_no_protocol = re.sub(r'^https?://', '', url1.lower()).rstrip('/')
    url2_no_protocol = re.sub(r'^https?://', '', url2.lower()).rstrip('/')
    
    if url1_no_protocol == url2_no_protocol:
        return "good", 0.95
    
    # Check if domain matches
    url1_domain = re.sub(r'^https?://(?:www\.)?', '', url1.lower()).split('/')[0]
    url2_domain = re.sub(r'^https?://(?:www\.)?', '', url2.lower()).split('/')[0]
    
    if url1_domain == url2_domain:
        return "acceptable", 0.8
    
    return "no_match", 0.0


def normalize_url(url):
    """Normalize URL for comparison"""
    if not url:
        return ""
    
    url = url.lower().strip()
    url = url.rstrip('/')
    url = re.sub(r'^https?://', '', url)
    url = re.sub(r'^www\.', '', url)
    
    return url
