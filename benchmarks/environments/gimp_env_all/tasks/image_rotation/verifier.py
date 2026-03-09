#!/usr/bin/env python3
"""
Verifier for GIMP image rotation task.
Checks if image was rotated to correct orientation by detecting rotation angle
and measuring horizon alignment improvement.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def detect_rotation_angle_correlation(original_img, result_img, expected_angle=-15.0, tolerance=5.0):
    """
    Detect rotation angle between images using cross-correlation analysis.
    
    Args:
        original_img: Original PIL image
        result_img: Result PIL image  
        expected_angle: Expected rotation angle in degrees
        tolerance: Angle search tolerance in degrees
        
    Returns:
        dict: Analysis results including detected angle and confidence
    """
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L'))
    else:
        orig_gray = np.array(original_img)
        
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L'))
    else:
        result_gray = np.array(result_img)
    
    # Ensure images are same size
    if orig_gray.shape != result_gray.shape:
        # Resize result to match original for comparison
        result_pil = Image.fromarray(result_gray).resize(original_img.size)
        result_gray = np.array(result_pil)
    
    try:
        from scipy.ndimage import rotate
        from skimage.feature import match_template
        
        # Test angles around expected value
        test_angles = np.arange(expected_angle - tolerance, expected_angle + tolerance + 0.5, 0.5)
        correlations = []
        
        for angle in test_angles:
            # Generate reference rotation
            test_rotated = rotate(orig_gray, angle, reshape=False, order=1, mode='constant', cval=0)
            
            # Crop to avoid black borders affecting correlation
            h, w = test_rotated.shape
            margin = int(min(h, w) * 0.1)  # 10% margin
            test_cropped = test_rotated[margin:h-margin, margin:w-margin]
            result_cropped = result_gray[margin:h-margin, margin:w-margin]
            
            if test_cropped.size == 0 or result_cropped.size == 0:
                correlations.append(0)
                continue
            
            # Compute normalized cross-correlation
            correlation = np.corrcoef(test_cropped.flatten(), result_cropped.flatten())[0, 1]
            if np.isnan(correlation):
                correlation = 0
            correlations.append(correlation)
        
        # Find peak correlation and corresponding angle
        if len(correlations) > 0:
            best_idx = np.argmax(correlations)
            detected_angle = test_angles[best_idx]
            confidence = correlations[best_idx]
            
            # Check if angle is within tolerance
            angle_error = abs(detected_angle - expected_angle)
            angle_accurate = angle_error <= 3.0  # Allow 3 degree tolerance
            
            return {
                'detected_angle': detected_angle,
                'expected_angle': expected_angle,
                'angle_error': angle_error,
                'angle_accurate': angle_accurate,
                'confidence': confidence,
                'correlation_successful': True
            }
        else:
            return {
                'detected_angle': None,
                'expected_angle': expected_angle,
                'angle_error': float('inf'),
                'angle_accurate': False,
                'confidence': 0,
                'correlation_successful': False
            }
            
    except ImportError:
        logging.warning("SciPy/scikit-image not available, using fallback method")
        return detect_rotation_fallback(orig_gray, result_gray, expected_angle)


def detect_rotation_fallback(orig_gray, result_gray, expected_angle):
    """Fallback rotation detection using simple pixel differences."""
    # Simple check: see if images are different enough to indicate rotation
    if orig_gray.shape == result_gray.shape:
        pixel_diff = np.mean(np.abs(orig_gray.astype(np.float32) - result_gray.astype(np.float32)))
        rotation_detected = pixel_diff > 10  # Threshold for meaningful change
        
        return {
            'detected_angle': expected_angle if rotation_detected else 0,
            'expected_angle': expected_angle,
            'angle_error': 0 if rotation_detected else abs(expected_angle),
            'angle_accurate': rotation_detected,
            'confidence': 0.8 if rotation_detected else 0.2,
            'correlation_successful': False
        }
    else:
        return {
            'detected_angle': expected_angle,  # Assume correct if size changed
            'expected_angle': expected_angle,
            'angle_error': 0,
            'angle_accurate': True,
            'confidence': 0.9,
            'correlation_successful': False
        }


def analyze_horizon_alignment(original_img, result_img):
    """
    Analyze horizon alignment improvement using edge detection.
    
    Args:
        original_img: Original PIL image
        result_img: Result PIL image
        
    Returns:
        dict: Analysis of horizon alignment before and after
    """
    def get_horizontal_line_angles(img):
        """Extract angles of horizontal-ish lines in image."""
        try:
            from skimage import filters, feature
            
            gray = np.array(img.convert('L'))
            
            # Edge detection
            edges = feature.canny(gray, sigma=2, low_threshold=0.1, high_threshold=0.2)
            
            # Hough line detection for near-horizontal lines
            from skimage.transform import hough_line, hough_line_peaks
            
            # Focus on angles within ±30 degrees of horizontal
            angles = np.linspace(-np.pi/6, np.pi/6, 60)
            h, theta, d = hough_line(edges, theta=angles)
            
            # Get prominent lines
            peaks = hough_line_peaks(h, theta, d, threshold=0.3*np.max(h), num_peaks=10)
            
            # Convert angles to degrees
            line_angles = []
            for _, angle, _ in zip(*peaks):
                angle_deg = np.degrees(angle)
                line_angles.append(angle_deg)
            
            return line_angles
            
        except ImportError:
            # Fallback: simple gradient-based analysis
            gray = np.array(img.convert('L'))
            
            # Compute horizontal gradients
            grad_y = np.gradient(gray, axis=0)
            
            # Find rows with strong horizontal features
            row_gradients = np.std(grad_y, axis=1)
            strong_rows = np.where(row_gradients > np.percentile(row_gradients, 80))[0]
            
            # Simple heuristic for horizon alignment
            if len(strong_rows) > 0:
                # If strong horizontal features are roughly in middle third, assume good alignment
                h, w = gray.shape
                middle_third = (h//3, 2*h//3)
                middle_rows = [r for r in strong_rows if middle_third[0] <= r <= middle_third[1]]
                horizon_angle = 0 if len(middle_rows) > len(strong_rows) * 0.3 else 10  # rough estimate
                return [horizon_angle]
            else:
                return [15]  # assume tilted if no strong features
    
    # Get line angles for both images
    orig_angles = get_horizontal_line_angles(original_img)
    result_angles = get_horizontal_line_angles(result_img)
    
    # Calculate average deviation from horizontal (0 degrees)
    orig_deviation = np.mean([abs(angle) for angle in orig_angles]) if orig_angles else 15
    result_deviation = np.mean([abs(angle) for angle in result_angles]) if result_angles else 15
    
    improvement = orig_deviation - result_deviation
    
    return {
        'original_deviation': orig_deviation,
        'result_deviation': result_deviation,
        'improvement': improvement,
        'horizon_improved': improvement > 2.0  # At least 2 degree improvement
    }


def check_quality_preservation(original_img, result_img):
    """Check if rotation preserved image quality."""
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Check if dimensions are reasonable (rotation might change size slightly)
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    size_ratio = (result_w * result_h) / (orig_w * orig_h)
    size_preserved = 0.8 <= size_ratio <= 1.2  # Allow 20% size variation
    
    # Check if image was modified
    if original_img.size == result_img.size:
        orig_array = np.array(original_img)
        result_array = np.array(result_img)
        pixel_diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
        image_modified = pixel_diff > 5  # Threshold for meaningful change
    else:
        image_modified = True  # Size change indicates modification
    
    return {
        'size_preserved': size_preserved,
        'image_modified': image_modified,
        'original_size': original_img.size,
        'result_size': result_img.size
    }


def check_image_rotation(traj, env_info, task_info):
    """
    Main verifier function for image rotation task.
    Checks:
    1. Image was rotated by approximately -15 degrees (clockwise)
    2. Horizon alignment was improved
    3. Image quality was preserved
    4. Image was meaningfully modified
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
        "/home/ga/Desktop/straightened_photo.jpg",
        "/home/ga/Desktop/straightened_photo.png",
        "/home/ga/Desktop/straightened_photo.jpeg",
        "/home/ga/Desktop/tilted_landscape_rotated.jpg",
        "/home/ga/Desktop/rotated_landscape.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/tilted_landscape.jpg",
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
        # Load images from copied files
        original_image = Image.open(file_info["original_path"])
        result_image = Image.open(file_info["result_path"])
        
        logging.debug(f"Found result image at: {file_info['result_container_path']}")
        
        # Detect rotation angle
        rotation_analysis = detect_rotation_angle_correlation(original_image, result_image, -15.0, 5.0)
        
        # Analyze horizon alignment improvement
        horizon_analysis = analyze_horizon_alignment(original_image, result_image)
        
        # Check quality preservation
        quality_analysis = check_quality_preservation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Expected rotation: -15.0°")
        
        if rotation_analysis['correlation_successful']:
            feedback_parts.append(f"Detected rotation: {rotation_analysis['detected_angle']:.1f}°")
            feedback_parts.append(f"Angle error: {rotation_analysis['angle_error']:.1f}°")
        else:
            feedback_parts.append("Rotation detection: fallback method used")
        
        feedback_parts.append(f"Rotation accurate: {'✅' if rotation_analysis['angle_accurate'] else '❌'}")
        feedback_parts.append(f"Horizon improved: {'✅' if horizon_analysis['horizon_improved'] else '❌'}")
        feedback_parts.append(f"Quality preserved: {'✅' if quality_analysis['size_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if quality_analysis['image_modified'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if rotation_analysis['angle_accurate']:
            criteria_met += 1
        if horizon_analysis['horizon_improved']:
            criteria_met += 1
        if quality_analysis['size_preserved']:
            criteria_met += 1
        if quality_analysis['image_modified']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect image rotation!")
        elif passed:
            feedback_parts.append("✅ Good image rotation!")
        else:
            feedback_parts.append("❌ Image rotation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in image rotation verification: {e}")
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
    result = check_image_rotation([], {}, {})
    print(f"Test result: {result}")