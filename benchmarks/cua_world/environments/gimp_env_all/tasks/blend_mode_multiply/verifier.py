#!/usr/bin/env python3
"""
Verifier for GIMP blend mode multiply task.
Checks if the top layer's blend mode was changed to Multiply.
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
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def parse_xcf_blend_mode(xcf_path):
    """
    Attempt to parse XCF file and extract blend mode information.
    Returns (success, blend_mode_info)
    """
    try:
        # Try to use gimpformats library if available
        from gimpformats.gimpXcfDocument import GimpDocument
        
        xcf = GimpDocument(xcf_path)
        layers = xcf.layers
        
        if len(layers) < 2:
            return False, f"Expected 2 layers, found {len(layers)}"
        
        # Get the top layer (first in list)
        top_layer = layers[0]
        blend_mode = top_layer.blendMode
        
        logging.debug(f"XCF layers found: {len(layers)}")
        logging.debug(f"Top layer blend mode: {blend_mode}")
        
        # Check for Multiply mode (can be numeric or string)
        is_multiply = False
        if isinstance(blend_mode, int):
            # GIMP blend mode IDs - Multiply is typically mode 3
            is_multiply = (blend_mode == 3)
        elif isinstance(blend_mode, str):
            is_multiply = blend_mode.upper() in ["MULTIPLY", "MULTIPLY_MODE"]
        
        return True, {
            'is_multiply': is_multiply,
            'blend_mode': blend_mode,
            'layer_count': len(layers)
        }
        
    except ImportError:
        return False, "gimpformats library not available"
    except Exception as e:
        return False, f"XCF parsing failed: {str(e)}"


def create_multiply_reference(base_img, overlay_img):
    """
    Create a mathematical reference of what Multiply blend should look like.
    Multiply formula: result = (base * overlay) / 255
    """
    # Ensure images are the same size
    if base_img.size != overlay_img.size:
        overlay_img = overlay_img.resize(base_img.size)
    
    # Convert to RGB if needed
    if base_img.mode != 'RGB':
        base_img = base_img.convert('RGB')
    if overlay_img.mode != 'RGB':
        overlay_img = overlay_img.convert('RGB')
    
    # Convert to numpy arrays
    base_array = np.array(base_img, dtype=np.float32)
    overlay_array = np.array(overlay_img, dtype=np.float32)
    
    # Apply multiply blend formula
    result_array = (base_array * overlay_array) / 255.0
    
    # Convert back to PIL Image
    result_array = np.clip(result_array, 0, 255).astype(np.uint8)
    return Image.fromarray(result_array)


def compare_images_ssim(img1, img2):
    """Compare two images using Structural Similarity Index."""
    try:
        from skimage.metrics import structural_similarity as ssim
        
        # Ensure same size
        if img1.size != img2.size:
            img2 = img2.resize(img1.size)
        
        # Convert to RGB and numpy arrays
        if img1.mode != 'RGB':
            img1 = img1.convert('RGB')
        if img2.mode != 'RGB':
            img2 = img2.convert('RGB')
        
        arr1 = np.array(img1)
        arr2 = np.array(img2)
        
        # Calculate SSIM
        try:
            # Try newer scikit-image API
            similarity = ssim(arr1, arr2, channel_axis=2)
        except TypeError:
            # Fall back to older API
            similarity = ssim(arr1, arr2, multichannel=True)
        
        return similarity
    except ImportError:
        # Fallback to basic pixel difference if SSIM not available
        if img1.size != img2.size:
            img2 = img2.resize(img1.size)
        
        arr1 = np.array(img1.convert('RGB'))
        arr2 = np.array(img2.convert('RGB'))
        
        # Calculate normalized pixel difference
        diff = np.mean(np.abs(arr1.astype(float) - arr2.astype(float))) / 255.0
        # Convert to similarity score (1 = identical, 0 = completely different)
        similarity = 1.0 - diff
        return similarity


def check_brightness_reduction(original_img, result_img):
    """Check if the result image is appropriately darkened compared to original."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('L'))  # Convert to grayscale
    result_array = np.array(result_img.convert('L'))
    
    orig_brightness = np.mean(orig_array)
    result_brightness = np.mean(result_array)
    
    brightness_reduction = (orig_brightness - result_brightness) / orig_brightness
    
    return {
        'orig_brightness': orig_brightness,
        'result_brightness': result_brightness,
        'brightness_reduction': brightness_reduction,
        'appropriately_darkened': 0.15 <= brightness_reduction <= 0.6  # 15-60% reduction
    }


def check_blend_mode_multiply(traj, env_info, task_info):
    """
    Main verifier function for blend mode multiply task.
    Checks:
    1. XCF file contains top layer with Multiply blend mode
    2. Visual result matches mathematical Multiply reference
    3. Image is appropriately darkened
    4. Layers are preserved (not flattened)
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
        "/home/ga/Desktop/blended_multiply.png",
        "/home/ga/Desktop/blended_multiply.jpg",
        "/home/ga/Desktop/blend_composition.png",
        "/home/ga/Desktop/base_landscape_edited.png"
    ]
    
    possible_xcf_files = [
        "/home/ga/Desktop/blended_multiply.xcf",
        "/home/ga/Desktop/blend_composition.xcf"
    ]
    
    # For base images, we'll try to get the original components
    base_files = [
        "/home/ga/Desktop/base_landscape.jpg",
        "/home/ga/Desktop/overlay_orange.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/base_landscape.jpg",  # Primary original
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
    
    # Create temp directory for additional files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        try:
            # Load the result image
            result_image = Image.open(file_info["result_path"])
            logging.debug(f"Found result image at: {file_info['result_container_path']}")
            
            # Try to copy and analyze XCF file
            xcf_success = False
            xcf_info = None
            
            for xcf_path in possible_xcf_files:
                try:
                    temp_xcf = temp_path / "composition.xcf"
                    copy_from_env(xcf_path, str(temp_xcf))
                    success, xcf_info = parse_xcf_blend_mode(temp_xcf)
                    if success:
                        xcf_success = True
                        logging.debug(f"Successfully parsed XCF: {xcf_path}")
                        break
                except Exception as e:
                    logging.debug(f"Could not process XCF {xcf_path}: {e}")
                    continue
            
            # Try to get overlay image for visual reference creation
            overlay_image = None
            try:
                temp_overlay = temp_path / "overlay.png"
                copy_from_env("/home/ga/Desktop/overlay_orange.png", str(temp_overlay))
                overlay_image = Image.open(temp_overlay)
            except Exception as e:
                logging.debug(f"Could not get overlay image: {e}")
            
            # Try to get base image for comparison
            base_image = None
            try:
                base_image = Image.open(file_info["original_path"])
            except Exception as e:
                logging.debug(f"Could not load base image: {e}")
            
            feedback_parts = []
            feedback_parts.append(f"Result image size: {result_image.size}")
            
            # Evaluate success based on multiple criteria
            criteria_met = 0
            total_criteria = 4
            
            # 1. XCF Analysis (Primary validation)
            if xcf_success and xcf_info:
                feedback_parts.append(f"XCF layers found: {xcf_info['layer_count']}")
                feedback_parts.append(f"Blend mode: {xcf_info['blend_mode']}")
                if xcf_info['is_multiply']:
                    criteria_met += 1
                    feedback_parts.append("Top layer blend mode: ✅ Multiply")
                else:
                    feedback_parts.append(f"Top layer blend mode: ❌ {xcf_info['blend_mode']} (not Multiply)")
            else:
                feedback_parts.append("XCF analysis: ❌ Could not parse layer data")
            
            # 2. Visual Reference Comparison (Secondary validation)
            visual_match = False
            if base_image and overlay_image:
                try:
                    reference_multiply = create_multiply_reference(base_image, overlay_image)
                    ssim_score = compare_images_ssim(reference_multiply, result_image)
                    visual_match = ssim_score >= 0.85
                    if visual_match:
                        criteria_met += 1
                    feedback_parts.append(f"Visual similarity: {ssim_score:.3f} ({'✅' if visual_match else '❌'})")
                except Exception as e:
                    feedback_parts.append(f"Visual comparison failed: {str(e)}")
            else:
                feedback_parts.append("Visual comparison: ❌ Missing base/overlay images")
            
            # 3. Brightness Analysis
            darkening_ok = False
            if base_image:
                try:
                    brightness_analysis = check_brightness_reduction(base_image, result_image)
                    darkening_ok = brightness_analysis['appropriately_darkened']
                    if darkening_ok:
                        criteria_met += 1
                    feedback_parts.append(f"Brightness reduction: {brightness_analysis['brightness_reduction']:.1%} ({'✅' if darkening_ok else '❌'})")
                except Exception as e:
                    feedback_parts.append(f"Brightness analysis failed: {str(e)}")
            else:
                feedback_parts.append("Brightness analysis: ❌ No base image for comparison")
            
            # 4. Layer Preservation Check
            layers_preserved = xcf_success and xcf_info and xcf_info['layer_count'] >= 2
            if layers_preserved:
                criteria_met += 1
            feedback_parts.append(f"Layers preserved: {'✅' if layers_preserved else '❌'}")
            
            # Calculate final score
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            if passed and score >= 90:
                feedback_parts.append("🎉 Perfect blend mode application!")
            elif passed:
                feedback_parts.append("✅ Good blend mode application!")
            else:
                feedback_parts.append("❌ Blend mode change needs improvement")
                
            return {
                "passed": passed,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            logging.error(f"Error in blend mode verification: {e}")
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
    result = check_blend_mode_multiply([], {}, {})
    print(f"Test result: {result}")