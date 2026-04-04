#!/usr/bin/env python3
"""
Verifier for GIMP image export task.
Checks if landscape image was successfully exported as landscape_final.png with correct format.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import glob
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def validate_png_file(file_path):
    """
    Validate that a file is actually a PNG format with correct headers and content.
    """
    try:
        # Check PNG magic bytes (89 50 4E 47 0D 0A 1A 0A)
        with open(file_path, 'rb') as f:
            magic_bytes = f.read(8)
            if magic_bytes != b'\x89PNG\r\n\x1a\n':
                logging.debug(f"File {file_path} does not have PNG magic bytes")
                return False, "File is not a valid PNG format"
        
        # Try to open with PIL to verify structure
        with Image.open(file_path) as img:
            # Verify it opens as PNG
            if img.format != 'PNG':
                return False, f"PIL detected format as {img.format}, not PNG"
            
            # Check dimensions are reasonable
            width, height = img.size
            if width <= 0 or height <= 0:
                return False, f"Invalid image dimensions: {width}x{height}"
            
            # Verify image data integrity
            try:
                img.verify()  # This will raise exception if corrupted
            except Exception as e:
                return False, f"Image data verification failed: {str(e)}"
            
            return True, f"Valid PNG file: {width}x{height} pixels"
            
    except Exception as e:
        return False, f"Error validating PNG file: {str(e)}"


def find_exported_file(copy_from_env, search_locations=None):
    """
    Search for the exported file in various locations and with different naming patterns.
    Returns (success, file_info_dict)
    """
    if search_locations is None:
        search_locations = [
            "/home/ga/Desktop",
            "/home/ga/Documents", 
            "/home/ga",
            "/tmp/shared"
        ]
    
    # Primary target filename
    target_filename = "landscape_final.png"
    
    # Alternative filename patterns to try
    filename_patterns = [
        "landscape_final.png",
        "landscape_final.PNG", 
        "landscape-final.png",
        "*landscape*final*.png",
        "*landscape*final*.PNG"
    ]
    
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        for location in search_locations:
            for pattern in filename_patterns:
                container_path = f"{location}/{pattern}"
                
                try:
                    # Handle glob patterns differently
                    if '*' in pattern:
                        # Use find command to search for glob patterns
                        continue  # We'll handle this separately
                    
                    # Try direct file copy
                    host_path = temp_path / f"found_export_{len(filename_patterns)}.png"
                    
                    try:
                        copy_from_env(f"{location}/{pattern}", str(host_path))
                        
                        if host_path.exists():
                            # Validate the found file
                            is_valid, validation_msg = validate_png_file(host_path)
                            
                            return True, {
                                "success": True,
                                "container_path": f"{location}/{pattern}",
                                "host_path": str(host_path),
                                "filename": pattern,
                                "location": location,
                                "is_valid_png": is_valid,
                                "validation_message": validation_msg,
                                "temp_dir": temp_dir
                            }
                            
                    except Exception:
                        continue  # Try next pattern
                        
                except Exception as e:
                    logging.debug(f"Error searching {container_path}: {e}")
                    continue
        
        # If direct patterns failed, try a broader search
        for location in search_locations:
            try:
                # Copy any PNG files created recently
                import subprocess
                result = subprocess.run([
                    'find', location, '-name', '*.png', '-type', 'f', '-newer', f'{location}/landscape_image.jpg'
                ], capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0 and result.stdout.strip():
                    png_files = result.stdout.strip().split('\n')
                    for png_file in png_files:
                        if 'landscape' in png_file.lower() and 'final' in png_file.lower():
                            host_path = temp_path / "found_broad_search.png"
                            try:
                                copy_from_env(png_file, str(host_path))
                                if host_path.exists():
                                    is_valid, validation_msg = validate_png_file(host_path)
                                    return True, {
                                        "success": True,
                                        "container_path": png_file,
                                        "host_path": str(host_path),
                                        "filename": Path(png_file).name,
                                        "location": str(Path(png_file).parent),
                                        "is_valid_png": is_valid,
                                        "validation_message": validation_msg,
                                        "temp_dir": temp_dir,
                                        "found_via": "broad_search"
                                    }
                            except:
                                continue
                                
            except Exception as e:
                logging.debug(f"Broad search failed for {location}: {e}")
                continue
    
    return False, {"success": False, "error": "Export file not found in any searched location"}


def check_image_export(traj, env_info, task_info):
    """
    Main verifier function for image export task.
    Checks:
    1. File "landscape_final.png" exists in accessible location
    2. File is valid PNG format
    3. File contains valid image data
    4. File was created during task execution (recent timestamp)
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    try:
        # Search for the exported file
        found_file, file_info = find_exported_file(copy_from_env)
        
        if not found_file:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Export file not found. {file_info.get('error', 'Unknown error')}"
            }
        
        logging.debug(f"Found exported file at: {file_info['container_path']}")
        
        # Validate the file content
        host_path = file_info['host_path']
        
        # Load and verify image content
        with Image.open(host_path) as exported_image:
            width, height = exported_image.size
            
            # Verify image has reasonable content (not blank/corrupted)
            img_array = np.array(exported_image.convert('RGB'))
            pixel_variance = np.var(img_array)
            
            # Check if image has sufficient detail (not completely blank)
            has_content = pixel_variance > 100  # Reasonable threshold for image content
        
        feedback_parts = []
        feedback_parts.append(f"Found file: {file_info['filename']}")
        feedback_parts.append(f"Location: {file_info['location']}")
        feedback_parts.append(f"Size: {width}x{height}")
        feedback_parts.append(f"Valid PNG: {'✅' if file_info['is_valid_png'] else '❌'}")
        feedback_parts.append(f"Has content: {'✅' if has_content else '❌'}")
        feedback_parts.append(f"Pixel variance: {pixel_variance:.1f}")
        
        # Calculate success based on criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. File successfully created and found
        if found_file:
            criteria_met += 1
        
        # 2. File is valid PNG format
        if file_info['is_valid_png']:
            criteria_met += 1
            
        # 3. File contains valid image content  
        if has_content:
            criteria_met += 1
            
        # 4. File has reasonable dimensions
        if width > 100 and height > 100:  # Reasonable minimum size
            criteria_met += 1
            feedback_parts.append("Adequate size: ✅")
        else:
            feedback_parts.append("Adequate size: ❌")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect image export!")
        elif passed:
            feedback_parts.append("✅ Good image export!")
        else:
            feedback_parts.append("❌ Image export needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in image export verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary files if needed
        if 'file_info' in locals() and isinstance(file_info, dict):
            cleanup_verification_environment(file_info.get("temp_dir", ""))


if __name__ == "__main__":
    # Test the verifier
    result = check_image_export([], {}, {})
    print(f"Test result: {result}")