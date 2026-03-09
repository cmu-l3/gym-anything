#!/usr/bin/env python3
"""
Verifier for Analyze Line Intensity Profile task.

VERIFICATION STRATEGY (Multi-Signal, Anti-Gaming):

Programmatic Checks (75 points):
1. Line markup exists (20 pts) - A line markup node exists in the scene
2. Line has valid endpoints (15 pts) - Line has 2 control points within brain volume
3. Line length appropriate (10 pts) - Line is 80-200mm (reasonable A-P span)
4. Output CSV exists (15 pts) - Profile data file created at specified path
5. CSV has valid data (15 pts) - File contains numeric intensity values

VLM Checks (25 points):
6. Profile shows variation (15 pts) - Intensity std dev > threshold (not fake flat data)
7. VLM confirms visualization (10 pts) - Screenshot shows line and/or profile plot

Pass threshold: 70 points with (line_markup_exists AND csv_exists) both satisfied
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_analyze_line_intensity_profile(traj, env_info, task_info):
    """
    Verify that line intensity profile was computed and saved.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - Line markup state from Slicer scene
    - CSV file timestamps (anti-gaming)
    - CSV content analysis
    - VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    line_length_range = metadata.get('line_length_range_mm', {"min": 80, "max": 200})
    min_profile_samples = metadata.get('min_profile_samples', 50)
    min_intensity_stddev = metadata.get('min_intensity_stddev', 10)
    intensity_range = metadata.get('mrhead_intensity_range', {"min": 0, "max": 1200})
    
    weights = metadata.get('scoring_weights', {})
    w_line_exists = weights.get('line_markup_exists', 20)
    w_valid_endpoints = weights.get('line_has_valid_endpoints', 15)
    w_line_length = weights.get('line_length_appropriate', 10)
    w_csv_exists = weights.get('output_csv_exists', 15)
    w_csv_valid = weights.get('csv_has_valid_data', 15)
    w_variation = weights.get('profile_shows_variation', 15)
    w_vlm = weights.get('vlm_confirms_visualization', 10)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/line_profile_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['raw_result'] = result
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer was not running")
        # Still continue to check if files were created
    
    # ================================================================
    # CRITERION 1: Line Markup Exists (20 points)
    # ================================================================
    line_exists = result.get('line_markup_exists', False)
    num_control_points = result.get('num_control_points', 0)
    
    if line_exists and num_control_points >= 2:
        score += w_line_exists
        feedback_parts.append("Line markup exists")
        details['line_markup'] = True
    elif line_exists:
        score += w_line_exists * 0.5
        feedback_parts.append(f"Line markup exists but has {num_control_points} control points")
        details['line_markup'] = "partial"
    else:
        feedback_parts.append("No line markup found")
        details['line_markup'] = False
    
    # ================================================================
    # CRITERION 2: Line Has Valid Endpoints (15 points)
    # ================================================================
    endpoints_in_bounds = result.get('endpoints_in_bounds', False)
    line_p1 = result.get('line_p1', [0, 0, 0])
    line_p2 = result.get('line_p2', [0, 0, 0])
    
    # Check that endpoints are not at origin (default/unset values)
    points_not_origin = (
        any(abs(x) > 1 for x in line_p1) and 
        any(abs(x) > 1 for x in line_p2)
    )
    
    if endpoints_in_bounds and points_not_origin:
        score += w_valid_endpoints
        feedback_parts.append("Line endpoints within brain volume")
        details['valid_endpoints'] = True
    elif points_not_origin:
        score += w_valid_endpoints * 0.6
        feedback_parts.append("Line endpoints placed (bounds check uncertain)")
        details['valid_endpoints'] = "uncertain"
    else:
        feedback_parts.append("Line endpoints not valid or not placed")
        details['valid_endpoints'] = False
    
    # ================================================================
    # CRITERION 3: Line Length Appropriate (10 points)
    # ================================================================
    line_length = result.get('line_length_mm', 0)
    min_len = line_length_range.get('min', 80)
    max_len = line_length_range.get('max', 200)
    
    if min_len <= line_length <= max_len:
        score += w_line_length
        feedback_parts.append(f"Line length OK ({line_length:.1f}mm)")
        details['line_length_ok'] = True
    elif line_length > 0:
        # Partial credit for any reasonable line
        if 50 <= line_length <= 250:
            score += w_line_length * 0.5
            feedback_parts.append(f"Line length acceptable ({line_length:.1f}mm)")
        else:
            feedback_parts.append(f"Line length out of range ({line_length:.1f}mm)")
        details['line_length_ok'] = "marginal"
    else:
        feedback_parts.append("No valid line length")
        details['line_length_ok'] = False
    
    details['line_length_mm'] = line_length
    
    # ================================================================
    # CRITERION 4: Output CSV Exists (15 points)
    # ================================================================
    csv_exists = result.get('csv_exists', False)
    csv_created_during_task = result.get('csv_created_during_task', False)
    csv_size = result.get('csv_size_bytes', 0)
    
    if csv_exists and csv_created_during_task:
        score += w_csv_exists
        feedback_parts.append(f"CSV file created ({csv_size} bytes)")
        details['csv_exists'] = True
        details['csv_created_during_task'] = True
    elif csv_exists:
        # File exists but wasn't created during task - suspicious
        score += w_csv_exists * 0.3
        feedback_parts.append("CSV exists but may predate task")
        details['csv_exists'] = True
        details['csv_created_during_task'] = False
    else:
        feedback_parts.append("Output CSV not found")
        details['csv_exists'] = False
    
    # ================================================================
    # CRITERION 5: CSV Has Valid Data (15 points)
    # ================================================================
    csv_valid = result.get('csv_valid_data', False)
    csv_num_rows = result.get('csv_num_rows', 0)
    csv_has_intensity = result.get('csv_has_intensity_col', False) or csv_num_rows > 0
    
    if csv_valid and csv_num_rows >= min_profile_samples:
        score += w_csv_valid
        feedback_parts.append(f"CSV has valid data ({csv_num_rows} samples)")
        details['csv_valid'] = True
    elif csv_num_rows > 10:
        score += w_csv_valid * 0.6
        feedback_parts.append(f"CSV has data but fewer samples ({csv_num_rows})")
        details['csv_valid'] = "partial"
    elif csv_exists:
        feedback_parts.append("CSV exists but lacks valid intensity data")
        details['csv_valid'] = False
    
    details['csv_num_rows'] = csv_num_rows
    
    # ================================================================
    # CRITERION 6: Profile Shows Variation (15 points)
    # Anti-gaming: flat/constant data indicates fake file
    # ================================================================
    intensity_stddev = result.get('csv_intensity_stddev', 0)
    intensity_min = result.get('csv_intensity_min', 0)
    intensity_max = result.get('csv_intensity_max', 0)
    intensity_mean = result.get('csv_intensity_mean', 0)
    
    # Check for realistic intensity variation
    has_variation = intensity_stddev > min_intensity_stddev
    intensity_range_valid = (
        intensity_range['min'] <= intensity_min and
        intensity_max <= intensity_range['max']
    )
    
    if has_variation and intensity_range_valid:
        score += w_variation
        feedback_parts.append(f"Profile shows tissue variation (std={intensity_stddev:.1f})")
        details['variation_ok'] = True
    elif has_variation:
        score += w_variation * 0.7
        feedback_parts.append(f"Profile has variation but unusual range")
        details['variation_ok'] = "unusual_range"
    elif csv_num_rows > 0:
        # Suspiciously flat data
        feedback_parts.append(f"Profile is suspiciously flat (std={intensity_stddev:.1f})")
        details['variation_ok'] = False
    
    details['intensity_stats'] = {
        'min': intensity_min,
        'max': intensity_max,
        'mean': intensity_mean,
        'stddev': intensity_stddev
    }
    
    # ================================================================
    # CRITERION 7: VLM Confirms Visualization (10 points)
    # Use TRAJECTORY frames, not just final screenshot
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    
    vlm_score = 0
    vlm_feedback = "VLM verification skipped"
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames for process verification
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if final:
                frames.append(final)
            
            if frames:
                vlm_prompt = """You are verifying a medical imaging task in 3D Slicer.

The agent was asked to:
1. Place a line markup through a brain MRI (from frontal to occipital)
2. Use the Line Profile module to compute intensity values
3. Export the profile to a CSV file

Look at these screenshots and assess:
1. Is there a LINE visible in any slice view (a ruler/line drawn through the brain)?
2. Is the Line Profile module or a plot/chart window visible?
3. Does any screenshot show what appears to be an intensity profile plot?

Respond in JSON format:
{
    "line_visible_in_slices": true/false,
    "line_profile_module_visible": true/false,
    "intensity_plot_visible": true/false,
    "brain_mri_loaded": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    line_visible = parsed.get('line_visible_in_slices', False)
                    profile_visible = parsed.get('intensity_plot_visible', False)
                    module_visible = parsed.get('line_profile_module_visible', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score VLM verification
                    if (line_visible or profile_visible) and confidence in ['medium', 'high']:
                        vlm_score = w_vlm
                        vlm_feedback = "VLM confirms line/profile visible"
                    elif line_visible or profile_visible or module_visible:
                        vlm_score = w_vlm * 0.6
                        vlm_feedback = "VLM partially confirms task"
                    else:
                        vlm_feedback = "VLM could not confirm visualization"
                else:
                    vlm_feedback = f"VLM query failed: {vlm_result.get('error', 'unknown')}"
        except ImportError:
            vlm_feedback = "VLM utilities not available"
        except Exception as e:
            vlm_feedback = f"VLM error: {str(e)}"
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    
    # Key criteria for pass
    key_criteria_met = (
        result.get('line_markup_exists', False) and
        result.get('csv_exists', False)
    )
    
    # Pass threshold: 70 points AND key criteria
    passed = score >= 70 and key_criteria_met
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }