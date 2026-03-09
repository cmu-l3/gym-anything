#!/usr/bin/env python3
"""
Verifier for GIMP color balance task.
Checks if color cast was corrected using RGB channel analysis.
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


def analyze_color_cast(image):
    """Analyze RGB channel means to detect color cast."""
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    img_array = np.array(image)
    r_mean = np.mean(img_array[:, :, 0])
    g_mean = np.mean(img_array[:, :, 1])
    b_mean = np.mean(img_array[:, :, 2])
    
    # Calculate cast indicators
    warmth = (r_mean + g_mean) / 2 - b_mean  # Positive = warm cast
    redness = r_mean - (g_mean + b_mean) / 2
    yellowness = (r_mean + g_mean) / 2 - b_mean
    
    return {
        'r_mean': r_mean,
        'g_mean': g_mean,
        'b_mean': b_mean,
        'warmth': warmth,
        'redness': redness,
        'yellowness': yellowness
    }


def verify_color_balance_correction(orig_stats, result_stats):
    """Verify that color balance correction moved in correct direction."""
    
    # Calculate cast reduction
    orig_warmth = orig_stats['warmth']
    result_warmth = result_stats['warmth']
    
    if orig_warmth > 0:  # Only calculate reduction if there was a warm cast
        cast_reduction = (orig_warmth - result_warmth) / orig_warmth * 100
    else:
        cast_reduction = 0
    
    # Calculate RGB channel balance improvement
    orig_variance = np.var([orig_stats['r_mean'], orig_stats['g_mean'], orig_stats['b_mean']])
    result_variance = np.var([result_stats['r_mean'], result_stats['g_mean'], result_stats['b_mean']])
    
    if orig_variance > 0:
        balance_improvement = (orig_variance - result_variance) / orig_variance * 100
    else:
        balance_improvement = 0
    
    # Check for proper correction direction (blue increased, red/yellow reduced for warm cast)
    blue_increased = result_stats['b_mean'] > orig_stats['b_mean']
    red_yellow_reduced = (result_stats['r_mean'] + result_stats['g_mean']) < (orig_stats['r_mean'] + orig_stats['g_mean'])
    
    return {
        'cast_reduction_pct': cast_reduction,
        'balance_improvement_pct': balance_improvement,
        'correct_direction': blue_increased and red_yellow_reduced,
        'blue_change': result_stats['b_mean'] - orig_stats['b_mean'],
        'warmth_change': orig_warmth - result_warmth
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed significantly
    }


def check_color_balance(traj, env_info, task_info):
    """
    Main verifier function for color balance task.
    Checks:
    1. Color cast was reduced (warm cast moved toward neutral)
    2. RGB channel balance improved
    3. Correction moved in the right direction
    4. Image was meaningfully modified
    5. No overcorrection occurred
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
        "/home/ga/Desktop/color_balanced.jpg",
        "/home/ga/Desktop/color_balanced.png",
        "/home/ga/Desktop/color_balanced.jpeg",
        "/home/ga/Desktop/warm_landscape_balanced.jpg",
        "/home/ga/Desktop/landscape_corrected.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/warm_landscape.jpg",
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
        
        # Analyze color cast in both images
        original_stats = analyze_color_cast(original_image)
        result_stats = analyze_color_cast(result_image)
        
        # Check color balance correction
        correction_analysis = verify_color_balance_correction(original_stats, result_stats)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original warmth: {original_stats['warmth']:.1f}")
        feedback_parts.append(f"Result warmth: {result_stats['warmth']:.1f}")
        feedback_parts.append(f"Warmth reduction: {correction_analysis['warmth_change']:.1f}")
        feedback_parts.append(f"Blue channel change: {correction_analysis['blue_change']:.1f}")
        feedback_parts.append(f"Balance improvement: {correction_analysis['balance_improvement_pct']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Color cast reduced (warmth decreased by at least 30% or by at least 10 units)
        cast_reduction_significant = (correction_analysis['cast_reduction_pct'] >= 30 or 
                                    correction_analysis['warmth_change'] >= 10)
        if cast_reduction_significant:
            criteria_met += 1
        feedback_parts.append(f"Color cast reduced: {'✅' if cast_reduction_significant else '❌'}")
        
        # 2. RGB balance improved (variance decreased)
        balance_improved = correction_analysis['balance_improvement_pct'] > 0
        if balance_improved:
            criteria_met += 1
        feedback_parts.append(f"RGB balance improved: {'✅' if balance_improved else '❌'}")
        
        # 3. Correct direction (blue increased, red/yellow decreased for warm cast)
        if correction_analysis['correct_direction']:
            criteria_met += 1
        feedback_parts.append(f"Correct direction: {'✅' if correction_analysis['correct_direction'] else '❌'}")
        
        # 4. No overcorrection (result shouldn't have opposite strong cast)
        no_overcorrection = abs(result_stats['warmth']) <= abs(original_stats['warmth']) + 5
        if no_overcorrection:
            criteria_met += 1
        feedback_parts.append(f"No overcorrection: {'✅' if no_overcorrection else '❌'}")
        
        # 5. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (but round up 3/5 to pass threshold)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent color balance correction!")
        elif passed:
            feedback_parts.append("✅ Good color balance correction!")
        else:
            feedback_parts.append("❌ Color balance correction needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color balance verification: {e}")
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
    result = check_color_balance([], {}, {})
    print(f"Test result: {result}")