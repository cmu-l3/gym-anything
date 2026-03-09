#!/usr/bin/env python3
"""
Verifier for GIMP JPEG export task.
Checks if PNG image was successfully exported as JPEG with appropriate quality settings.
"""

import logging
from pathlib import Path
from PIL import Image
from PIL.ExifTags import TAGS
import numpy as np
import sys
import os
import glob

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    HAS_SSIM = False
    logging.warning("scikit-image not available, using basic similarity check")


def estimate_jpeg_quality_from_filesize(jpeg_path, original_png_path):
    """
    Estimate JPEG quality based on file size ratio compared to original PNG.
    This is a heuristic method based on typical compression ratios.
    """
    try:
        jpeg_size = os.path.getsize(jpeg_path)
        png_size = os.path.getsize(original_png_path)
        
        if png_size == 0:
            return None, "Original PNG file is empty"
        
        size_ratio = jpeg_size / png_size
        
        # Typical size ratios for different quality levels:
        # Quality 95-100: ~40-60% of PNG size
        # Quality 85-95:  ~25-40% of PNG size  
        # Quality 75-85:  ~20-30% of PNG size
        # Quality 60-75:  ~15-25% of PNG size
        # Quality <60:    ~10-20% of PNG size
        
        if 0.40 <= size_ratio <= 0.70:
            estimated_range = (85, 100)
        elif 0.25 <= size_ratio < 0.40:
            estimated_range = (75, 90)
        elif 0.15 <= size_ratio < 0.25:
            estimated_range = (65, 80)
        elif 0.10 <= size_ratio < 0.15:
            estimated_range = (50, 70)
        else:
            estimated_range = (30, 95)  # Wide range for unusual cases
            
        return estimated_range, f"Size ratio: {size_ratio:.3f} (JPEG: {jpeg_size}, PNG: {png_size})"
        
    except Exception as e:
        return None, f"Error estimating quality: {str(e)}"


def check_image_similarity(original_img, result_img, threshold=0.90):
    """
    Check if two images are similar using SSIM or basic pixel comparison.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode
    if original_img.mode != result_img.mode:
        if original_img.mode == 'RGBA':
            original_img = original_img.convert('RGB')
        if result_img.mode == 'RGBA':
            result_img = result_img.convert('RGB')
    
    if HAS_SSIM:
        # Use SSIM for better perceptual similarity
        orig_array = np.array(original_img)
        result_array = np.array(result_img)
        
        if orig_array.shape != result_array.shape:
            return False, f"Shape mismatch: {orig_array.shape} vs {result_array.shape}"
        
        try:
            # Handle different image modes
            if len(orig_array.shape) == 3:  # Color image
                similarity = ssim(orig_array, result_array, multichannel=True, channel_axis=2)
            else:  # Grayscale image
                similarity = ssim(orig_array, result_array)
                
            return similarity >= threshold, f"SSIM: {similarity:.3f}"
        except Exception as e:
            logging.warning(f"SSIM failed, using basic comparison: {e}")
    
    # Fallback: basic pixel difference
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    if orig_array.shape != result_array.shape:
        return False, f"Shape mismatch: {orig_array.shape} vs {result_array.shape}"
    
    # Calculate mean absolute difference
    diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
    max_diff = 255.0  # Maximum possible difference for 8-bit images
    similarity = 1.0 - (diff / max_diff)
    
    return similarity >= threshold, f"Pixel similarity: {similarity:.3f}"


def find_exported_jpeg_files(directory):
    """
    Find potential JPEG export files in the directory.
    Returns list of JPEG files sorted by modification time (newest first).
    """
    jpeg_patterns = [
        "*.jpg", "*.jpeg", "*.JPG", "*.JPEG"
    ]
    
    jpeg_files = []
    for pattern in jpeg_patterns:
        jpeg_files.extend(glob.glob(os.path.join(directory, pattern)))
    
    # Sort by modification time (newest first)
    jpeg_files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    
    # Filter out the original PNG (shouldn't be JPEG but just in case)
    jpeg_files = [f for f in jpeg_files if not f.endswith('photo_image.png')]
    
    return jpeg_files


def check_jpeg_export(traj, env_info, task_info):
    """
    Main verifier function for JPEG export task.
    Checks:
    1. JPEG file was created with proper format
    2. Quality appears appropriate (70-95 range estimated from file size)
    3. Content is preserved (high similarity to original)
    4. Compression was effective (meaningful file size reduction)
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # First, let's look for any JPEG files that might have been created
    # We'll search for common export names and any JPEG in the Desktop
    possible_results = [
        "/home/ga/Desktop/exported_photo.jpg",
        "/home/ga/Desktop/exported_photo.jpeg", 
        "/home/ga/Desktop/photo_image.jpg",
        "/home/ga/Desktop/photo_image.jpeg",
        "/home/ga/Desktop/export.jpg",
        "/home/ga/Desktop/export.jpeg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_image.png",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )
    
    if not success:
        # If standard setup failed, try to find any JPEG files
        logging.debug("Standard setup failed, searching for any JPEG files...")
        
        # Try to copy the Desktop directory listing to find JPEG files
        import tempfile
        with tempfile.TemporaryDirectory() as temp_dir:
            try:
                # Copy original PNG first
                original_path = Path(temp_dir) / "original.png"
                copy_from_env("/home/ga/Desktop/photo_image.png", str(original_path))
                
                # Try to find any JPEG files by attempting to copy common names
                for potential_name in ["exported_photo.jpg", "photo_image.jpg", "export.jpg"]:
                    try:
                        result_path = Path(temp_dir) / "result.jpg"
                        copy_from_env(f"/home/ga/Desktop/{potential_name}", str(result_path))
                        
                        # If we successfully copied a file, update file_info
                        file_info = {
                            "original_path": str(original_path),
                            "result_path": str(result_path),
                            "result_container_path": f"/home/ga/Desktop/{potential_name}",
                            "temp_dir": temp_dir
                        }
                        success = True
                        break
                    except:
                        continue
                        
                if not success:
                    return {
                        "passed": False,
                        "score": 0,
                        "feedback": "No JPEG export file found. Make sure to export the PNG as JPEG format."
                    }
                        
            except Exception as e:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"Could not access files: {str(e)}"
                }
    
    try:
        # Load images from copied files
        original_image = Image.open(file_info["original_path"])
        result_image = Image.open(file_info["result_path"])
        
        logging.debug(f"Found result image at: {file_info['result_container_path']}")
        
        # Verify the result is actually a JPEG file
        if result_image.format != 'JPEG':
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Exported file is not JPEG format (found: {result_image.format})"
            }
        
        # Check file extension
        result_path = file_info["result_container_path"]
        has_jpeg_extension = result_path.lower().endswith(('.jpg', '.jpeg'))
        
        # Estimate JPEG quality from file size ratio
        quality_range, size_info = estimate_jpeg_quality_from_filesize(
            file_info["result_path"], 
            file_info["original_path"]
        )
        
        # Check content preservation
        similarity_ok, similarity_info = check_image_similarity(original_image, result_image, 0.85)
        
        # Check compression effectiveness
        orig_size = os.path.getsize(file_info["original_path"])
        result_size = os.path.getsize(file_info["result_path"])
        compression_ratio = result_size / orig_size if orig_size > 0 else 1.0
        effective_compression = 0.20 <= compression_ratio <= 0.70
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size} ({orig_size} bytes)")
        feedback_parts.append(f"Result size: {result_image.size} ({result_size} bytes)")
        feedback_parts.append(f"Format: {result_image.format}")
        feedback_parts.append(f"File extension: {'✅' if has_jpeg_extension else '❌'}")
        feedback_parts.append(f"Compression ratio: {compression_ratio:.2f}")
        feedback_parts.append(f"Size info: {size_info}")
        feedback_parts.append(f"Similarity: {similarity_info}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Correct JPEG format with proper extension
        if result_image.format == 'JPEG' and has_jpeg_extension:
            criteria_met += 1
        feedback_parts.append(f"Correct JPEG format: {'✅' if result_image.format == 'JPEG' and has_jpeg_extension else '❌'}")
        
        # 2. Quality appears appropriate (estimated 70-95 range)
        quality_appropriate = False
        if quality_range:
            quality_appropriate = quality_range[0] >= 60 and quality_range[1] <= 100
            if quality_appropriate:
                criteria_met += 1
        feedback_parts.append(f"Quality appropriate: {'✅' if quality_appropriate else '❌'} (estimated: {quality_range})")
        
        # 3. Content preserved (similarity check)
        if similarity_ok:
            criteria_met += 1
        feedback_parts.append(f"Content preserved: {'✅' if similarity_ok else '❌'}")
        
        # 4. Effective compression (reasonable file size reduction)
        if effective_compression:
            criteria_met += 1
        feedback_parts.append(f"Effective compression: {'✅' if effective_compression else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect JPEG export!")
        elif passed:
            feedback_parts.append("✅ Good JPEG export!")
        else:
            feedback_parts.append("❌ JPEG export needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in JPEG export verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary files
        cleanup_verification_environment(file_info.get("temp_dir", ""))


if __name__ == "__main__":
    # Test the verifier
    result = check_jpeg_export([], {}, {})
    print(f"Test result: {result}")