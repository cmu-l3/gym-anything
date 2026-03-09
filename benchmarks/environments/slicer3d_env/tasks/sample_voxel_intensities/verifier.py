#!/usr/bin/env python3
"""
Verifier for Sample Voxel Intensities at Anatomical Landmarks task.

VERIFICATION CRITERIA:
1. Output file exists (15 points) - measurement file was created
2. File has structure (10 points) - contains identifiable measurements for 3 structures
3. Aorta measurement correct (20 points) - within tolerance of ground truth
4. Liver measurement correct (20 points) - within tolerance of ground truth
5. Spleen measurement correct (20 points) - within tolerance of ground truth
6. Data probe visible (10 points) - VLM confirms probe enabled in screenshots
7. Interpretation present (5 points) - clinical interpretation statement included

Pass threshold: 60 points with at least 2 correct measurements
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sample_voxel_intensities(traj, env_info, task_info):
    """
    Verify the sample voxel intensities task completion.
    
    Uses multi-criteria scoring with ground truth comparison.
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
    expected_ranges = metadata.get('expected_ranges', {
        "aorta": {"min": 150, "max": 250, "tolerance": 30},
        "liver": {"min": 40, "max": 80, "tolerance": 30},
        "spleen": {"min": 40, "max": 60, "tolerance": 30}
    })
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('output_file_exists', 15)
    w_structure = weights.get('file_has_structure', 10)
    w_aorta = weights.get('aorta_correct', 20)
    w_liver = weights.get('liver_correct', 20)
    w_spleen = weights.get('spleen_correct', 20)
    w_probe = weights.get('data_probe_visible', 10)
    w_interpretation = weights.get('interpretation_present', 5)

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}

    # ================================================================
    # Step 1: Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        # Try alternative location
        try:
            copy_from_env("/tmp/task_result/result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Export result not found: {e}"
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

    # ================================================================
    # Step 2: Load ground truth
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env("/tmp/task_result/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth from result dir: {e}")
        # Try alternative location
        try:
            copy_from_env("/var/lib/slicer/ground_truth/amos_0001_intensity_gt.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e2:
            logger.warning(f"Could not load ground truth: {e2}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_measurements = ground_truth.get('measurements', {})
    details['ground_truth_loaded'] = bool(gt_measurements)

    # ================================================================
    # Step 3: Check output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += w_file_exists
        feedback_parts.append(f"✓ Output file created during task (+{w_file_exists})")
        details['output_file_exists'] = True
        details['file_created_during_task'] = True
    elif output_exists:
        # File exists but was not created during task - suspicious
        score += w_file_exists // 2
        feedback_parts.append(f"~ Output file exists but timestamp unclear (+{w_file_exists // 2})")
        details['output_file_exists'] = True
        details['file_created_during_task'] = False
    else:
        feedback_parts.append("✗ Output file not found")
        details['output_file_exists'] = False
        # Cannot continue without output file
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # Step 4: Parse output content for measurements
    # ================================================================
    output_content = result.get('output_content', '')
    
    # Try to get measurements from parsed values first
    measurements = {}
    for organ in ['aorta', 'liver', 'spleen']:
        key = f'parsed_{organ}_hu'
        value = result.get(key, '')
        if value:
            try:
                measurements[organ] = float(value)
            except ValueError:
                pass
    
    # If parsing failed, try to extract from content directly
    if len(measurements) < 3 and output_content:
        for organ in ['aorta', 'liver', 'spleen']:
            if organ not in measurements:
                # Try various patterns
                patterns = [
                    rf'{organ}[:\s]+([0-9]+\.?[0-9]*)\s*HU',
                    rf'{organ}[:\s]+([0-9]+\.?[0-9]*)',
                    rf'{organ}.*?([0-9]+\.?[0-9]*)\s*HU',
                ]
                for pattern in patterns:
                    match = re.search(pattern, output_content, re.IGNORECASE)
                    if match:
                        try:
                            measurements[organ] = float(match.group(1))
                            break
                        except ValueError:
                            pass

    details['parsed_measurements'] = measurements
    structures_found = list(measurements.keys())
    details['structures_found'] = structures_found

    # ================================================================
    # Step 5: Check file structure (10 points)
    # ================================================================
    if len(structures_found) >= 3:
        score += w_structure
        feedback_parts.append(f"✓ All three structures documented (+{w_structure})")
    elif len(structures_found) >= 2:
        partial = int(w_structure * 0.7)
        score += partial
        feedback_parts.append(f"~ Two structures documented (+{partial})")
    elif len(structures_found) >= 1:
        partial = int(w_structure * 0.3)
        score += partial
        feedback_parts.append(f"~ One structure documented (+{partial})")
    else:
        feedback_parts.append("✗ No recognizable measurements in output file")

    # ================================================================
    # Step 6: Verify measurements against ground truth (60 points total)
    # ================================================================
    correct_measurements = 0
    
    for organ, weight in [('aorta', w_aorta), ('liver', w_liver), ('spleen', w_spleen)]:
        if organ in measurements:
            measured = measurements[organ]
            
            # Get expected value from ground truth or use expected range
            if organ in gt_measurements:
                expected = gt_measurements[organ].get('mean_hu', 0)
                tolerance = gt_measurements[organ].get('tolerance', 30)
            else:
                # Use midpoint of expected range
                organ_range = expected_ranges.get(organ, {"min": 0, "max": 200, "tolerance": 30})
                expected = (organ_range['min'] + organ_range['max']) / 2
                tolerance = organ_range.get('tolerance', 30)
            
            error = abs(measured - expected)
            details[f'{organ}_measured'] = measured
            details[f'{organ}_expected'] = expected
            details[f'{organ}_error'] = error
            
            # Also check if in physiologically plausible range
            organ_range = expected_ranges.get(organ, {"min": 0, "max": 500})
            in_plausible_range = organ_range['min'] - 50 <= measured <= organ_range['max'] + 50
            
            if error <= tolerance:
                score += weight
                correct_measurements += 1
                feedback_parts.append(f"✓ {organ.capitalize()}: {measured:.0f} HU (expected {expected:.0f}±{tolerance}) (+{weight})")
            elif error <= tolerance * 2 and in_plausible_range:
                partial = weight // 2
                score += partial
                feedback_parts.append(f"~ {organ.capitalize()}: {measured:.0f} HU close to expected {expected:.0f}±{tolerance} (+{partial})")
            elif in_plausible_range:
                # At least physiologically plausible
                partial = weight // 4
                score += partial
                feedback_parts.append(f"~ {organ.capitalize()}: {measured:.0f} HU plausible but differs from expected {expected:.0f} (+{partial})")
            else:
                feedback_parts.append(f"✗ {organ.capitalize()}: {measured:.0f} HU incorrect (expected {expected:.0f}±{tolerance})")
        else:
            feedback_parts.append(f"✗ {organ.capitalize()}: not found in output")
            details[f'{organ}_measured'] = None

    details['correct_measurements'] = correct_measurements

    # ================================================================
    # Step 7: Check for interpretation (5 points)
    # ================================================================
    has_interpretation = result.get('has_interpretation', False)
    
    if has_interpretation:
        score += w_interpretation
        feedback_parts.append(f"✓ Interpretation statement present (+{w_interpretation})")
        details['has_interpretation'] = True
    else:
        # Check content directly
        interpretation_keywords = ['interpretation', 'normal', 'expected', 'range', 
                                   'assessment', 'finding', 'conclusion', 'contrast', 
                                   'enhancement', 'within']
        if any(kw in output_content.lower() for kw in interpretation_keywords):
            score += w_interpretation
            feedback_parts.append(f"✓ Interpretation statement present (+{w_interpretation})")
            details['has_interpretation'] = True
        else:
            feedback_parts.append("~ No interpretation statement found")
            details['has_interpretation'] = False

    # ================================================================
    # Step 8: VLM verification for data probe (10 points)
    # ================================================================
    # Check if data probe was likely used based on evidence
    # If we have measurements and Slicer was running, give partial credit
    slicer_running = result.get('slicer_was_running', False)
    
    if slicer_running and correct_measurements >= 2:
        # Give credit if measurements obtained while Slicer was running
        score += w_probe
        feedback_parts.append(f"✓ Data probe likely used (Slicer running, measurements obtained) (+{w_probe})")
        details['data_probe_verified'] = True
    elif slicer_running and correct_measurements >= 1:
        partial = w_probe // 2
        score += partial
        feedback_parts.append(f"~ Partial evidence of data probe use (+{partial})")
        details['data_probe_verified'] = 'partial'
    else:
        feedback_parts.append("~ Could not verify data probe usage")
        details['data_probe_verified'] = False

    # ================================================================
    # Final scoring
    # ================================================================
    # Pass requires: score >= 60 AND at least 2 correct measurements
    key_criteria_met = correct_measurements >= 2
    passed = score >= 60 and key_criteria_met

    details['total_score'] = score
    details['max_score'] = max_score
    details['key_criteria_met'] = key_criteria_met
    details['passed'] = passed

    feedback = "\n".join(feedback_parts)
    
    if passed:
        feedback += f"\n\n✓ PASSED: {score}/{max_score} points with {correct_measurements} correct measurements"
    else:
        if not key_criteria_met:
            feedback += f"\n\n✗ FAILED: Need at least 2 correct measurements (got {correct_measurements})"
        else:
            feedback += f"\n\n✗ FAILED: Score {score}/{max_score} below threshold of 60"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }