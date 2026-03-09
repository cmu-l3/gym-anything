#!/usr/bin/env python3
"""
Verifier for GIMP newsprint halftone task.
Checks if newsprint halftone effect was successfully applied using FFT and pattern analysis.
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


def detect_halftone_pattern_fft(image):
    """
    Detect halftone screening using FFT analysis.
    Returns strength of regular frequency patterns indicating halftone dots.
    """
    try:
        # Convert to grayscale for analysis
        if image.mode != 'L':
            gray = image.convert('L')
        else:
            gray = image
        
        gray_array = np.array(gray, dtype=float)
        
        # Compute 2D FFT
        fft = np.fft.fft2(gray_array)
        fft_shift = np.fft.fftshift(fft)
        magnitude = np.abs(fft_shift)
        
        # Remove DC component (center)
        h, w = magnitude.shape
        center_h, center_w = h//2, w//2
        magnitude[center_h-5:center_h+5, center_w-5:center_w+5] = 0
        
        # Look for strong frequency peaks (halftone screens create regular peaks)
        threshold = np.percentile(magnitude, 99.5)
        peaks = magnitude > threshold
        num_peaks = np.sum(peaks)
        
        # Halftone patterns have characteristic frequency peaks
        # More peaks than natural images, less than pure noise
        peak_score = min(num_peaks / 100.0, 1.0) if 10 < num_peaks < 1000 else 0
        
        # Calculate average peak strength
        if num_peaks > 0:
            peak_strength = np.mean(magnitude[peaks]) / np.mean(magnitude)
        else:
            peak_strength = 0
        
        logging.debug(f"FFT Analysis: {num_peaks} peaks, score={peak_score:.3f}, strength={peak_strength:.3f}")
        
        return {
            'peak_score': peak_score,
            'num_peaks': num_peaks,
            'peak_strength': peak_strength,
            'fft_detected': peak_score > 0.1 and peak_strength > 1.5
        }
        
    except Exception as e:
        logging.error(f"FFT analysis failed: {e}")
        return {
            'peak_score': 0,
            'num_peaks': 0,
            'peak_strength': 0,
            'fft_detected': False
        }


def analyze_texture_increase(original_img, result_img):
    """
    Measure texture increase due to dot pattern introduction.
    Halftone should significantly increase local texture.
    """
    try:
        # Ensure same size
        if original_img.size != result_img.size:
            result_img = result_img.resize(original_img.size)
        
        # Convert to grayscale
        orig_gray = np.array(original_img.convert('L'), dtype=float)
        result_gray = np.array(result_img.convert('L'), dtype=float)
        
        # Calculate local standard deviation (texture measure)
        def local_std(img, size=5):
            from scipy import ndimage
            mean = ndimage.uniform_filter(img, size=size)
            mean_sq = ndimage.uniform_filter(img**2, size=size)
            return np.sqrt(np.maximum(mean_sq - mean**2, 0))
        
        try:
            from scipy import ndimage
            orig_texture = np.mean(local_std(orig_gray))
            result_texture = np.mean(local_std(result_gray))
        except ImportError:
            # Fallback: simple gradient-based texture measure
            orig_grad = np.sqrt(np.gradient(orig_gray, axis=0)**2 + np.gradient(orig_gray, axis=1)**2)
            result_grad = np.sqrt(np.gradient(result_gray, axis=0)**2 + np.gradient(result_gray, axis=1)**2)
            orig_texture = np.mean(orig_grad)
            result_texture = np.mean(result_grad)
        
        # Newsprint effect should significantly increase local texture
        texture_ratio = result_texture / (orig_texture + 1e-6)
        
        logging.debug(f"Texture Analysis: orig={orig_texture:.3f}, result={result_texture:.3f}, ratio={texture_ratio:.3f}")
        
        return {
            'original_texture': orig_texture,
            'result_texture': result_texture,
            'texture_ratio': texture_ratio,
            'texture_increased': texture_ratio > 1.5
        }
        
    except Exception as e:
        logging.error(f"Texture analysis failed: {e}")
        return {
            'original_texture': 0,
            'result_texture': 0,
            'texture_ratio': 0,
            'texture_increased': False
        }


def detect_pattern_regularity(image):
    """
    Detect regular dot patterns characteristic of halftoning using autocorrelation.
    """
    try:
        gray = np.array(image.convert('L'))
        
        # Use center crop for efficiency
        h, w = gray.shape
        crop = gray[h//4:3*h//4, w//4:3*w//4]
        
        # Autocorrelation using numpy correlate
        def autocorr_2d(img):
            # Flatten and normalize
            img_flat = img.flatten()
            img_norm = (img_flat - np.mean(img_flat)) / np.std(img_flat)
            
            # Compute 1D autocorrelation as approximation
            autocorr = np.correlate(img_norm, img_norm, mode='full')
            autocorr = autocorr / np.max(autocorr)
            
            # Look for peaks away from center
            center = len(autocorr) // 2
            left = autocorr[:center-50] if center > 50 else autocorr[:center//2]
            right = autocorr[center+50:] if center < len(autocorr)-50 else autocorr[center+(center//2):]
            
            if len(left) > 0 and len(right) > 0:
                return max(np.max(left), np.max(right))
            else:
                return 0
        
        peak_strength = autocorr_2d(crop)
        
        logging.debug(f"Pattern Regularity: peak_strength={peak_strength:.3f}")
        
        # Regular patterns have strong off-center autocorrelation peaks
        return {
            'peak_strength': peak_strength,
            'pattern_regular': peak_strength > 0.3
        }
        
    except Exception as e:
        logging.error(f"Pattern regularity analysis failed: {e}")
        return {
            'peak_strength': 0,
            'pattern_regular': False
        }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different (transformation occurred)."""
    try:
        # Ensure same size
        if original_img.size != result_img.size:
            result_img = result_img.resize(original_img.size)
        
        # Convert to arrays for comparison
        orig_array = np.array(original_img.convert('RGB'))
        result_array = np.array(result_img.convert('RGB'))
        
        # Calculate pixel-wise difference
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        
        # Calculate percentage of significantly changed pixels
        significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
        total_pixels = orig_array.shape[0] * orig_array.shape[1]
        change_percentage = (significant_diff / total_pixels) * 100
        
        logging.debug(f"Change Analysis: mean_diff={mean_diff:.2f}, change_pct={change_percentage:.1f}%")
        
        return {
            'mean_difference': mean_diff,
            'change_percentage': change_percentage,
            'meaningfully_changed': change_percentage > 15  # At least 15% of pixels changed significantly
        }
        
    except Exception as e:
        logging.error(f"Change analysis failed: {e}")
        return {
            'mean_difference': 0,
            'change_percentage': 0,
            'meaningfully_changed': False
        }


def check_newsprint_effect(traj, env_info, task_info):
    """
    Main verifier function for newsprint halftone task.
    Checks:
    1. FFT analysis detects regular frequency patterns (halftone screening)
    2. Texture analysis shows significant increase from dot patterns
    3. Pattern regularity analysis confirms periodic structure
    4. Meaningful change occurred (image was transformed)
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
        "/home/ga/Desktop/newsprint_image.jpg",
        "/home/ga/Desktop/newsprint_image.png",
        "/home/ga/Desktop/newsprint_image.jpeg",
        "/home/ga/Desktop/photo_image_newsprint.jpg",
        "/home/ga/Desktop/halftone_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_image.jpg",
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
        
        # Perform multiple analyses
        fft_analysis = detect_halftone_pattern_fft(result_image)
        texture_analysis = analyze_texture_increase(original_image, result_image)
        pattern_analysis = detect_pattern_regularity(result_image)
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"FFT peaks detected: {fft_analysis['num_peaks']}")
        feedback_parts.append(f"Texture ratio: {texture_analysis['texture_ratio']:.2f}")
        feedback_parts.append(f"Pattern regularity: {pattern_analysis['peak_strength']:.3f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. FFT detects halftone screening patterns
        if fft_analysis['fft_detected']:
            criteria_met += 1
        feedback_parts.append(f"FFT halftone detected: {'✅' if fft_analysis['fft_detected'] else '❌'}")
        
        # 2. Texture significantly increased
        if texture_analysis['texture_increased']:
            criteria_met += 1
        feedback_parts.append(f"Texture increased: {'✅' if texture_analysis['texture_increased'] else '❌'}")
        
        # 3. Pattern regularity detected
        if pattern_analysis['pattern_regular']:
            criteria_met += 1
        feedback_parts.append(f"Regular pattern: {'✅' if pattern_analysis['pattern_regular'] else '❌'}")
        
        # 4. Meaningful change occurred
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect newsprint halftone effect!")
        elif passed:
            feedback_parts.append("✅ Good newsprint transformation!")
        else:
            feedback_parts.append("❌ Newsprint effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in newsprint verification: {e}")
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
    result = check_newsprint_effect([], {}, {})
    print(f"Test result: {result}")