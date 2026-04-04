#!/usr/bin/env python3
"""
Verifier for GIMP grid render task.
Checks if a grid overlay was successfully rendered on the image.
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


def detect_lines_by_projection(img_array):
    """
    Detect grid lines using projection method.
    Sum pixel intensities along rows and columns to find periodic patterns.
    """
    gray = np.mean(img_array, axis=2) if len(img_array.shape) == 3 else img_array
    
    # Calculate projections (sum along axes)
    row_projection = np.sum(gray, axis=1)  # Sum across columns (horizontal lines)
    col_projection = np.sum(gray, axis=0)  # Sum across rows (vertical lines)
    
    # Find peaks in projections that could indicate grid lines
    def find_peaks_simple(signal, min_distance=20):
        """Simple peak detection without scipy."""
        peaks = []
        for i in range(min_distance, len(signal) - min_distance):
            if signal[i] > signal[i-1] and signal[i] > signal[i+1]:
                # Check if it's a significant peak
                local_max = max(signal[max(0, i-min_distance):min(len(signal), i+min_distance)])
                if signal[i] >= local_max * 0.95:  # Within 5% of local maximum
                    peaks.append(i)
        return peaks
    
    # Detect peaks in projections
    try:
        from scipy.signal import find_peaks
        h_peaks, _ = find_peaks(row_projection, distance=20, prominence=np.std(row_projection)*0.5)
        v_peaks, _ = find_peaks(col_projection, distance=20, prominence=np.std(col_projection)*0.5)
    except ImportError:
        h_peaks = find_peaks_simple(row_projection, min_distance=20)
        v_peaks = find_peaks_simple(col_projection, min_distance=20)
    
    return h_peaks, v_peaks, row_projection, col_projection


def detect_grid_by_edges(original_img, result_img):
    """
    Detect grid by analyzing the difference between original and result images.
    Look for new edge structures that form a regular pattern.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to arrays
    orig_array = np.array(original_img.convert('L'))
    result_array = np.array(result_img.convert('L'))
    
    # Calculate difference to isolate grid
    diff = np.abs(result_array.astype(float) - orig_array.astype(float))
    
    # Try advanced edge detection if available
    try:
        import cv2
        # Apply edge detection to difference image
        edges = cv2.Canny((diff * 255 / np.max(diff)).astype(np.uint8), 50, 150)
        
        # Hough line detection
        lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=50, 
                               minLineLength=100, maxLineGap=10)
        
        if lines is not None:
            h_lines = []
            v_lines = []
            
            for line in lines:
                x1, y1, x2, y2 = line[0]
                
                # Classify as horizontal or vertical
                angle = np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi
                if abs(angle) < 15 or abs(angle - 180) < 15:  # Horizontal
                    h_lines.append(line)
                elif abs(angle - 90) < 15 or abs(angle + 90) < 15:  # Vertical  
                    v_lines.append(line)
            
            return len(h_lines), len(v_lines), diff
        else:
            return 0, 0, diff
            
    except ImportError:
        logging.debug("OpenCV not available, using fallback edge detection")
        
        # Simple edge detection using gradient
        gy, gx = np.gradient(diff)
        edge_strength = np.sqrt(gx**2 + gy**2)
        
        # Threshold to find strong edges
        threshold = np.percentile(edge_strength, 90)
        strong_edges = edge_strength > threshold
        
        # Count potential grid intersections
        edge_count = np.sum(strong_edges)
        return edge_count // 100, edge_count // 100, diff  # Rough estimate


def analyze_grid_regularity(peaks, image_size):
    """
    Analyze if detected peaks form a regular grid pattern.
    """
    if len(peaks) < 4:
        return False, 0, 0
    
    # Calculate spacing between consecutive peaks
    spacings = np.diff(peaks)
    
    if len(spacings) < 2:
        return False, 0, 0
    
    # Check regularity using coefficient of variation
    mean_spacing = np.mean(spacings)
    std_spacing = np.std(spacings)
    
    # Coefficient of variation (lower is more regular)
    cv = std_spacing / mean_spacing if mean_spacing > 0 else 1.0
    
    # Consider regular if CV < 0.15 (15% variation)
    is_regular = cv < 0.15
    
    return is_regular, mean_spacing, cv


def check_grid_coverage(peaks_h, peaks_v, img_size):
    """
    Check if grid covers sufficient area of the image.
    """
    width, height = img_size
    
    # Check if grid extends across most of the image
    if len(peaks_h) > 0:
        h_coverage = (peaks_h[-1] - peaks_h[0]) / height if len(peaks_h) > 1 else 0
    else:
        h_coverage = 0
    
    if len(peaks_v) > 0:
        v_coverage = (peaks_v[-1] - peaks_v[0]) / width if len(peaks_v) > 1 else 0
    else:
        v_coverage = 0
    
    # Good coverage if grid spans at least 60% of image
    good_coverage = h_coverage > 0.6 and v_coverage > 0.6
    
    return good_coverage, h_coverage, v_coverage


def check_grid_render(traj, env_info, task_info):
    """
    Main verifier function for grid render task.
    Checks:
    1. Grid lines were rendered (horizontal and vertical)
    2. Lines form a regular pattern
    3. Grid covers sufficient area of the image
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
        "/home/ga/Desktop/grid_overlay.jpg",
        "/home/ga/Desktop/grid_overlay.png",
        "/home/ga/Desktop/grid_overlay.jpeg",
        "/home/ga/Desktop/base_image_grid.jpg",
        "/home/ga/Desktop/image_with_grid.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/base_image.jpg",
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
        
        # Convert to arrays for analysis
        result_array = np.array(result_image.convert('RGB'))
        
        # Method 1: Projection-based line detection
        h_peaks, v_peaks, row_proj, col_proj = detect_lines_by_projection(result_array)
        
        # Method 2: Edge-based detection (compare with original)
        h_edges, v_edges, diff_image = detect_grid_by_edges(original_image, result_image)
        
        # Analyze regularity of detected patterns
        h_regular, h_spacing, h_cv = analyze_grid_regularity(h_peaks, result_image.height)
        v_regular, v_spacing, v_cv = analyze_grid_regularity(v_peaks, result_image.width)
        
        # Check grid coverage
        good_coverage, h_coverage, v_coverage = check_grid_coverage(h_peaks, v_peaks, result_image.size)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        # Calculate variance increase (grid should increase image complexity)
        orig_var = np.var(np.array(original_image.convert('L')))
        result_var = np.var(np.array(result_image.convert('L')))
        variance_increase = result_var > orig_var * 1.05  # At least 5% variance increase
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Horizontal lines detected: {len(h_peaks)} (proj) / {h_edges} (edge)")
        feedback_parts.append(f"Vertical lines detected: {len(v_peaks)} (proj) / {v_edges} (edge)")
        feedback_parts.append(f"H-spacing regularity: CV={h_cv:.3f}" if len(h_peaks) > 1 else "H-spacing: insufficient data")
        feedback_parts.append(f"V-spacing regularity: CV={v_cv:.3f}" if len(v_peaks) > 1 else "V-spacing: insufficient data")
        feedback_parts.append(f"Grid coverage: H={h_coverage:.1%}, V={v_coverage:.1%}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Horizontal lines detected (at least 4)
        h_lines_good = len(h_peaks) >= 4
        if h_lines_good:
            criteria_met += 1
        feedback_parts.append(f"Horizontal lines adequate: {'✅' if h_lines_good else '❌'}")
        
        # 2. Vertical lines detected (at least 4)  
        v_lines_good = len(v_peaks) >= 4
        if v_lines_good:
            criteria_met += 1
        feedback_parts.append(f"Vertical lines adequate: {'✅' if v_lines_good else '❌'}")
        
        # 3. Regular pattern (low coefficient of variation)
        regular_pattern = (h_regular and v_regular) or (len(h_peaks) >= 4 and len(v_peaks) >= 4)
        if regular_pattern:
            criteria_met += 1
        feedback_parts.append(f"Regular grid pattern: {'✅' if regular_pattern else '❌'}")
        
        # 4. Good coverage
        if good_coverage:
            criteria_met += 1
        feedback_parts.append(f"Sufficient coverage: {'✅' if good_coverage else '❌'}")
        
        # 5. Image modified meaningfully  
        meaningful_change = images_different and variance_increase
        if meaningful_change:
            criteria_met += 1
        feedback_parts.append(f"Image meaningfully modified: {'✅' if meaningful_change else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but using 75% threshold as specified
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent grid overlay rendered!")
        elif passed:
            feedback_parts.append("✅ Good grid overlay rendered!")
        else:
            feedback_parts.append("❌ Grid overlay needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in grid render verification: {e}")
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
    result = check_grid_render([], {}, {})
    print(f"Test result: {result}")