#!/usr/bin/env python3
"""
Verifier for GIMP checkerboard pattern task.
Checks if a regular checkerboard pattern was successfully generated.
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


def detect_checkerboard_pattern_fft(image):
    """
    Use FFT to detect periodic checkerboard pattern.
    Returns (has_pattern, num_peaks, pattern_strength).
    """
    # Convert to grayscale for frequency analysis
    if image.mode != 'L':
        gray = image.convert('L')
    else:
        gray = image
    
    gray_array = np.array(gray, dtype=np.float32)
    
    try:
        # Compute 2D Fourier Transform
        f_transform = np.fft.fft2(gray_array)
        f_shift = np.fft.fftshift(f_transform)
        magnitude = np.abs(f_shift)
        
        # Detect peaks indicating periodic pattern
        height, width = magnitude.shape
        center_y, center_x = height // 2, width // 2
        
        # Analyze off-center peaks (checkerboard creates symmetric peaks)
        threshold = np.percentile(magnitude, 99.5)
        peaks = magnitude > threshold
        
        # Count significant peaks excluding DC component
        peaks[center_y-5:center_y+5, center_x-5:center_x+5] = False
        num_peaks = np.sum(peaks)
        
        # Checkerboard typically produces 4-8 strong peaks
        has_periodic_pattern = num_peaks >= 4
        
        # Calculate pattern strength
        pattern_strength = np.mean(magnitude[peaks]) if num_peaks > 0 else 0
        
        logging.debug(f"FFT Analysis: peaks={num_peaks}, strength={pattern_strength:.2f}, periodic={has_periodic_pattern}")
        
        return has_periodic_pattern, num_peaks, pattern_strength
        
    except Exception as e:
        logging.error(f"FFT analysis failed: {e}")
        return False, 0, 0


def analyze_checkerboard_colors(image):
    """
    Check for two-color alternating pattern characteristic of checkerboards.
    Returns (is_balanced, has_contrast, distribution).
    """
    img_array = np.array(image.convert('RGB'))
    
    # Flatten to analyze color distribution
    pixels = img_array.reshape(-1, 3)
    
    try:
        # Use k-means clustering to find dominant colors
        from sklearn.cluster import KMeans
        kmeans = KMeans(n_clusters=2, random_state=42, n_init=10)
        kmeans.fit(pixels)
        
        labels = kmeans.labels_
        unique, counts = np.unique(labels, return_counts=True)
        
        # Check for roughly equal distribution (40-60% tolerance)
        total = len(labels)
        distribution = counts / total
        is_balanced = all(0.4 <= d <= 0.6 for d in distribution)
        
        # Check contrast between two colors
        colors = kmeans.cluster_centers_
        color_diff = np.linalg.norm(colors[0] - colors[1])
        has_contrast = color_diff > 60  # Sufficient contrast for checkerboard
        
        logging.debug(f"Color Analysis: balanced={is_balanced}, contrast={has_contrast}, diff={color_diff:.1f}")
        logging.debug(f"Color distribution: {distribution}")
        
        return is_balanced, has_contrast, distribution
        
    except ImportError:
        # Fallback without sklearn
        logging.warning("sklearn not available, using simple color analysis")
        
        # Simple analysis: check for sufficient variation in grayscale
        gray = np.array(image.convert('L'))
        std_dev = np.std(gray)
        mean_val = np.mean(gray)
        
        # Good checkerboard should have high standard deviation
        has_variation = std_dev > 50  # Significant variation
        is_balanced = 80 < mean_val < 175  # Not too dark or too light
        has_contrast = has_variation  # Use variation as proxy for contrast
        
        return is_balanced, has_contrast, [0.5, 0.5]  # Assume balanced


def validate_grid_structure(image):
    """
    Check for alternating pattern in spatial domain.
    Returns (has_grid, alternation_strength).
    """
    gray = np.array(image.convert('L'))
    
    # Check for checkerboard alternation at different scales
    best_alternation = 0
    has_grid = False
    
    for scale in [4, 8, 16, 20, 32]:
        if gray.shape[0] < scale*2 or gray.shape[1] < scale*2:
            continue
            
        h, w = gray.shape
        small = gray[::scale, ::scale]
        
        if small.shape[0] < 2 or small.shape[1] < 2:
            continue
        
        # Check for checkerboard alternation
        # In a checkerboard, adjacent cells should differ significantly
        h_diff = np.abs(np.diff(small.astype(np.float32), axis=1))
        v_diff = np.abs(np.diff(small.astype(np.float32), axis=0))
        
        h_alternation = np.mean(h_diff)
        v_alternation = np.mean(v_diff)
        avg_alternation = (h_alternation + v_alternation) / 2
        
        if avg_alternation > best_alternation:
            best_alternation = avg_alternation
        
        # Strong differences indicate alternation
        if h_alternation > 40 and v_alternation > 40:
            has_grid = True
            logging.debug(f"Grid detected at scale {scale}: h_alt={h_alternation:.1f}, v_alt={v_alternation:.1f}")
    
    logging.debug(f"Grid Analysis: has_grid={has_grid}, best_alternation={best_alternation:.1f}")
    return has_grid, best_alternation


def generate_reference_checkerboard(size, check_size=20):
    """
    Generate a perfect reference checkerboard for comparison.
    """
    width, height = size
    
    # Create checkerboard pattern
    checkerboard = np.zeros((height, width), dtype=np.uint8)
    
    for y in range(height):
        for x in range(width):
            # Determine which check we're in
            check_x = x // check_size
            check_y = y // check_size
            
            # Alternate between 0 (black) and 255 (white)
            if (check_x + check_y) % 2 == 0:
                checkerboard[y, x] = 255
            else:
                checkerboard[y, x] = 0
    
    return Image.fromarray(checkerboard, mode='L')


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('L'))
    result_array = np.array(result_img.convert('L'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(diff > 50)  # Pixels with >50 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 70  # At least 70% of pixels changed significantly
    }


def check_checkerboard_pattern(traj, env_info, task_info):
    """
    Main verifier function for checkerboard pattern task.
    Checks:
    1. Pattern regularity using FFT analysis
    2. Two-color distribution (approximately 50/50)
    3. Sufficient contrast between colors
    4. Grid structure with alternating pattern
    5. Image was meaningfully modified
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
        "/home/ga/Desktop/checkerboard_pattern.png",
        "/home/ga/Desktop/checkerboard_pattern.jpg",
        "/home/ga/Desktop/checkerboard.png",
        "/home/ga/Desktop/pattern.png",
        "/home/ga/Desktop/blank_canvas.png"  # In case they modified original
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/blank_canvas.png",
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
        
        # 1. Analyze pattern regularity using FFT
        has_periodic_pattern, num_peaks, pattern_strength = detect_checkerboard_pattern_fft(result_image)
        
        # 2. Analyze color distribution
        is_balanced, has_contrast, distribution = analyze_checkerboard_colors(result_image)
        
        # 3. Validate grid structure
        has_grid, alternation_strength = validate_grid_structure(result_image)
        
        # 4. Check for meaningful change from original
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"FFT peaks detected: {num_peaks}")
        feedback_parts.append(f"Pattern strength: {pattern_strength:.1f}")
        feedback_parts.append(f"Color distribution: {[f'{d:.1%}' for d in distribution]}")
        feedback_parts.append(f"Contrast ratio: {has_contrast}")
        feedback_parts.append(f"Alternation strength: {alternation_strength:.1f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Pattern regularity (FFT shows periodic structure)
        if has_periodic_pattern:
            criteria_met += 1
        feedback_parts.append(f"Pattern regularity: {'✅' if has_periodic_pattern else '❌'}")
        
        # 2. Two-color distribution (approximately 50/50)
        if is_balanced:
            criteria_met += 1
        feedback_parts.append(f"Color balance: {'✅' if is_balanced else '❌'}")
        
        # 3. Sufficient contrast
        if has_contrast:
            criteria_met += 1
        feedback_parts.append(f"Good contrast: {'✅' if has_contrast else '❌'}")
        
        # 4. Grid structure detected
        if has_grid:
            criteria_met += 1
        feedback_parts.append(f"Grid structure: {'✅' if has_grid else '❌'}")
        
        # 5. Meaningful change
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) - adjusting threshold to 75%
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect checkerboard pattern!")
        elif passed:
            feedback_parts.append("✅ Good checkerboard pattern!")
        else:
            feedback_parts.append("❌ Checkerboard pattern needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in checkerboard verification: {e}")
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
    result = check_checkerboard_pattern([], {}, {})
    print(f"Test result: {result}")