#!/usr/bin/env python3
"""
Verifier for segment_ventricles task.

VERIFICATION STRATEGY (Multi-criteria scoring):

1. Segmentation Exists (25 points)
   - A segmentation with ventricle-related name exists in Slicer scene
   
2. Measurement File Created (20 points)
   - JSON file exists at expected path with volume measurement
   - File was created during task (anti-gaming timestamp check)
   
3. Volume in Valid Range (25 points)
   - Measured volume is between 5-80 mL (anatomically plausible)
   
4. Volume in Expected Range (15 points)
   - Volume is between 15-45 mL (closer to normal values)
   
5. VLM Quality Check (15 points)
   - Trajectory frames show segmentation workflow
   - Final screenshot shows segmentation overlay

Pass threshold: 70 points with BOTH segmentation_exists AND measurement_file_created
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_segment_ventricles(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the segment_ventricles task completion.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info including copy_from_env function
        task_info: Task configuration with metadata
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    measurement_file_path = metadata.get('measurement_file', 
        '/home/ga/Documents/SlicerData/Exports/ventricle_measurement.json')
    valid_range = metadata.get('valid_volume_range_ml', {"min": 5, "max": 80})
    expected_range = metadata.get('expected_volume_range_ml', {"min": 15, "max": 45})
    weights = metadata.get('scoring_weights', {})
    
    # Scoring weights
    w_seg_exists = weights.get('segmentation_exists', 25)
    w_file_created = weights.get('measurement_file_created', 20)
    w_valid_range = weights.get('volume_in_valid_range', 25)
    w_expected_range = weights.get('volume_in_expected_range', 15)
    w_vlm = weights.get('vlm_quality_check', 15)
    
    # Initialize results
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # STEP 1: Load task result from export script
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        logger.info("Successfully loaded task result")
    except FileNotFoundError:
        feedback_parts.append("Export result not found - task may not have completed")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": {"error": "result_not_found"}
        }
    except json.JSONDecodeError as e:
        feedback_parts.append(f"Invalid JSON in result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": {"error": "json_decode_error"}
        }
    except Exception as e:
        feedback_parts.append(f"Failed to read result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result_data'] = result_data
    
    # Check if Slicer was running
    if not result_data.get('slicer_running', False):
        feedback_parts.append("Slicer was not running")
        # Don't return early - still check other criteria
    
    # ================================================================
    # CRITERION 1: Segmentation Exists (25 points)
    # ================================================================
    segmentation_exists = result_data.get('segmentation_exists', False)
    slicer_segment_name = result_data.get('slicer_segment_name', '')
    slicer_segment_voxels = result_data.get('slicer_segment_voxels', 0)
    
    if segmentation_exists:
        score += w_seg_exists
        feedback_parts.append(f"✓ Segmentation exists: '{slicer_segment_name}'")
        details['segmentation_exists'] = True
        details['segment_name'] = slicer_segment_name
        
        # Check for trivially small segmentation (anti-gaming)
        if slicer_segment_voxels > 0 and slicer_segment_voxels < 500:
            score -= 10  # Penalty for trivial segmentation
            feedback_parts.append(f"⚠ Segmentation very small ({slicer_segment_voxels} voxels)")
    else:
        feedback_parts.append("✗ No ventricle segmentation found in Slicer scene")
        details['segmentation_exists'] = False
    
    # ================================================================
    # CRITERION 2: Measurement File Created (20 points)
    # ================================================================
    measurement_exists = result_data.get('measurement_file_exists', False)
    measurement_created_during_task = result_data.get('measurement_created_during_task', False)
    
    # Also try to read the measurement file directly
    measurement_data = {}
    temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(measurement_file_path, temp_meas.name)
        with open(temp_meas.name, 'r') as f:
            measurement_data = json.load(f)
        measurement_exists = True
        logger.info(f"Read measurement file: {measurement_data}")
    except Exception as e:
        logger.info(f"Could not read measurement file: {e}")
    finally:
        if os.path.exists(temp_meas.name):
            os.unlink(temp_meas.name)
    
    if measurement_exists:
        if measurement_created_during_task:
            score += w_file_created
            feedback_parts.append("✓ Measurement file created during task")
            details['measurement_file_created'] = True
        else:
            score += w_file_created * 0.5  # Partial credit if file exists but timestamp unclear
            feedback_parts.append("△ Measurement file exists (timestamp unclear)")
            details['measurement_file_created'] = True
    else:
        feedback_parts.append("✗ Measurement file not found")
        details['measurement_file_created'] = False
    
    # ================================================================
    # CRITERION 3: Volume in Valid Range (25 points)
    # ================================================================
    # Get volume from multiple sources
    volume_ml = 0.0
    
    # Priority 1: From measurement file
    if measurement_data:
        for key in ['volume_ml', 'volume', 'Volume_ml', 'volume_mL']:
            if key in measurement_data:
                try:
                    volume_ml = float(measurement_data[key])
                    if volume_ml > 0:
                        break
                except (ValueError, TypeError):
                    pass
    
    # Priority 2: From Slicer query
    if volume_ml <= 0:
        volume_ml = float(result_data.get('slicer_segment_volume_ml', 0))
    
    # Priority 3: From reported value
    if volume_ml <= 0:
        volume_ml = float(result_data.get('reported_volume_ml', 0))
    
    details['volume_ml'] = volume_ml
    
    valid_min = valid_range.get('min', 5)
    valid_max = valid_range.get('max', 80)
    
    if valid_min <= volume_ml <= valid_max:
        score += w_valid_range
        feedback_parts.append(f"✓ Volume ({volume_ml:.1f} mL) in valid range ({valid_min}-{valid_max} mL)")
        details['volume_valid'] = True
    elif volume_ml > 0:
        feedback_parts.append(f"✗ Volume ({volume_ml:.1f} mL) outside valid range ({valid_min}-{valid_max} mL)")
        details['volume_valid'] = False
    else:
        feedback_parts.append("✗ No valid volume measurement found")
        details['volume_valid'] = False
    
    # ================================================================
    # CRITERION 4: Volume in Expected Range (15 points)
    # ================================================================
    expected_min = expected_range.get('min', 15)
    expected_max = expected_range.get('max', 45)
    
    if expected_min <= volume_ml <= expected_max:
        score += w_expected_range
        feedback_parts.append(f"✓ Volume in expected normal range ({expected_min}-{expected_max} mL)")
        details['volume_expected'] = True
    elif valid_min <= volume_ml <= valid_max:
        # Partial credit for valid but not expected range
        score += w_expected_range * 0.3
        feedback_parts.append(f"△ Volume valid but outside expected range ({expected_min}-{expected_max} mL)")
        details['volume_expected'] = False
    else:
        details['volume_expected'] = False
    
    # ================================================================
    # CRITERION 5: VLM Quality Check (15 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Try to use VLM on trajectory frames
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Import trajectory utilities if available
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Sample trajectory frames to verify workflow
                frames = sample_trajectory_frames(traj, n=4)
                final_frame = get_final_screenshot(traj)
                
                if frames or final_frame:
                    all_frames = (frames or []) + ([final_frame] if final_frame else [])
                    
                    vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to segment brain ventricles from an MRI scan.

Look for evidence of:
1. SEGMENT_EDITOR_USED: Is the Segment Editor module visible in any frame?
2. SEGMENTATION_VISIBLE: Is there a colored overlay on the brain MRI showing segmentation?
3. VENTRICLE_REGION: Does the segmentation appear to be in the central brain region (where ventricles are located)?
4. STATISTICS_VISIBLE: Is the Segment Statistics module or any measurement visible?

Respond in JSON format:
{
    "segment_editor_used": true/false,
    "segmentation_visible": true/false,
    "ventricle_region_correct": true/false,
    "statistics_visible": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        # Score based on VLM findings
                        if parsed.get('segmentation_visible'):
                            vlm_score += 8
                        if parsed.get('ventricle_region_correct'):
                            vlm_score += 4
                        if parsed.get('workflow_completed') or parsed.get('statistics_visible'):
                            vlm_score += 3
                        
                        vlm_feedback = parsed.get('observations', 'VLM analysis complete')
                    else:
                        vlm_score = 5  # Partial credit if VLM available but inconclusive
                        vlm_feedback = "VLM analysis inconclusive"
                else:
                    vlm_score = 5  # Partial credit if no frames available
                    vlm_feedback = "No trajectory frames available for VLM"
                    
            except ImportError:
                # VLM utilities not available, fall back to screenshot check
                vlm_score = verify_screenshot_quality(copy_from_env, details)
                vlm_feedback = "VLM not available, used screenshot heuristics"
        else:
            # No VLM available, use screenshot quality heuristics
            vlm_score = verify_screenshot_quality(copy_from_env, details)
            vlm_feedback = "VLM not available, used screenshot heuristics"
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_score = 5  # Partial credit
        vlm_feedback = f"VLM error: {str(e)[:50]}"
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(f"VLM: {vlm_feedback}")
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # ANTI-GAMING CHECKS
    # ================================================================
    elapsed = result_data.get('elapsed_seconds', 0)
    details['elapsed_seconds'] = elapsed
    
    if elapsed < 30 and segmentation_exists and measurement_exists:
        feedback_parts.append("⚠ Task completed suspiciously fast")
        # Could add penalty, but rely on other checks
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = min(100, max(0, int(score)))
    
    # Determine pass/fail based on key criteria
    key_criteria_met = (
        details.get('segmentation_exists', False) and
        details.get('measurement_file_created', False)
    )
    
    passed = score >= 70 and key_criteria_met
    
    details['final_score'] = score
    details['key_criteria_met'] = key_criteria_met
    details['passed'] = passed
    
    # Format feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback += f"\n\n✓ TASK PASSED (Score: {score}/100)"
    else:
        feedback += f"\n\n✗ TASK FAILED (Score: {score}/100)"
        if not details.get('segmentation_exists'):
            feedback += "\n  - Missing: Ventricle segmentation in Slicer"
        if not details.get('measurement_file_created'):
            feedback += "\n  - Missing: Measurement JSON file"
        if score < 70:
            feedback += f"\n  - Score below threshold (need 70, got {score})"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def verify_screenshot_quality(copy_from_env, details: Dict) -> int:
    """
    Fallback verification using screenshot heuristics when VLM is not available.
    
    Returns a score out of 15.
    """
    score = 0
    
    # Check final screenshot
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_final_state.png", temp_screenshot.name)
        
        # Check file size (segmentation screenshots tend to be larger due to colors)
        file_size = os.path.getsize(temp_screenshot.name)
        details['final_screenshot_size'] = file_size
        
        if file_size > 100000:  # >100KB suggests real content
            score += 5
        
        # Try to analyze with PIL if available
        try:
            from PIL import Image
            img = Image.open(temp_screenshot.name)
            
            # Count unique colors (segmentation adds colored overlays)
            if img.width * img.height > 100000:
                img_small = img.resize((200, 200))
                colors = len(set(img_small.getdata()))
            else:
                colors = len(set(img.getdata()))
            
            details['screenshot_colors'] = colors
            
            # Segmented images typically have more color variety
            if colors > 500:
                score += 5
            elif colors > 200:
                score += 3
            
            # Check for presence of specific colors (common segmentation colors)
            # Red, green, blue overlays are common
            img_rgb = img.convert('RGB')
            pixels = list(img_rgb.getdata())
            
            # Count pixels with high color saturation (not grayscale)
            colored_pixels = 0
            for r, g, b in pixels[:10000]:  # Sample first 10k pixels
                max_diff = max(abs(r-g), abs(r-b), abs(g-b))
                if max_diff > 30:  # Significant color difference
                    colored_pixels += 1
            
            color_ratio = colored_pixels / min(10000, len(pixels))
            details['colored_pixel_ratio'] = color_ratio
            
            if color_ratio > 0.05:  # >5% colored pixels
                score += 5
            elif color_ratio > 0.01:
                score += 2
                
            img.close()
            
        except ImportError:
            # PIL not available, just use file size
            if file_size > 200000:
                score += 5
                
    except Exception as e:
        logger.warning(f"Screenshot analysis failed: {e}")
        score = 3  # Minimal credit
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    
    return min(15, score)