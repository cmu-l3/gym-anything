#!/usr/bin/env python3
"""
Verifier for Evans Index Calculation task.

VERIFICATION STRATEGY:
Uses multi-criteria scoring with both programmatic checks and VLM verification.

Programmatic checks (from export JSON via copy_from_env):
1. Two line markups exist (25 pts) - verifies measurements were created
2. Same slice level (20 pts) - both measurements at same Z coordinate
3. Measurements horizontal (15 pts) - lines are oriented correctly
4. Valid ratio range (20 pts) - Evans Index is physiologically plausible

VLM verification (using trajectory frames):
5. Anatomically correct placement (15 pts) - confirms measurements at frontal horn level

Additional check:
6. Measurements exported (5 pts) - data saved for record keeping

Pass threshold: 70 points with two_lines_exist AND same_level satisfied
"""

import json
import os
import tempfile
import logging
import math
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_evans_index(traj, env_info, task_info):
    """
    Verify the Evans Index calculation task.
    
    Uses copy_from_env to get result files from container.
    Uses trajectory frames for VLM verification.
    
    Returns:
        dict with 'passed' (bool), 'score' (float 0-1), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get scoring weights from metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    w_two_lines = weights.get('two_line_markups_exist', 25)
    w_same_level = weights.get('same_slice_level', 20)
    w_horizontal = weights.get('measurements_horizontal', 15)
    w_valid_ratio = weights.get('valid_ratio_range', 20)
    w_vlm_correct = weights.get('vlm_anatomically_correct', 15)
    w_exported = weights.get('measurements_exported', 5)
    
    expected_evans_range = metadata.get('expected_evans_index_range', {"min": 0.15, "max": 0.50})
    z_tolerance = metadata.get('z_tolerance_mm', 5.0)
    angle_tolerance = metadata.get('horizontal_angle_tolerance_deg', 15)
    
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/evans_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info("Successfully loaded result JSON from container")
    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Also try to get detailed measurements
    temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    measurements_data = {}
    try:
        copy_from_env("/tmp/evans_measurements.json", temp_meas.name)
        with open(temp_meas.name, 'r') as f:
            measurements_data = json.load(f)
    except Exception:
        logger.info("Could not load detailed measurements - using result file")
    finally:
        if os.path.exists(temp_meas.name):
            os.unlink(temp_meas.name)
    
    # ================================================================
    # CHECK: Slicer was running
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # CRITERION 1: Two Line Markups Exist (25 points)
    # ================================================================
    line_count = result.get('line_count', 0)
    details['line_count'] = line_count
    
    if line_count >= 2:
        score += w_two_lines
        feedback_parts.append(f"✓ Found {line_count} line measurements ({w_two_lines} pts)")
    elif line_count == 1:
        partial = int(w_two_lines * 0.4)
        score += partial
        feedback_parts.append(f"✗ Only 1 line measurement found (need 2) ({partial} pts)")
    else:
        feedback_parts.append(f"✗ No line measurements found (0 pts)")
    
    # ================================================================
    # CRITERION 2: Same Slice Level (20 points)
    # ================================================================
    same_level = result.get('same_level', False)
    z_diff = result.get('z_difference_mm')
    details['same_level'] = same_level
    details['z_difference_mm'] = z_diff
    
    if same_level:
        score += w_same_level
        feedback_parts.append(f"✓ Both measurements at same level (Z diff: {z_diff}mm) ({w_same_level} pts)")
    elif z_diff is not None:
        if z_diff < z_tolerance * 2:
            partial = int(w_same_level * 0.5)
            score += partial
            feedback_parts.append(f"✗ Measurements close but not same level (Z diff: {z_diff}mm) ({partial} pts)")
        else:
            feedback_parts.append(f"✗ Measurements at different levels (Z diff: {z_diff}mm) (0 pts)")
    elif line_count < 2:
        feedback_parts.append("✗ Cannot check slice level - insufficient measurements (0 pts)")
    else:
        feedback_parts.append("✗ Could not verify slice level consistency (0 pts)")
    
    # ================================================================
    # CRITERION 3: Measurements Horizontal (15 points)
    # ================================================================
    lines_horizontal = False
    lines_info = measurements_data.get('lines', [])
    
    if lines_info and len(lines_info) >= 2:
        horizontal_count = sum(1 for line in lines_info if line.get('is_horizontal', False))
        details['horizontal_line_count'] = horizontal_count
        
        if horizontal_count >= 2:
            score += w_horizontal
            lines_horizontal = True
            feedback_parts.append(f"✓ Both measurements are horizontal ({w_horizontal} pts)")
        elif horizontal_count == 1:
            partial = int(w_horizontal * 0.5)
            score += partial
            feedback_parts.append(f"✗ Only 1 measurement is horizontal ({partial} pts)")
        else:
            angles = [line.get('angle_from_horizontal_deg', 90) for line in lines_info]
            feedback_parts.append(f"✗ Measurements not horizontal (angles: {angles}) (0 pts)")
    elif line_count >= 2:
        # No detailed line info but we have 2 lines - give partial credit
        partial = int(w_horizontal * 0.3)
        score += partial
        feedback_parts.append(f"? Could not verify orientation ({partial} pts)")
    else:
        feedback_parts.append("✗ Insufficient measurements to check orientation (0 pts)")
    
    details['lines_horizontal'] = lines_horizontal
    
    # ================================================================
    # CRITERION 4: Valid Ratio Range (20 points)
    # ================================================================
    evans_index = result.get('evans_index')
    valid_ratio = False
    
    if evans_index is not None:
        details['evans_index'] = evans_index
        details['frontal_horn_width_mm'] = result.get('frontal_horn_width_mm')
        details['skull_width_mm'] = result.get('skull_width_mm')
        details['interpretation'] = result.get('interpretation')
        
        min_valid = expected_evans_range.get('min', 0.15)
        max_valid = expected_evans_range.get('max', 0.50)
        
        if min_valid <= evans_index <= max_valid:
            score += w_valid_ratio
            valid_ratio = True
            feedback_parts.append(f"✓ Evans Index {evans_index:.3f} in valid range ({w_valid_ratio} pts)")
        elif 0.10 <= evans_index <= 0.60:
            # Borderline - physiologically possible but unusual
            partial = int(w_valid_ratio * 0.5)
            score += partial
            feedback_parts.append(f"✗ Evans Index {evans_index:.3f} is borderline plausible ({partial} pts)")
        else:
            feedback_parts.append(f"✗ Evans Index {evans_index:.3f} outside physiological range (0 pts)")
    elif line_count >= 2:
        feedback_parts.append("✗ Could not calculate Evans Index from measurements (0 pts)")
    else:
        feedback_parts.append("✗ Evans Index cannot be calculated - insufficient measurements (0 pts)")
    
    details['valid_ratio'] = valid_ratio
    
    # ================================================================
    # CRITERION 5: VLM Visual Verification (15 points)
    # Uses TRAJECTORY frames, not just final screenshot
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    vlm_query = env_info.get('vlm_query')
    
    if vlm_query and traj:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory (shows progression of work)
            trajectory_frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            all_frames = []
            if trajectory_frames:
                all_frames.extend(trajectory_frames)
            if final_frame:
                all_frames.append(final_frame)
            
            if all_frames:
                vlm_prompt = """Analyze these screenshots from a 3D Slicer brain MRI measurement task.

The agent was asked to calculate the Evans Index by measuring:
1. Maximum width of the frontal horns of the lateral ventricles
2. Maximum internal skull diameter at the same axial level

Check for the following in the screenshots:
1. Is an axial (horizontal cross-section) brain MRI slice visible?
2. Are there horizontal line measurements drawn on the image?
3. Does one line appear to span the frontal horns (bright fluid-filled spaces in the anterior/front part of the brain)?
4. Does another line appear to span the full width of the skull?
5. Are the measurements at an appropriate anatomical level (mid-brain level where frontal horns are visible)?

Respond in JSON format:
{
    "axial_brain_slice_visible": true/false,
    "line_measurements_visible": true/false,
    "frontal_horn_measurement_placed": true/false,
    "skull_width_measurement_placed": true/false,
    "correct_anatomical_level": true/false,
    "confidence": "high"/"medium"/"low",
    "observations": "brief description of what you see"
}"""
                
                vlm_response = vlm_query(images=all_frames, prompt=vlm_prompt)
                
                if vlm_response and vlm_response.get('success'):
                    vlm_result = vlm_response.get('parsed', {})
                    
                    if not vlm_result:
                        # Try to parse from raw text
                        raw = vlm_response.get('raw', '')
                        json_match = re.search(r'\{[^}]+\}', raw, re.DOTALL)
                        if json_match:
                            try:
                                vlm_result = json.loads(json_match.group())
                            except:
                                pass
                    
                    if vlm_result:
                        checks_passed = 0
                        if vlm_result.get('axial_brain_slice_visible'):
                            checks_passed += 1
                        if vlm_result.get('line_measurements_visible'):
                            checks_passed += 1
                        if vlm_result.get('frontal_horn_measurement_placed'):
                            checks_passed += 1
                        if vlm_result.get('skull_width_measurement_placed'):
                            checks_passed += 1
                        if vlm_result.get('correct_anatomical_level'):
                            checks_passed += 1
                        
                        details['vlm_checks_passed'] = checks_passed
                        details['vlm_result'] = vlm_result
                        
                        if checks_passed >= 4:
                            vlm_score = w_vlm_correct
                            vlm_feedback = "VLM confirms correct measurement placement"
                        elif checks_passed >= 3:
                            vlm_score = int(w_vlm_correct * 0.7)
                            vlm_feedback = f"VLM partially confirms ({checks_passed}/5 checks)"
                        elif checks_passed >= 2:
                            vlm_score = int(w_vlm_correct * 0.4)
                            vlm_feedback = f"VLM found some elements ({checks_passed}/5 checks)"
                        else:
                            vlm_feedback = "VLM could not confirm correct measurements"
                    else:
                        vlm_feedback = "Could not parse VLM response"
                else:
                    vlm_feedback = f"VLM query unsuccessful: {vlm_response.get('error', 'unknown')}"
            else:
                vlm_feedback = "No trajectory frames available"
                
        except ImportError:
            vlm_feedback = "VLM utilities not available"
        except Exception as e:
            vlm_feedback = f"VLM verification error: {str(e)}"
            logger.exception("VLM verification failed")
    else:
        vlm_feedback = "VLM verification skipped (no query function or trajectory)"
    
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"✓ {vlm_feedback} ({vlm_score} pts)")
    else:
        feedback_parts.append(f"✗ {vlm_feedback} (0 pts)")
    
    # ================================================================
    # CRITERION 6: Measurements Exported (5 points)
    # ================================================================
    measurements_exported = result.get('measurements_exported', False)
    
    if measurements_exported:
        score += w_exported
        feedback_parts.append(f"✓ Measurements exported to file ({w_exported} pts)")
    else:
        feedback_parts.append(f"✗ Measurements not exported (0 pts)")
    
    details['measurements_exported'] = measurements_exported
    
    # ================================================================
    # ANTI-GAMING CHECK: Verify task was actually performed
    # ================================================================
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    task_duration = task_end - task_start if task_end > task_start else 0
    details['task_duration_sec'] = task_duration
    
    # If task completed in < 10 seconds with perfect score, suspicious
    if task_duration < 10 and score > 80:
        score = int(score * 0.5)
        feedback_parts.append("⚠ Suspicious: Task completed too quickly - score reduced")
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    normalized_score = min(score / max_score, 1.0)
    
    # Pass criteria: 70+ points AND two_lines_exist AND same_level
    two_lines_exist = line_count >= 2
    passed = (score >= 70 and two_lines_exist and same_level)
    
    # Build final feedback
    feedback_str = "\n".join(feedback_parts)
    feedback_str += f"\n\nTotal Score: {score}/{max_score}"
    
    if evans_index is not None:
        feedback_str += f"\n\nEvans Index: {evans_index:.4f}"
        interpretation = result.get('interpretation', '')
        if interpretation:
            feedback_str += f"\nClinical Interpretation: {interpretation}"
    
    if passed:
        feedback_str += "\n\n✓ TASK PASSED"
    else:
        reasons = []
        if not two_lines_exist:
            reasons.append("need at least 2 line measurements")
        if not same_level:
            reasons.append("measurements must be at same slice level")
        if score < 70:
            reasons.append(f"score {score} below threshold of 70")
        
        feedback_str += f"\n\n✗ TASK FAILED: {'; '.join(reasons)}"
    
    return {
        "passed": passed,
        "score": normalized_score,
        "feedback": feedback_str,
        "details": details
    }


if __name__ == "__main__":
    # Test run without container
    print("Evans Index Verifier - Test Mode")
    print("This verifier requires container environment to run properly.")
    
    # Mock test
    mock_result = {
        "passed": False,
        "score": 0.0,
        "feedback": "Test mode - no container available"
    }
    print(json.dumps(mock_result, indent=2))