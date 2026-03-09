#!/usr/bin/env python3
"""
Verifier for GIMP solid noise render task.
Checks if solid noise texture was successfully generated with proper characteristics.
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


def calculate_entropy(image_array):
    """Calculate Shannon entropy of image to measure randomness."""
    if len(image_array.shape) == 3:
        # Convert to grayscale for entropy calculation
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    # Calculate histogram
    histogram, _ = np.histogram(gray.flatten(), bins=256, range=(0, 256))
    histogram = histogram / histogram.sum()  # Normalize
    
    # Calculate entropy (avoiding log(0) with small epsilon)
    entropy = -np.sum(histogram * np.log2(histogram + 1e-10))
    return entropy


def calculate_spatial_variance(image_array):
    """Calculate standard deviation of pixel intensities."""
    if len(image_array.shape) == 3:
        # Convert to grayscale for variance calculation
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    return np.std(gray)


def analyze_frequency_content(image_array):
    """
    Analyze frequency domain characteristics.
    Good noise should have distributed frequency content, not concentrated in low frequencies.
    """
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    try:
        # Compute 2D FFT
        fft = np.fft.fft2(gray)
        fft_shift = np.fft.fftshift(fft)
        magnitude = np.abs(fft_shift)
        
        # Analyze spectral distribution
        # Check energy distribution - noise should not be concentrated only in low frequencies
        center = np.array(magnitude.shape) // 2
        
        # Define low frequency region (center 20x20 pixels)
        low_freq_size = 10
        low_freq_energy = np.sum(magnitude[center[0]-low_freq_size:center[0]+low_freq_size, 
                                          center[1]-low_freq_size:center[1]+low_freq_size])
        total_energy = np.sum(magnitude)
        
        # Good noise should have <60% energy concentrated in very low frequencies
        low_freq_ratio = low_freq_energy / total_energy if total_energy > 0 else 1.0
        has_good_freq_distribution = low_freq_ratio < 0.6
        
        return has_good_freq_distribution, low_freq_ratio
        
    except Exception as e:
        logging.warning(f"Frequency analysis failed: {e}")
        # Fallback: assume good if we can't analyze
        return True, 0.5


def check_histogram_distribution(image_array):
    """
    Check if the image has a good histogram distribution (not solid color or simple pattern).
    """
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    # Calculate histogram
    histogram, _ = np.histogram(gray.flatten(), bins=64, range=(0, 256))
    
    # Count non-empty bins
    non_empty_bins = np.sum(histogram > 0)
    
    # Good noise should use a reasonable number of different intensity values
    good_distribution = non_empty_bins >= 20  # At least 20 different intensity ranges
    
    # Check if distribution is too concentrated (like a solid color)
    max_bin_percentage = np.max(histogram) / np.sum(histogram)
    not_too_concentrated = max_bin_percentage < 0.7  # No single intensity dominates >70%
    
    return good_distribution and not_too_concentrated, non_empty_bins, max_bin_percentage


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different (not just unchanged)."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to arrays
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # >30 intensity units change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    # Good noise generation should change most of the image
    meaningfully_changed = change_percentage > 80  # At least 80% of pixels significantly changed
    
    return meaningfully_changed, change_percentage, mean_diff


def check_solid_noise(traj, env_info, task_info):
    """
    Main verifier function for solid noise render task.
    Checks:
    1. High variance indicates significant pixel intensity variation
    2. High entropy indicates randomness and information content
    3. Good histogram distribution (not uniform or concentrated)
    4. Frequency content indicates noise-like characteristics  
    5. Image was meaningfully modified from original
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
        "/home/ga/Desktop/solid_noise_texture.png",
        "/home/ga/Desktop/solid_noise_texture.jpg", 
        "/home/ga/Desktop/solid_noise_texture.jpeg",
        "/home/ga/Desktop/noise_texture.png",
        "/home/ga/Desktop/texture.png",
        "/home/ga/Desktop/blank_canvas_noise.png"
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
        
        # Convert result image to array for analysis
        result_array = np.array(result_image)
        
        # 1. Check variance (should be high for good noise)
        variance = calculate_spatial_variance(result_array)
        high_variance = variance > 30
        
        # 2. Check entropy (should be high for random noise)
        entropy = calculate_entropy(result_array)
        high_entropy = entropy > 6.0
        
        # 3. Check histogram distribution
        good_histogram, non_empty_bins, max_concentration = check_histogram_distribution(result_array)
        
        # 4. Check frequency content
        good_frequency_dist, low_freq_ratio = analyze_frequency_content(result_array)
        
        # 5. Check if image was meaningfully changed from original
        meaningfully_changed, change_percentage, mean_diff = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Pixel variance: {variance:.1f} (need >30)")
        feedback_parts.append(f"Image entropy: {entropy:.2f} bits (need >6.0)")
        feedback_parts.append(f"Histogram bins used: {non_empty_bins}/64")
        feedback_parts.append(f"Max intensity concentration: {max_concentration:.1%}")
        feedback_parts.append(f"Low frequency ratio: {low_freq_ratio:.2f}")
        feedback_parts.append(f"Pixels changed: {change_percentage:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        if high_variance:
            criteria_met += 1
        feedback_parts.append(f"High variance: {'✅' if high_variance else '❌'}")
        
        if high_entropy:
            criteria_met += 1
        feedback_parts.append(f"High entropy: {'✅' if high_entropy else '❌'}")
        
        if good_histogram:
            criteria_met += 1
        feedback_parts.append(f"Good distribution: {'✅' if good_histogram else '❌'}")
        
        if good_frequency_dist:
            criteria_met += 1
        feedback_parts.append(f"Good frequency content: {'✅' if good_frequency_dist else '❌'}")
        
        if meaningfully_changed:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if meaningfully_changed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent solid noise generation!")
        elif passed:
            feedback_parts.append("✅ Good solid noise texture created!")
        else:
            feedback_parts.append("❌ Solid noise generation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in solid noise verification: {e}")
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
    result = check_solid_noise([], {}, {})
    print(f"Test result: {result}")