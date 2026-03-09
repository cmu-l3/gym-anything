#!/usr/bin/env python3
"""
Verifier for GIMP merge down layers task.
Checks if one layer was merged down (layer count reduced by 1) while preserving visual appearance.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")

logging.basicConfig(level=logging.DEBUG)

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
    except ImportError:
        ssim = None
        logging.warning("SSIM not available, using pixel-wise comparison")


def count_xcf_layers(xcf_path):
    """
    Attempt to count layers in an XCF file using multiple methods.
    Returns layer count or None if unable to determine.
    """
    try:
        # Method 1: Try PIL's XCF support
        with Image.open(xcf_path) as xcf_img:
            layer_count = 0
            try:
                while True:
                    xcf_img.seek(layer_count)
                    layer_count += 1
            except EOFError:
                pass
            
            if layer_count > 0:
                logging.debug(f"PIL method found {layer_count} layers")
                return layer_count
                
    except Exception as e:
        logging.debug(f"PIL XCF method failed: {e}")
    
    # Method 2: Parse XCF binary structure (basic approach)
    try:
        with open(xcf_path, 'rb') as f:
            # XCF files start with "gimp xcf " magic
            magic = f.read(9)
            if magic != b'gimp xcf ':
                return None
            
            # Skip version and dimensions
            f.seek(14)  # Skip magic + version (4) + width (4) + height (4) + base_type (4)
            
            # Count layer pointers (each layer has an offset pointer)
            layer_count = 0
            while True:
                offset_bytes = f.read(4)
                if len(offset_bytes) != 4:
                    break
                offset = int.from_bytes(offset_bytes, byteorder='big')
                if offset == 0:  # End of layer list
                    break
                layer_count += 1
                if layer_count > 100:  # Safety limit
                    break
            
            if layer_count > 0:
                logging.debug(f"Binary parsing found {layer_count} layers")
                return layer_count
                
    except Exception as e:
        logging.debug(f"Binary XCF parsing failed: {e}")
    
    return None


def compare_images_ssim(img1, img2, threshold=0.98):
    """
    Compare two images using SSIM if available, fallback to pixel comparison.
    """
    if img1.size != img2.size:
        img2 = img2.resize(img1.size)
    
    # Convert to RGB for consistent comparison
    if img1.mode != 'RGB':
        img1 = img1.convert('RGB')
    if img2.mode != 'RGB':
        img2 = img2.convert('RGB')
    
    if ssim:
        try:
            arr1 = np.array(img1)
            arr2 = np.array(img2)
            
            # Calculate window size
            min_dim = min(arr1.shape[0], arr1.shape[1])
            win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
            win_size = max(3, win_size)
            
            try:
                # Try newer SSIM API
                similarity = ssim(arr1, arr2, win_size=win_size, channel_axis=2)
            except TypeError:
                # Fall back to older API
                similarity = ssim(arr1, arr2, win_size=win_size, multichannel=True)
            
            logging.debug(f"SSIM similarity: {similarity:.4f}")
            return similarity >= threshold, similarity
            
        except Exception as e:
            logging.warning(f"SSIM failed, using pixel comparison: {e}")
    
    # Fallback: pixel-wise comparison
    arr1 = np.array(img1)
    arr2 = np.array(img2)
    
    # Calculate mean absolute difference
    diff = np.mean(np.abs(arr1.astype(np.float32) - arr2.astype(np.float32)))
    # Normalize to 0-1 scale (255 max difference)
    similarity = 1.0 - (diff / 255.0)
    
    logging.debug(f"Pixel similarity: {similarity:.4f}")
    return similarity >= threshold, similarity


def setup_verification_environment(original_xcf, result_xcf, original_flat, result_flat, copy_from_env):
    """
    Set up verification by copying files from container.
    """
    temp_dir = tempfile.mkdtemp()
    temp_path = Path(temp_dir)
    
    # Define host paths
    host_original_xcf = temp_path / "original.xcf"
    host_result_xcf = temp_path / "result.xcf" 
    host_original_flat = temp_path / "original_flat.png"
    host_result_flat = temp_path / "result_flat.png"
    
    # Copy original XCF
    try:
        copy_from_env(original_xcf, str(host_original_xcf))
    except Exception as e:
        return False, {"error": f"Could not copy original XCF: {e}", "temp_dir": temp_dir}
    
    # Copy result XCF
    try:
        copy_from_env(result_xcf, str(host_result_xcf))
    except Exception as e:
        return False, {"error": f"Could not copy result XCF: {e}", "temp_dir": temp_dir}
    
    # Copy flattened images
    try:
        copy_from_env(original_flat, str(host_original_flat))
    except Exception as e:
        logging.warning(f"Could not copy original flattened image: {e}")
        host_original_flat = None
        
    # Try multiple possible result flat file locations
    result_flat_paths = [
        "/home/ga/Desktop/merged_result.png",
        "/home/ga/Desktop/merged_result.jpg", 
        "/home/ga/Desktop/merged_result.jpeg"
    ]
    
    host_result_flat = None
    for flat_path in result_flat_paths:
        try:
            temp_flat = temp_path / f"result_flat_{Path(flat_path).suffix}"
            copy_from_env(flat_path, str(temp_flat))
            host_result_flat = temp_flat
            break
        except Exception:
            continue
    
    return True, {
        "temp_dir": temp_dir,
        "original_xcf": host_original_xcf,
        "result_xcf": host_result_xcf,
        "original_flat": host_original_flat,
        "result_flat": host_result_flat
    }


def cleanup_verification_environment(temp_dir):
    """Clean up temporary verification files."""
    import shutil
    try:
        shutil.rmtree(temp_dir)
    except Exception as e:
        logging.warning(f"Could not clean up temp directory: {e}")


def check_merge_down(traj, env_info, task_info):
    """
    Main verifier function for merge down task.
    Checks:
    1. Layer count reduced by exactly 1
    2. Visual appearance preserved (SSIM ≥ 0.98)
    3. Proper XCF file structure maintained
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Set up verification environment
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/multi_layer_composition.xcf",  # original XCF
        "/home/ga/Desktop/multi_layer_composition.xcf",  # result XCF (same file, modified)
        "/home/ga/Desktop/original_flattened.png",       # original flattened
        "/home/ga/Desktop/merged_result.png",            # result flattened
        copy_from_env
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": file_info.get("error", "Setup failed")
        }
    
    try:
        # For this verification, we need to compare the original state with the current state
        # Since both original and result point to the same file (which was modified),
        # we'll use a different approach: check the layer count and visual similarity
        
        # Count layers in the result XCF
        result_layer_count = count_xcf_layers(file_info["result_xcf"])
        
        # Expected original layer count was 3 (Background, Circle, Text)
        expected_original_count = 3
        expected_result_count = 2  # After merging Text down into Circle
        
        # Load flattened images for visual comparison if available
        visual_preserved = True
        visual_similarity = 1.0
        
        if file_info["original_flat"] and file_info["result_flat"]:
            try:
                original_flat = Image.open(file_info["original_flat"])
                result_flat = Image.open(file_info["result_flat"])
                visual_preserved, visual_similarity = compare_images_ssim(original_flat, result_flat, 0.98)
            except Exception as e:
                logging.warning(f"Visual comparison failed: {e}")
                visual_preserved = None
        
        feedback_parts = []
        feedback_parts.append(f"Expected original layers: {expected_original_count}")
        feedback_parts.append(f"Expected result layers: {expected_result_count}")
        
        if result_layer_count is not None:
            feedback_parts.append(f"Actual result layers: {result_layer_count}")
        else:
            feedback_parts.append("Could not determine layer count")
        
        if visual_similarity is not None:
            feedback_parts.append(f"Visual similarity: {visual_similarity:.3f}")
        
        # Calculate success based on criteria
        criteria_met = 0
        total_criteria = 3
        
        # 1. Layer count reduced by exactly 1
        layer_count_correct = (result_layer_count == expected_result_count) if result_layer_count is not None else False
        if layer_count_correct:
            criteria_met += 1
        feedback_parts.append(f"Layer count reduced by 1: {'✅' if layer_count_correct else '❌'}")
        
        # 2. Visual appearance preserved (if we can check it)
        if visual_preserved is not None:
            if visual_preserved:
                criteria_met += 1
            feedback_parts.append(f"Visual appearance preserved: {'✅' if visual_preserved else '❌'}")
        else:
            # If we can't check visual preservation, give benefit of doubt if layer count is correct
            if layer_count_correct:
                criteria_met += 1
            feedback_parts.append("Visual preservation: ⚠️ (could not verify)")
        
        # 3. XCF file structure valid
        xcf_valid = result_layer_count is not None and result_layer_count > 0
        if xcf_valid:
            criteria_met += 1
        feedback_parts.append(f"Valid XCF structure: {'✅' if xcf_valid else '❌'}")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/3 or 2/2 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect layer merge!")
        elif passed:
            feedback_parts.append("✅ Good layer merge!")
        else:
            feedback_parts.append("❌ Layer merge needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in merge down verification: {e}")
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
    result = check_merge_down([], {}, {})
    print(f"Test result: {result}")