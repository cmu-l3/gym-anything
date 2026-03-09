#!/usr/bin/env python3
"""
Verifier for Chrome Image Download Task: save_image_as@1
Task: Download a specific image using right-click 'Save image as...' context menu

Verification Strategy:
- Check if image file exists in Downloads folder
- Validate file is a proper image format (using PIL)
- Check file was created during task execution (timestamp)
- Verify file size is reasonable (not empty, not too small)
- Check filename matches expected pattern
- Optionally compare with original image
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PIL for image validation
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, image validation will be limited")


def find_downloaded_image(copy_from_env):
    """
    Find and copy the downloaded image from container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/image_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No image file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read image_filename.txt: {e}")
            found_name = "nature_photo.jpg"
        
        # Try to copy the downloaded image
        temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/image_download_verification/downloaded_image",
            "/tmp/downloaded_image",
            f"/home/ga/Downloads/{found_name}",
            "/home/ga/Downloads/nature_photo.jpg",
            "/home/ga/Downloads/nature_photo.jpeg",
            "/home/ga/Downloads/nature_photo",
            "/home/ga/Downloads/ocean_waves.jpg",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_image.name)
                
                # Check if file has content
                if Path(temp_image.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied image from: {container_path}")
                    return True, temp_image.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_image.name)
        return False, "", "", "Image file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding image: {e}", exc_info=True)
        return False, "", "", f"Error finding image: {str(e)}"


def check_image_file_size(image_path):
    """
    Check if image has meaningful file size.
    
    Returns:
        tuple: (passed, size_kb, feedback)
    """
    try:
        size_bytes = Path(image_path).stat().st_size
        size_kb = size_bytes / 1024
        
        if size_bytes < 100:  # Less than 100 bytes
            return False, size_kb, f"File too small ({size_bytes} bytes) - likely not a real image"
        elif size_bytes < 1024:  # Less than 1KB
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB)"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def validate_image_format(image_path):
    """
    Validate that file is a proper image using PIL.
    
    Returns:
        tuple: (passed, format, dimensions, feedback)
    """
    if not HAS_PIL:
        return None, "unknown", (0, 0), "PIL not available for validation"
    
    try:
        with Image.open(image_path) as img:
            width, height = img.size
            img_format = img.format
            
            # Check for valid dimensions
            if width == 0 or height == 0:
                return False, img_format, (width, height), "Invalid image dimensions (0x0)"
            
            # Check if dimensions seem reasonable for our test images
            if width < 50 or height < 50:
                return False, img_format, (width, height), f"Image too small ({width}x{height})"
            
            return True, img_format, (width, height), f"Valid {img_format} image ({width}x{height})"
            
    except Exception as e:
        return False, "invalid", (0, 0), f"Failed to validate image: {str(e)}"


def check_filename_correctness(actual_name, expected_patterns=None):
    """
    Check if filename matches expected patterns.
    
    Args:
        actual_name: The actual filename found
        expected_patterns: List of acceptable filename patterns
        
    Returns:
        tuple: (passed, feedback)
    """
    if expected_patterns is None:
        expected_patterns = [
            "nature_photo.jpg",
            "nature_photo.jpeg",
            "nature_photo.png",
            "nature_photo"
        ]
    
    actual_lower = actual_name.lower()
    
    # Check for exact match
    if actual_lower in [p.lower() for p in expected_patterns]:
        return True, f"Filename correct: {actual_name}"
    
    # Check for close match (contains key parts)
    if "nature" in actual_lower and "photo" in actual_lower:
        return True, f"Filename acceptable: {actual_name}"
    
    # Check if it's the original filename (also acceptable)
    if "ocean" in actual_lower or "waves" in actual_lower:
        return True, f"Filename from original source: {actual_name} (acceptable)"
    
    return False, f"Filename incorrect: {actual_name} (expected: nature_photo.jpg)"


def compare_with_original(downloaded_path, copy_from_env):
    """
    Compare downloaded image with original to verify it's the correct image.
    
    Returns:
        tuple: (passed, similarity_score, feedback)
    """
    if not HAS_PIL:
        return None, 0, "PIL not available for comparison"
    
    try:
        # Try to copy original image
        temp_original = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        try:
            copy_from_env("/tmp/image_download_verification/original_image.jpg", temp_original.name)
        except:
            try:
                copy_from_env("/tmp/original_image.jpg", temp_original.name)
            except:
                os.unlink(temp_original.name)
                return None, 0, "Original image not available for comparison"
        
        # Compare dimensions at minimum
        with Image.open(downloaded_path) as downloaded_img:
            with Image.open(temp_original.name) as original_img:
                dl_size = downloaded_img.size
                orig_size = original_img.size
                
                os.unlink(temp_original.name)
                
                if dl_size == orig_size:
                    return True, 100, f"Image dimensions match original ({dl_size[0]}x{dl_size[1]})"
                else:
                    return False, 50, f"Image dimensions differ: {dl_size} vs {orig_size}"
                
    except Exception as e:
        logger.warning(f"Could not compare with original: {e}")
        return None, 0, "Comparison failed"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for save_image_as@1 task.
    
    Verifies:
    1. Image file exists and was found
    2. File has meaningful size (>1KB)
    3. File is a valid image format (PIL validation)
    4. File has reasonable dimensions
    5. Filename matches expected pattern (with flexibility)
    
    Scoring:
    - 100%: All 5 criteria met
    - 80-99%: 4/5 criteria met (minor issue)
    - 60-79%: 3/5 criteria met (some issues)
    - 40-59%: 2/5 criteria met (significant issues)
    - <40%: <2 criteria met (task mostly failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Image file exists
    logger.info("Checking if image file exists...")
    success, image_path, image_name, error = find_downloaded_image(copy_from_env)
    
    if not success:
        feedback = f"✗ Image file not found\n{error}"
        feedback += "\n\nPlease ensure you:"
        feedback += "\n  1. Right-clicked on the target image (ocean waves)"
        feedback += "\n  2. Selected 'Save image as...' from context menu"
        feedback += "\n  3. Saved the file in Downloads folder"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ Image file found: {image_name}")
    criteria_met += 1
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_kb, size_feedback = check_image_file_size(image_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {size_feedback}")
    
    # Criterion 3: Image format validation
    logger.info("Validating image format...")
    format_ok, img_format, dimensions, format_feedback = validate_image_format(image_path)
    if format_ok is None:
        feedback_parts.append(f"⚠ {format_feedback}")
        criteria_met += 0.5  # Partial credit if PIL not available
    elif format_ok:
        feedback_parts.append(f"✓ {format_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {format_feedback}")
    
    # Criterion 4: Dimensions check (reasonable size for our test images)
    logger.info("Checking image dimensions...")
    if format_ok and dimensions[0] >= 300 and dimensions[1] >= 200:
        feedback_parts.append(f"✓ Image dimensions reasonable: {dimensions[0]}x{dimensions[1]}")
        criteria_met += 1
    elif format_ok is None:
        feedback_parts.append(f"⚠ Could not verify dimensions")
        criteria_met += 0.5  # Partial credit
    else:
        feedback_parts.append(f"✗ Image dimensions suspicious: {dimensions[0]}x{dimensions[1]}")
    
    # Criterion 5: Filename check
    logger.info("Checking filename...")
    filename_ok, filename_feedback = check_filename_correctness(image_name)
    if filename_ok:
        feedback_parts.append(f"✓ {filename_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ {filename_feedback}")
        criteria_met += 0.5  # Partial credit for wrong filename but correct image
    
    # Optional: Compare with original
    logger.info("Comparing with original image...")
    comparison_ok, similarity, comparison_feedback = compare_with_original(image_path, copy_from_env)
    if comparison_ok:
        feedback_parts.append(f"✓ {comparison_feedback}")
    elif comparison_ok is None:
        feedback_parts.append(f"ℹ {comparison_feedback}")
    else:
        feedback_parts.append(f"⚠ {comparison_feedback}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PIL:
        feedback += "\n\n⚠ Note: PIL/Pillow library not available, some checks had limited functionality"
    
    if passed:
        feedback += "\n\n✅ Successfully downloaded the target image!"
    else:
        feedback += "\n\n❌ Image download incomplete or incorrect."
        feedback += "\n\nTips for success:"
        feedback += "\n  • Make sure to right-click directly on the target image"
        feedback += "\n  • Select 'Save image as...' (not 'Copy image')"
        feedback += "\n  • Save with filename 'nature_photo' or similar"
        feedback += "\n  • Ensure file saves to Downloads folder"
    
    # Clean up temporary file
    try:
        if image_path and os.path.exists(image_path):
            os.unlink(image_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "filename": image_name,
            "size_kb": size_kb if size_ok else 0,
            "format": img_format if format_ok is not None else "unknown",
            "dimensions": dimensions if format_ok is not None else (0, 0)
        }
    }
