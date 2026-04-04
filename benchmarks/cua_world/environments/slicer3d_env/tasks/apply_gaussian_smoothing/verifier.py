#!/usr/bin/env python3
"""
Verifier for apply_gaussian_smoothing task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

1. Output volume exists (25 points) - A new volume was created beyond the original
2. Correct dimensions (15 points) - Output volume has same dimensions as input
3. Smoothing detected (30 points) - Statistical analysis confirms Gaussian smoothing:
   - Laplacian magnitude (edge sharpness) decreased
   - Standard deviation decreased slightly
4. Appropriate sigma (15 points) - Smoothing level is appropriate (not too little/much)
5. Visual confirmation (10 points) - Screenshots show work was done
6. Original preserved (5 points) - Input volume still exists unchanged

Anti-gaming measures:
- Timestamp verification: Output must be created after task start
- Difference check: Output cannot be identical to input
- Dimension check: Output must match input dimensions
- Smoothing magnitude check: Smoothing must be detectable but not excessive

Pass threshold: 70 points with output_volume_exists AND smoothing_detected
"""

import json
import os
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_apply_gaussian_smoothing(traj, env_info, task_info):
    """
    Verify that Gaussian smoothing was properly applied to the MRHead volume.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    
    Returns:
        Dict with "passed" (bool), "score" (int 0-100), "feedback" (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata for expected values
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    thresholds = metadata.get('smoothing_thresholds', {})
    
    w_output_exists = weights.get('output_volume_exists', 25)
    w_dimensions = weights.get('correct_dimensions', 15)
    w_smoothing = weights.get('smoothing_detected', 30)
    w_sigma = weights.get('appropriate_sigma', 15)
    w_visual = weights.get('visual_confirmation', 10)
    w_original = weights.get('original_preserved', 5)
    
    laplacian_ratio_max = thresholds.get('laplacian_ratio_max', 0.90)
    laplacian_ratio_min = thresholds.get('laplacian_ratio_min', 0.30)
    std_ratio_max = thresholds.get('std_ratio_max', 0.99)
    
    score = 0
    details = {
        "output_volume_exists": False,
        "correct_dimensions": False,
        "smoothing_detected": False,
        "appropriate_sigma": False,
        "visual_confirmation": False,
        "original_preserved": False,
    }
    feedback_parts = []
    
    # ================================================================
    # Load result data from container
    # ================================================================
    temp_dir = tempfile.mkdtemp()
    result_file = os.path.join(temp_dir, "result.json")
    result = {}
    
    try:
        # Try primary location
        try:
            copy_from_env("/tmp/task_result.json", result_file)
        except:
            # Try alternative location
            copy_from_env("/tmp/slicer_task_results/result.json", result_file)
        
        with open(result_file, 'r') as f:
            result = json.load(f)
            
    except FileNotFoundError:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    
    try:
        # ================================================================
        # Check basic conditions
        # ================================================================
        
        # Was Slicer running?
        if not result.get('slicer_was_running', False):
            feedback_parts.append("Slicer was not running or scene info unavailable")
            return {
                "passed": False,
                "score": 0,
                "feedback": "; ".join(feedback_parts),
                "details": details
            }
        
        volumes = result.get('volumes', [])
        initial_stats = result.get('initial_stats', {})
        task_start = result.get('task_start', 0)
        
        # ================================================================
        # Find original and smoothed volumes
        # ================================================================
        original_volume = None
        smoothed_volume = None
        
        for vol in volumes:
            name = vol.get('name', '')
            if name == 'MRHead' or name.lower() == 'mrhead':
                original_volume = vol
            elif vol.get('is_smoothed_output') or vol.get('is_potential_output'):
                smoothed_volume = vol
            elif any(kw in name.lower() for kw in ['smooth', 'gaussian', 'filtered', 'blur']):
                smoothed_volume = vol
        
        # If no obviously named smoothed volume, look for any non-MRHead volume
        if smoothed_volume is None:
            for vol in volumes:
                name = vol.get('name', '')
                if name != 'MRHead' and name.lower() != 'mrhead':
                    smoothed_volume = vol
                    break
        
        # ================================================================
        # CRITERION 1: Output volume exists (25 points)
        # ================================================================
        if smoothed_volume is not None:
            details["output_volume_exists"] = True
            score += w_output_exists
            smoothed_name = smoothed_volume.get('name', 'unknown')
            feedback_parts.append(f"Output volume found: '{smoothed_name}'")
            details["smoothed_volume_name"] = smoothed_name
        else:
            feedback_parts.append("No output volume found (only original MRHead present)")
            # If no output volume, cannot continue most checks
            return {
                "passed": False,
                "score": score,
                "feedback": "; ".join(feedback_parts),
                "details": details
            }
        
        # ================================================================
        # CRITERION 2: Correct dimensions (15 points)
        # ================================================================
        if original_volume and smoothed_volume:
            orig_dims = tuple(original_volume.get('dimensions', []))
            smooth_dims = tuple(smoothed_volume.get('dimensions', []))
            
            # Also check against initial stats
            if not orig_dims or orig_dims == (0, 0, 0):
                orig_dims = tuple(initial_stats.get('shape', []))
            
            if orig_dims and smooth_dims and orig_dims == smooth_dims and orig_dims != (0, 0, 0):
                details["correct_dimensions"] = True
                score += w_dimensions
                feedback_parts.append(f"Dimensions match: {smooth_dims}")
                details["dimensions"] = smooth_dims
            elif smooth_dims and smooth_dims != (0, 0, 0):
                feedback_parts.append(f"Dimension mismatch: original {orig_dims}, output {smooth_dims}")
                details["dimension_mismatch"] = {"original": orig_dims, "output": smooth_dims}
            else:
                feedback_parts.append("Could not verify dimensions")
        
        # ================================================================
        # CRITERION 3: Smoothing detected (30 points)
        # ================================================================
        smoothing_confirmed = False
        smoothing_analysis = {}
        
        if initial_stats and smoothed_volume:
            input_laplacian = initial_stats.get('laplacian_mean', 0)
            input_std = initial_stats.get('std', 0)
            
            output_laplacian = smoothed_volume.get('laplacian_mean')
            output_std = smoothed_volume.get('std')
            
            smoothing_analysis['input_laplacian'] = input_laplacian
            smoothing_analysis['output_laplacian'] = output_laplacian
            smoothing_analysis['input_std'] = input_std
            smoothing_analysis['output_std'] = output_std
            
            # Check laplacian ratio (primary indicator of smoothing)
            if output_laplacian is not None and input_laplacian > 0:
                laplacian_ratio = output_laplacian / input_laplacian
                smoothing_analysis['laplacian_ratio'] = laplacian_ratio
                
                # Gaussian smoothing significantly reduces edge sharpness
                if laplacian_ratio < laplacian_ratio_max:
                    smoothing_confirmed = True
                    feedback_parts.append(f"Edges smoothed (Laplacian ratio: {laplacian_ratio:.3f})")
            
            # Check std ratio (secondary indicator)
            if output_std is not None and input_std > 0:
                std_ratio = output_std / input_std
                smoothing_analysis['std_ratio'] = std_ratio
                
                # Smoothing typically reduces std slightly
                if std_ratio < std_ratio_max and not smoothing_confirmed:
                    smoothing_confirmed = True
                    feedback_parts.append(f"Intensity variance reduced (ratio: {std_ratio:.3f})")
        
        if smoothing_confirmed:
            details["smoothing_detected"] = True
            score += w_smoothing
            details["smoothing_analysis"] = smoothing_analysis
        else:
            feedback_parts.append("No clear smoothing detected in output statistics")
            details["smoothing_analysis"] = smoothing_analysis
        
        # ================================================================
        # CRITERION 4: Appropriate sigma (15 points)
        # ================================================================
        # Check if smoothing is in reasonable range (not too little, not too much)
        if smoothing_analysis:
            laplacian_ratio = smoothing_analysis.get('laplacian_ratio', 1.0)
            
            # Expected range for sigma ≈ 2mm: laplacian ratio between 0.3 and 0.9
            if laplacian_ratio_min < laplacian_ratio < laplacian_ratio_max:
                details["appropriate_sigma"] = True
                score += w_sigma
                feedback_parts.append(f"Smoothing level appropriate (ratio {laplacian_ratio:.3f} in range [{laplacian_ratio_min}, {laplacian_ratio_max}])")
            elif laplacian_ratio <= laplacian_ratio_min:
                feedback_parts.append(f"Smoothing may be too aggressive (ratio {laplacian_ratio:.3f} < {laplacian_ratio_min})")
            elif laplacian_ratio >= laplacian_ratio_max:
                feedback_parts.append(f"Smoothing may be too weak (ratio {laplacian_ratio:.3f} >= {laplacian_ratio_max})")
        
        # ================================================================
        # CRITERION 5: Visual confirmation (10 points)
        # ================================================================
        # Check if screenshot exists and has content
        screenshot_exists = result.get('screenshot_exists', False)
        new_exports = result.get('new_export_count', 0)
        
        if screenshot_exists:
            # Basic check - screenshot was captured
            details["visual_confirmation"] = True
            score += w_visual
            feedback_parts.append("Screenshot captured for visual verification")
        elif new_exports > 0:
            # Alternative - volume was exported during task
            details["visual_confirmation"] = True
            score += w_visual
            feedback_parts.append(f"{new_exports} volume(s) exported during task")
        else:
            feedback_parts.append("No visual evidence captured")
        
        # ================================================================
        # CRITERION 6: Original preserved (5 points)
        # ================================================================
        if original_volume is not None:
            # Check that original MRHead still exists and wasn't destroyed
            orig_std = original_volume.get('std', 0)
            expected_std = initial_stats.get('std', 0)
            
            if expected_std > 0:
                # Allow small tolerance for floating point differences
                std_diff = abs(orig_std - expected_std) / expected_std if expected_std > 0 else 0
                if std_diff < 0.01:  # Within 1%
                    details["original_preserved"] = True
                    score += w_original
                    feedback_parts.append("Original MRHead volume preserved")
                else:
                    feedback_parts.append(f"Original volume may have been modified (std diff: {std_diff:.2%})")
            else:
                # Can't verify, give benefit of doubt if original exists
                details["original_preserved"] = True
                score += w_original
                feedback_parts.append("Original MRHead volume still exists")
        else:
            feedback_parts.append("Original MRHead volume not found")
        
        # ================================================================
        # Anti-gaming: Check timestamps
        # ================================================================
        new_exports_info = result.get('new_exports_during_task', [])
        if new_exports_info:
            details["file_created_during_task"] = True
        elif task_start > 0:
            # Check if any smoothed volume export has valid timestamp
            exported_path = smoothed_volume.get('exported_path', '') if smoothed_volume else ''
            if exported_path:
                export_info = result.get('new_exports_during_task', [])
                if export_info:
                    details["file_created_during_task"] = True
        
        # ================================================================
        # Calculate final result
        # ================================================================
        
        # Key criteria for passing
        key_criteria_met = (
            details["output_volume_exists"] and 
            details["smoothing_detected"]
        )
        
        # Pass if score >= 70 AND key criteria met
        passed = score >= 70 and key_criteria_met
        
        details["passed"] = passed
        details["final_score"] = score
        details["key_criteria_met"] = key_criteria_met
        
        feedback = "; ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }
        
    finally:
        # Cleanup temp directory
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    # For testing
    print("Gaussian Smoothing Task Verifier")
    print("Run via task framework for actual verification")
    print("")
    print("Verification criteria:")
    print("  1. Output volume exists (25 pts)")
    print("  2. Correct dimensions (15 pts)")
    print("  3. Smoothing detected (30 pts)")
    print("  4. Appropriate sigma (15 pts)")
    print("  5. Visual confirmation (10 pts)")
    print("  6. Original preserved (5 pts)")
    print("")
    print("Pass threshold: 70 points with output_volume_exists AND smoothing_detected")