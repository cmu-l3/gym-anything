#!/usr/bin/env python3
"""
Verifier for GIMP paste as new layer task.
Checks if a region was selected, copied, and pasted as a new independent layer.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile
import struct

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def try_parse_xcf_layer_count(xcf_path):
    """
    Attempt to parse XCF file and count layers using simple binary parsing.
    Returns layer count or None if parsing fails.
    """
    try:
        with open(xcf_path, 'rb') as f:
            # Read XCF header
            magic = f.read(9)  # "gimp xcf "
            if not magic.startswith(b'gimp xcf'):
                logging.debug("Not a valid XCF file")
                return None
            
            version = f.read(4)  # version string
            f.read(1)  # null terminator
            
            # Read image dimensions
            width = struct.unpack('>I', f.read(4))[0]
            height = struct.unpack('>I', f.read(4))[0]
            base_type = struct.unpack('>I', f.read(4))[0]
            
            # Skip precision info if present (newer XCF versions)
            if version >= b'v003':
                precision = struct.unpack('>I', f.read(4))[0]
            
            # Count layer offsets (simplified approach)
            layer_count = 0
            while True:
                try:
                    offset = struct.unpack('>I', f.read(4))[0]
                    if offset == 0:  # End of layer list
                        break
                    layer_count += 1
                    if layer_count > 10:  # Safety limit
                        break
                except:
                    break
            
            logging.debug(f"Parsed XCF: {width}x{height}, {layer_count} layers")
            return layer_count
            
    except Exception as e:
        logging.debug(f"XCF parsing failed: {e}")
        return None


def detect_content_duplication(original_img, result_img):
    """
    Detect if content appears duplicated in the result image.
    This would indicate paste as new layer operation occurred.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB for analysis
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Look for regions with significant change (potential duplicated content)
    magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    significant_changes = magnitude > 30  # Pixels that changed significantly
    
    change_percentage = (np.sum(significant_changes) / significant_changes.size) * 100
    
    # Analyze patterns that might indicate duplication
    # If paste as new layer occurred, some content might be intensified or overlapped
    intensified_regions = np.sum(result_array > orig_array + 20, axis=2) > 0
    intensified_percentage = (np.sum(intensified_regions) / intensified_regions.size) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'intensified_percentage': intensified_percentage,
        'content_modified': change_percentage > 5 or intensified_percentage > 2
    }


def analyze_layer_structure_indicators(result_img):
    """
    Analyze the result image for indicators of multi-layer composition.
    Look for signs that content was pasted on top of existing content.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    
    # Look for areas with high color intensity (might indicate overlapped content)
    high_intensity = np.sum(img_array > 200, axis=2) >= 2  # At least 2 channels very bright
    high_intensity_percentage = (np.sum(high_intensity) / high_intensity.size) * 100
    
    # Look for edge artifacts that might indicate layer boundaries
    gray = np.mean(img_array, axis=2)
    edges = np.abs(np.gradient(gray)[0]) + np.abs(np.gradient(gray)[1])
    strong_edges = edges > np.percentile(edges, 90)
    edge_density = (np.sum(strong_edges) / strong_edges.size) * 100
    
    return {
        'high_intensity_percentage': high_intensity_percentage,
        'edge_density': edge_density,
        'suggests_layers': high_intensity_percentage > 5 or edge_density > 8
    }


def check_paste_as_new_layer(traj, env_info, task_info):
    """
    Main verifier function for paste as new layer task.
    Checks:
    1. XCF file indicates multiple layers (preferred method)
    2. Evidence of content duplication in flattened result
    3. Image was meaningfully modified
    4. Layer structure indicators present
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
        "/home/ga/Desktop/paste_layers_result.xcf",  # XCF with layers
        "/home/ga/Desktop/paste_result_flattened.jpg",  # Flattened result
        "/home/ga/Desktop/paste_result_flattened.png",
        "/home/ga/Desktop/composite_image_edited.xcf",
        "/home/ga/Desktop/composite_image_result.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/composite_image.jpg",
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
        # Load original image
        original_image = Image.open(file_info["original_path"])
        
        # Try to analyze XCF file first (preferred method)
        xcf_layer_count = None
        if file_info["result_container_path"].endswith('.xcf'):
            xcf_layer_count = try_parse_xcf_layer_count(file_info["result_path"])
            logging.debug(f"XCF layer count: {xcf_layer_count}")
        
        # Also try to load result as image for additional analysis
        result_image = None
        try:
            # For XCF files, this might not work, but try anyway
            result_image = Image.open(file_info["result_path"])
        except Exception as e:
            logging.debug(f"Could not load result as image: {e}")
            # Try to find flattened version
            flattened_candidates = [
                "/home/ga/Desktop/paste_result_flattened.jpg",
                "/home/ga/Desktop/paste_result_flattened.png"
            ]
            for candidate in flattened_candidates:
                temp_flattened = Path(file_info["temp_dir"]) / f"flattened_{Path(candidate).name}"
                success, _ = setup_verification_environment(
                    candidate, [candidate], copy_from_env, "/home/ga/Desktop"
                )
                if success:
                    try:
                        # Try to copy flattened file
                        copy_from_env(candidate, str(temp_flattened))
                        result_image = Image.open(temp_flattened)
                        logging.debug(f"Loaded flattened result from {candidate}")
                        break
                    except Exception as e2:
                        logging.debug(f"Could not load flattened result: {e2}")
                        continue
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result file: {Path(file_info['result_container_path']).name}")
        
        # Count criteria met
        criteria_met = 0
        total_criteria = 4
        
        # Criterion 1: Multiple layers detected (XCF analysis)
        multiple_layers_detected = xcf_layer_count is not None and xcf_layer_count >= 2
        if multiple_layers_detected:
            criteria_met += 1
            feedback_parts.append(f"Multiple layers detected: ✅ ({xcf_layer_count} layers)")
        else:
            feedback_parts.append(f"Multiple layers detected: ❌ ({xcf_layer_count or 'unknown'})")
        
        # Criteria 2-4: Analyze flattened result if available
        if result_image is not None:
            feedback_parts.append(f"Result size: {result_image.size}")
            
            # Criterion 2: Content duplication analysis
            duplication_analysis = detect_content_duplication(original_image, result_image)
            content_duplicated = duplication_analysis['content_modified']
            if content_duplicated:
                criteria_met += 1
            feedback_parts.append(f"Content duplication detected: {'✅' if content_duplicated else '❌'}")
            feedback_parts.append(f"Change percentage: {duplication_analysis['change_percentage']:.1f}%")
            
            # Criterion 3: Layer structure indicators
            structure_analysis = analyze_layer_structure_indicators(result_image)
            layer_indicators = structure_analysis['suggests_layers']
            if layer_indicators:
                criteria_met += 1
            feedback_parts.append(f"Layer structure indicators: {'✅' if layer_indicators else '❌'}")
            
            # Criterion 4: Image modified from original
            images_different = not np.array_equal(
                np.array(original_image.convert('RGB')), 
                np.array(result_image.convert('RGB').resize(original_image.size))
            )
            if images_different:
                criteria_met += 1
            feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        else:
            feedback_parts.append("Result analysis: ❌ (could not load result image)")
        
        # Calculate success based on criteria
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent paste as new layer operation!")
        elif passed:
            feedback_parts.append("✅ Good paste as new layer operation!")
        else:
            feedback_parts.append("❌ Paste as new layer operation not detected")
        
        feedback_parts.append(f"Criteria met: {criteria_met}/{total_criteria}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in paste as new layer verification: {e}")
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
    result = check_paste_as_new_layer([], {}, {})
    print(f"Test result: {result}")