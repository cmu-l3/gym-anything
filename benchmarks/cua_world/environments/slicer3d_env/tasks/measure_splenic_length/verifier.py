#!/usr/bin/env python3
"""
Verifier for splenic length measurement task.

VERIFICATION CRITERIA (Multi-signal approach):
1. JSON file created (15 points) - output file exists with valid structure
2. Required fields present (10 points) - all required fields in JSON
3. Measurement accuracy (30 points) - within tolerance of ground truth
4. Classification correct (20 points) - splenomegaly boolean matches expected
5. Screenshot exists (10 points) - evidence of measurement captured
6. VLM spleen verification (10 points) - visual confirmation of measurement on spleen
7. Appropriate view used (5 points) - coronal/sagittal view for measurement

Pass threshold: 60 points with measurement_accuracy >= 15 points
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_splenic_length(traj, env_info, task_info):
    """
    Verify that the splenic length was measured correctly.
    
    Uses multiple independent signals to prevent gaming:
    - Programmatic checks on output files
    - Timestamp verification (anti-gaming)
    - VLM trajectory verification
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
    tolerance_pct = metadata.get('measurement_tolerance_percent', 15)
    min_measurement = metadata.get('min_measurement_mm', 50)
    max_measurement = metadata.get('max_measurement_mm', 300)
    
    weights = metadata.get('scoring_weights', {})
    w_json_created = weights.get('json_file_created', 15)
    w_fields_present = weights.get('required_fields_present', 10)
    w_accuracy = weights.get('measurement_accuracy', 30)
    w_classification = weights.get('classification_correct', 20)
    w_screenshot = weights.get('screenshot_exists', 10)
    w_vlm = weights.get('vlm_spleen_verification', 10)
    w_view = weights.get('appropriate_view_used', 5)

    # Initialize results
    score = 0
    feedback_parts = []
    details = {}
    scores_breakdown = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/splenic_task_result.json", temp_result.name)
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

    # ================================================================
    # CRITERION 1: JSON file created (15 points)
    # ================================================================
    measurement_exists = result.get('measurement_file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if measurement_exists:
        if file_created_during_task:
            scores_breakdown['json_file_created'] = w_json_created
            score += w_json_created
            feedback_parts.append("✓ Measurement JSON file created during task")
        else:
            # Partial credit - file exists but may have been pre-existing
            scores_breakdown['json_file_created'] = w_json_created // 2
            score += w_json_created // 2
            feedback_parts.append("~ Measurement file exists (may not be new)")
    else:
        scores_breakdown['json_file_created'] = 0
        feedback_parts.append("✗ Measurement JSON file not found")

    # ================================================================
    # CRITERION 2: Required fields present (10 points)
    # ================================================================
    measurement_valid = result.get('measurement_valid', False)
    
    if measurement_valid:
        scores_breakdown['required_fields_present'] = w_fields_present
        score += w_fields_present
        feedback_parts.append("✓ All required fields present in JSON")
    else:
        scores_breakdown['required_fields_present'] = 0
        feedback_parts.append("✗ JSON missing required fields (length_mm, splenomegaly, assessment)")

    # ================================================================
    # CRITERION 3: Measurement accuracy (30 points)
    # ================================================================
    measured_length = result.get('measured_length_mm', 0)
    gt_length = result.get('ground_truth_length_mm', 0)
    error_pct = result.get('measurement_error_percent', 100)
    measurement_accurate = result.get('measurement_accurate', False)
    measurement_reasonable = result.get('measurement_reasonable', False)
    
    details['measured_length_mm'] = measured_length
    details['ground_truth_length_mm'] = gt_length
    details['measurement_error_percent'] = error_pct
    
    if measurement_accurate:
        scores_breakdown['measurement_accuracy'] = w_accuracy
        score += w_accuracy
        feedback_parts.append(f"✓ Measurement accurate: {measured_length:.1f}mm (GT: {gt_length:.1f}mm, error: {error_pct:.1f}%)")
    elif measurement_reasonable and measured_length > 0 and gt_length > 0:
        # Partial credit based on accuracy
        if error_pct < 25:
            partial = int(w_accuracy * 0.7)
            scores_breakdown['measurement_accuracy'] = partial
            score += partial
            feedback_parts.append(f"~ Measurement close: {measured_length:.1f}mm (GT: {gt_length:.1f}mm, error: {error_pct:.1f}%)")
        elif error_pct < 40:
            partial = int(w_accuracy * 0.4)
            scores_breakdown['measurement_accuracy'] = partial
            score += partial
            feedback_parts.append(f"~ Measurement approximate: {measured_length:.1f}mm (GT: {gt_length:.1f}mm, error: {error_pct:.1f}%)")
        else:
            scores_breakdown['measurement_accuracy'] = 0
            feedback_parts.append(f"✗ Measurement inaccurate: {measured_length:.1f}mm (GT: {gt_length:.1f}mm, error: {error_pct:.1f}%)")
    elif measured_length > 0:
        # Measurement exists but no GT or out of reasonable range
        if min_measurement <= measured_length <= max_measurement:
            partial = int(w_accuracy * 0.3)
            scores_breakdown['measurement_accuracy'] = partial
            score += partial
            feedback_parts.append(f"~ Measurement in physiologic range: {measured_length:.1f}mm (GT unavailable)")
        else:
            scores_breakdown['measurement_accuracy'] = 0
            feedback_parts.append(f"✗ Measurement out of range: {measured_length:.1f}mm (expected {min_measurement}-{max_measurement}mm)")
    else:
        scores_breakdown['measurement_accuracy'] = 0
        feedback_parts.append("✗ No valid measurement found")

    # ================================================================
    # CRITERION 4: Classification correct (20 points)
    # ================================================================
    classification_correct = result.get('classification_correct', False)
    measured_spleno = result.get('measured_splenomegaly', 'unknown')
    gt_spleno = result.get('ground_truth_splenomegaly', 'unknown')
    measured_assessment = result.get('measured_assessment', '')
    gt_classification = result.get('ground_truth_classification', '')
    
    details['measured_splenomegaly'] = measured_spleno
    details['gt_splenomegaly'] = gt_spleno
    
    if classification_correct:
        scores_breakdown['classification_correct'] = w_classification
        score += w_classification
        feedback_parts.append(f"✓ Splenomegaly classification correct: {measured_assessment}")
    elif measured_spleno != 'unknown' and measurement_valid:
        # Check if classification is internally consistent with measurement
        expected_spleno = measured_length >= 120 if measured_length > 0 else None
        if expected_spleno is not None:
            measured_spleno_bool = str(measured_spleno).lower() == 'true'
            if measured_spleno_bool == expected_spleno:
                # Classification is at least self-consistent
                partial = int(w_classification * 0.5)
                scores_breakdown['classification_correct'] = partial
                score += partial
                feedback_parts.append(f"~ Classification self-consistent: {measured_assessment}")
            else:
                scores_breakdown['classification_correct'] = 0
                feedback_parts.append(f"✗ Classification inconsistent with measurement")
        else:
            scores_breakdown['classification_correct'] = 0
            feedback_parts.append(f"✗ Classification incorrect: {measured_assessment} (expected based on GT: {gt_classification})")
    else:
        scores_breakdown['classification_correct'] = 0
        feedback_parts.append("✗ No classification provided")

    # ================================================================
    # CRITERION 5: Screenshot exists (10 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    new_screenshots = result.get('new_screenshots_count', 0)
    
    if screenshot_exists and new_screenshots > 0:
        scores_breakdown['screenshot_exists'] = w_screenshot
        score += w_screenshot
        feedback_parts.append(f"✓ Screenshot captured ({new_screenshots} new)")
    elif screenshot_exists:
        partial = int(w_screenshot * 0.7)
        scores_breakdown['screenshot_exists'] = partial
        score += partial
        feedback_parts.append("~ Screenshot available (final state)")
    else:
        scores_breakdown['screenshot_exists'] = 0
        feedback_parts.append("✗ No screenshot found")

    # ================================================================
    # CRITERION 6: VLM spleen verification (10 points)
    # Use trajectory frames if available
    # ================================================================
    vlm_score = 0
    
    # Check if we have trajectory data
    trajectory_data = traj if isinstance(traj, dict) else {}
    screenshots = trajectory_data.get('screenshots', [])
    
    # Try to get VLM query function
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and len(screenshots) > 0:
        try:
            # Sample trajectory frames for process verification
            n_frames = min(5, len(screenshots))
            step = max(1, len(screenshots) // n_frames)
            sampled_frames = [screenshots[i] for i in range(0, len(screenshots), step)][:n_frames]
            
            vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to measure the splenic length (spleen size) on abdominal CT.

Look for evidence of:
1. CT scan showing abdominal anatomy
2. Navigation to the spleen region (left upper quadrant)
3. Use of coronal or sagittal view for measurement
4. A ruler/line measurement tool placed on the spleen
5. The measurement appearing to span from superior to inferior pole

Respond in JSON format:
{
    "abdominal_ct_visible": true/false,
    "spleen_region_visible": true/false,
    "measurement_tool_visible": true/false,
    "coronal_or_sagittal_view": true/false,
    "measurement_on_spleen": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=sampled_frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                if parsed.get('measurement_on_spleen', False):
                    vlm_score = w_vlm
                    feedback_parts.append("✓ VLM confirms measurement on spleen")
                elif parsed.get('measurement_tool_visible', False):
                    vlm_score = int(w_vlm * 0.6)
                    feedback_parts.append("~ VLM sees measurement tool")
                elif parsed.get('abdominal_ct_visible', False):
                    vlm_score = int(w_vlm * 0.3)
                    feedback_parts.append("~ VLM confirms abdominal CT visible")
                else:
                    feedback_parts.append("○ VLM could not confirm spleen measurement")
                
                details['vlm_result'] = parsed
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"○ VLM verification unavailable: {e}")
    elif len(screenshots) > 0:
        # Give partial credit for having trajectory screenshots
        vlm_score = int(w_vlm * 0.3)
        feedback_parts.append("~ Trajectory screenshots captured for review")
    else:
        feedback_parts.append("○ No trajectory data for VLM verification")
    
    scores_breakdown['vlm_spleen_verification'] = vlm_score
    score += vlm_score

    # ================================================================
    # CRITERION 7: Appropriate view used (5 points)
    # Infer from measurement accuracy and VLM
    # ================================================================
    if measurement_accurate or (vlm_score > 0 and measurement_reasonable):
        scores_breakdown['appropriate_view_used'] = w_view
        score += w_view
        feedback_parts.append("✓ Appropriate view likely used")
    elif measurement_reasonable:
        partial = int(w_view * 0.6)
        scores_breakdown['appropriate_view_used'] = partial
        score += partial
        feedback_parts.append("~ View selection acceptable")
    else:
        scores_breakdown['appropriate_view_used'] = 0

    # ================================================================
    # Anti-gaming checks
    # ================================================================
    # Check if Slicer was actually running
    slicer_running = result.get('slicer_running', False)
    if not slicer_running:
        feedback_parts.append("⚠ Warning: Slicer was not running at export time")
        # Reduce score if Slicer wasn't running
        score = int(score * 0.7)

    # Check timestamp - file must be created during task
    if measurement_exists and not file_created_during_task:
        feedback_parts.append("⚠ Warning: Output file may not have been created during task")

    # ================================================================
    # Calculate final result
    # ================================================================
    # Pass requires 60 points AND at least 15 points on measurement accuracy
    accuracy_score = scores_breakdown.get('measurement_accuracy', 0)
    passed = score >= 60 and accuracy_score >= 15

    details['scores_breakdown'] = scores_breakdown
    details['measurement_accurate'] = measurement_accurate
    details['classification_correct'] = classification_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # For standalone testing
    result = verify_splenic_length({}, {}, {})
    print(json.dumps(result, indent=2))