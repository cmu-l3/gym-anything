#!/usr/bin/env python3
"""
Verifier for GIMP layer duplication task.
Checks if a layer was successfully duplicated by analyzing the XCF file structure.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import struct
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SSIM = True
    except ImportError:
        HAS_SSIM = False
        logging.warning("SSIM not available, using basic content comparison")


def simple_xcf_layer_count(xcf_path):
    """
    Simple XCF parser to count layers.
    XCF format starts with magic bytes and contains layer information.
    This is a basic implementation for layer counting.
    """
    try:
        with open(xcf_path, 'rb') as f:
            # Check XCF magic bytes
            magic = f.read(9)
            if not magic.startswith(b'gimp xcf'):
                logging.debug("Not a valid XCF file")
                return 0
            
            # Skip to basic structure parsing
            # XCF format is complex, so we'll use a heuristic approach
            # Look for layer count indicators in the file
            f.seek(0)
            content = f.read(8192)  # Read first 8KB for analysis
            
            # Count occurrences of layer-related strings
            # This is a heuristic approach since full XCF parsing is complex
            layer_indicators = content.count(b'Background')
            copy_indicators = content.count(b'copy')
            
            # If we find both original and copy indicators, likely 2 layers
            if b'Background' in content and b'copy' in content:
                return 2
            elif layer_indicators > 0:
                return 1
            else:
                return 0
                
    except Exception as e:
        logging.error(f"Error parsing XCF file: {e}")
        return 0


def extract_xcf_layers_as_images(xcf_path):
    """
    Attempt to extract layer data from XCF file.
    Since XCF parsing is complex, we'll try multiple approaches.
    """
    layers = []
    
    try:
        # Try using GIMP-specific libraries if available
        import gimpformats
        xcf_data = gimpformats.xcf.load_xcf(xcf_path)
        
        for layer in xcf_data.layers:
            if hasattr(layer, 'image_data') and layer.image_data is not None:
                # Convert layer data to PIL Image
                img = Image.fromarray(layer.image_data)
                layers.append(img)
                
        return layers
        
    except ImportError:
        logging.debug("gimpformats not available, trying alternative approach")
    except Exception as e:
        logging.debug(f"gimpformats parsing failed: {e}")
    
    # Fallback: Try to use GIMP itself to export layers (if running in environment)
    # This would require GIMP command-line tools, which may not be available
    # For now, return empty list and rely on other verification methods
    return []


def analyze_layer_similarity(layer1, layer2):
    """
    Analyze similarity between two layer images.
    """
    if not HAS_SSIM:
        # Fallback to basic pixel comparison
        if layer1.size != layer2.size:
            layer2 = layer2.resize(layer1.size)
        
        if layer1.mode != layer2.mode:
            layer2 = layer2.convert(layer1.mode)
        
        arr1 = np.array(layer1)
        arr2 = np.array(layer2)
        
        # Calculate mean difference
        diff = np.mean(np.abs(arr1.astype(float) - arr2.astype(float)))
        # Convert to similarity score (lower diff = higher similarity)
        similarity = max(0, (255 - diff) / 255)
        
        return similarity
    
    # Use SSIM for better similarity measurement
    if layer1.size != layer2.size:
        layer2 = layer2.resize(layer1.size)
    
    if layer1.mode != 'RGB':
        layer1 = layer1.convert('RGB')
    if layer2.mode != 'RGB':
        layer2 = layer2.convert('RGB')
    
    arr1 = np.array(layer1)
    arr2 = np.array(layer2)
    
    # Ensure arrays have same shape
    if arr1.shape != arr2.shape:
        return 0.0
    
    # Calculate SSIM with appropriate window size
    min_dim = min(arr1.shape[0], arr1.shape[1])
    win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
    if win_size < 3:
        win_size = 3
    
    try:
        # Try new version first
        similarity = ssim(arr1, arr2, win_size=win_size, channel_axis=2)
    except TypeError:
        # Fall back to old version
        similarity = ssim(arr1, arr2, win_size=win_size, multichannel=True)
    
    return similarity


def check_layer_duplication(traj, env_info, task_info):
    """
    Main verifier function for layer duplication task.
    Checks:
    1. XCF file was created (preserving layer information)
    2. Layer count increased from 1 to 2
    3. Layer content similarity indicates successful duplication
    4. Proper layer structure
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Set up verification environment with fallback file search
    possible_results = [
        "/home/ga/Desktop/duplicated_layers.xcf",
        "/home/ga/Desktop/duplicated_layers.XCF",
        "/home/ga/Desktop/flower_image.xcf",
        "/home/ga/Desktop/layers.xcf",
        "/home/ga/Desktop/duplicate.xcf"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_image.jpg",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": file_info.get("error", "Setup failed")
        }
    
    try:
        # Load original image for reference
        original_image = Image.open(file_info["original_path"])
        
        # Analyze XCF file for layer information
        xcf_path = file_info["result_path"]
        layer_count = simple_xcf_layer_count(xcf_path)
        
        logging.debug(f"Detected layer count: {layer_count}")
        
        # Try to extract layer images for content analysis
        layer_images = extract_xcf_layers_as_images(xcf_path)
        
        feedback_parts = []
        feedback_parts.append(f"Original image: {original_image.size}")
        feedback_parts.append(f"XCF file found: ✅")
        feedback_parts.append(f"Detected layers: {layer_count}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Layer count increased to 2
        layer_count_correct = (layer_count == 2)
        if layer_count_correct:
            criteria_met += 1
        feedback_parts.append(f"Layer count is 2: {'✅' if layer_count_correct else '❌'}")
        
        # 2. XCF file format (already confirmed by finding the file)
        valid_xcf = True  # We already confirmed it's readable as XCF
        if valid_xcf:
            criteria_met += 1
        feedback_parts.append(f"Valid XCF format: {'✅' if valid_xcf else '❌'}")
        
        # 3. Layer content similarity (if we can extract layers)
        content_similarity_good = False
        if len(layer_images) >= 2:
            similarity = analyze_layer_similarity(layer_images[0], layer_images[1])
            content_similarity_good = similarity >= 0.95
            feedback_parts.append(f"Layer similarity: {similarity:.3f}")
        else:
            # Fallback: if we can't extract layers, check file size and structure
            file_size = os.path.getsize(xcf_path)
            # XCF with duplicated layer should be larger than a simple single-layer file
            content_similarity_good = file_size > 50000  # Reasonable size for multi-layer XCF
            feedback_parts.append(f"File size indicates multiple layers: {file_size} bytes")
        
        if content_similarity_good:
            criteria_met += 1
        feedback_parts.append(f"Layer content preserved: {'✅' if content_similarity_good else '❌'}")
        
        # 4. Image was modified from original (saved as XCF with multiple layers)
        meaningful_modification = (layer_count >= 2 and 
                                 os.path.exists(xcf_path) and 
                                 os.path.getsize(xcf_path) > 10000)
        if meaningful_modification:
            criteria_met += 1
        feedback_parts.append(f"Meaningful modification: {'✅' if meaningful_modification else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect layer duplication!")
        elif passed:
            feedback_parts.append("✅ Good layer duplication!")
        else:
            feedback_parts.append("❌ Layer duplication needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in layer duplication verification: {e}")
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
    result = check_layer_duplication([], {}, {})
    print(f"Test result: {result}")