#!/usr/bin/env python3
"""
Verifier for GIMP despeckle (noise reduction) task.
Checks if noise was successfully reduced while preserving image quality.
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

# Try to import advanced image processing libraries
try:
    from scipy.ndimage import uniform_filter
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    logging.warning("SciPy not available, using basic noise analysis")

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SSIM = True
    except ImportError:
        HAS_SSIM = False
        logging.warning("SSIM not available, using basic similarity measures")


def calculate_local_variance_basic(image, window_size=5):
    """
    Calculate average local variance as noise metric using basic NumPy operations.
    Fallback when SciPy is not available.
    """
    img_array = np.array(image.convert('L')).astype(np.float32)
    height, width = img_array.shape
    
    total_variance = 0
    count = 0
    
    # Sample multiple regions across the image
    step = max(window_size, 10)
    for y in range(window_size, height - window_size, step):
        for x in range(window_size, width - window_size, step):
            # Extract local window
            window = img_array[y-window_size//2:y+window_size//2+1, 
                              x-window_size//2:x+window_size//2+1]
            
            if window.size > 0:
                local_var = np.var(window)
                total_variance += local_var
                count += 1
    
    return total_variance / count if count > 0 else 0


def calculate_local_variance_advanced(image, window_size=5):
    """
    Calculate average local variance as noise metric using SciPy for precision.
    """
    img_array = np.array(image.convert('L')).astype(np.float32)
    
    # Calculate local mean and local mean of squares using uniform filter
    local_mean = uniform_filter(img_array, size=window_size)
    local_mean_sq = uniform_filter(img_array**2, size=window_size)
    
    # Local variance = E[X²] - E[X]²
    local_variance = local_mean_sq - local_mean**2
    
    # Return average variance (noise level indicator)
    return np.mean(local_variance)


def calculate_noise_level(image):
    """Calculate noise level using the best available method."""
    if HAS_SCIPY:
        return calculate_local_variance_advanced(image)
    else:
        return calculate_local_variance_basic(image)


def check_structural_similarity(img1, img2):
    """Check structural similarity between two images."""
    if not HAS_SSIM:
        # Fallback: simple pixel-wise comparison
        if img1.size != img2.size:
            img2 = img2.resize(img1.size)
        
        if img1.mode != img2.mode:
            img2 = img2.convert(img1.mode)
            
        arr1 = np.array(img1.convert('L'))
        arr2 = np.array(img2.convert('L'))
        
        # Calculate normalized cross-correlation as similarity measure
        correlation = np.corrcoef(arr1.flatten(), arr2.flatten())[0, 1]
        return max(0, correlation)  # Ensure non-negative
    
    # Use SSIM if available
    if img1.size != img2.size:
        img2 = img2.resize(img1.size)
    
    if img1.mode != 'RGB':
        img1 = img1.convert('RGB')
    if img2.mode != 'RGB':
        img2 = img2.convert('RGB')
    
    arr1 = np.array(img1)
    arr2 = np.array(img2)
    
    # Check dimensions for SSIM
    min_dim = min(arr1.shape[0], arr1.shape[1])
    win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
    
    if win_size < 3:
        # Image too small for SSIM, use simple correlation
        return np.corrcoef(arr1.flatten(), arr2.flatten())[0, 1]
    
    try:
        # Try newer SSIM API first
        similarity = ssim(arr1, arr2, win_size=win_size, channel_axis=2)
    except TypeError:
        # Fall back to older API
        similarity = ssim(arr1, arr2, win_size=win_size, multichannel=True)
    
    return similarity


def analyze_despeckle_effectiveness(original_img, result_img):
    """
    Analyze the effectiveness of the despeckle operation.
    """
    # Calculate noise levels
    original_noise = calculate_noise_level(original_img)
    result_noise = calculate_noise_level(result_img)
    
    # Calculate noise reduction percentage
    noise_reduction_pct = ((original_noise - result_noise) / original_noise * 100) if original_noise > 0 else 0
    
    # Check structural similarity (detail preservation)
    similarity = check_structural_similarity(original_img, result_img)
    
    # Check if images are meaningfully different
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('L'))
    result_array = np.array(result_img.convert('L'))
    
    # Calculate mean absolute difference
    mean_diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
    
    return {
        'original_noise': original_noise,
        'result_noise': result_noise,
        'noise_reduction_pct': noise_reduction_pct,
        'similarity': similarity,
        'mean_difference': mean_diff,
        'images_different': mean_diff > 1.0  # At least 1 intensity unit average difference
    }


def check_despeckle(traj, env_info, task_info):
    """
    Main verifier function for despeckle task.
    Checks:
    1. Image noise was significantly reduced
    2. Image structure and details were preserved
    3. Image was meaningfully modified
    4. Changes are consistent with noise reduction (not addition)
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
        "/home/ga/Desktop/despeckled_image.jpg",
        "/home/ga/Desktop/despeckled_image.png", 
        "/home/ga/Desktop/despeckled_image.jpeg",
        "/home/ga/Desktop/noisy_image_despeckled.jpg",
        "/home/ga/Desktop/cleaned_image.jpg",
        "/home/ga/Desktop/enhanced_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/noisy_image.jpg",
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
        
        # Analyze despeckle effectiveness
        analysis = analyze_despeckle_effectiveness(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original noise level: {analysis['original_noise']:.2f}")
        feedback_parts.append(f"Result noise level: {analysis['result_noise']:.2f}")
        feedback_parts.append(f"Noise reduction: {analysis['noise_reduction_pct']:.1f}%")
        feedback_parts.append(f"Structural similarity: {analysis['similarity']:.3f}")
        feedback_parts.append(f"Mean difference: {analysis['mean_difference']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Noise reduced by at least 10%
        significant_noise_reduction = analysis['noise_reduction_pct'] >= 10.0
        if significant_noise_reduction:
            criteria_met += 1
        feedback_parts.append(f"Significant noise reduction (≥10%): {'✅' if significant_noise_reduction else '❌'}")
        
        # 2. Image was meaningfully modified
        meaningfully_changed = analysis['images_different']
        if meaningfully_changed:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if meaningfully_changed else '❌'}")
        
        # 3. Structure and details preserved (similarity ≥ 0.75)
        quality_preserved = analysis['similarity'] >= 0.75
        if quality_preserved:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved (≥0.75): {'✅' if quality_preserved else '❌'}")
        
        # 4. Noise was reduced (not increased)
        noise_direction_correct = analysis['noise_reduction_pct'] >= 0
        if noise_direction_correct:
            criteria_met += 1
        feedback_parts.append(f"Noise reduced (not increased): {'✅' if noise_direction_correct else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent noise reduction!")
        elif passed:
            feedback_parts.append("✅ Good noise reduction!")
        else:
            feedback_parts.append("❌ Despeckle filter needs better application")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in despeckle verification: {e}")
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
    result = check_despeckle([], {}, {})
    print(f"Test result: {result}")