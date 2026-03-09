#!/usr/bin/env python3
"""
Verifier for Lung Nodule Measurement task.

VERIFICATION STRATEGY (Multi-Signal Anti-Gaming):

Programmatic Checks (85 points):
1. Line markup created in Slicer (20 pts)
2. Measurement file exported (15 pts)  
3. Measurement accuracy vs ground truth (35 pts - proportional)
4. Line position validity (15 pts) - measurement is in plausible lung region

VLM Trajectory Check (15 points):
5. Trajectory shows measurement workflow progression (15 pts)

ANTI-GAMING MEASURES:
- Timestamp validation (file must be created during task)
- Value range validation (measurement must be plausible for lung nodules: 3-30mm)
- Process validation via trajectory frames

Pass Threshold: 60 points with (line_markup OR measurement_file) AND measurement_valid
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_lung_nodule(traj, env_info, task_info):
    """
    Verify lung nodule measurement task completion.
    
    Uses copy_from_env to read result files from container.
    Uses trajectory frames for VLM verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    tolerance_mm = metadata.get('measurement_tolerance_mm', 3.0)
    plausible_range = metadata.get('nodule_diameter_plausible_range_mm', {"min": 3, "max": 30})
    weights = metadata.get('scoring_weights', {})
    
    w_line_created = weights.get('line_markup_created', 20)
    w_measurement_exported = weights.get('measurement_exported', 15)
    w_measurement_accuracy = weights.get('measurement_accuracy', 35)
    w_line_position = weights.get('line_position_valid', 15)
    w_vlm = weights.get('vlm_confirmation', 15)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lung_nodule_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_loaded'] = True
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - export script may have failed"
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task cannot be completed"
        }
    
    # ================================================================
    # CRITERION 1: Line markup created (20 points)
    # ================================================================
    line_markup_exists = result.get('line_markup_exists', False)
    line_length_mm = float(result.get('line_length_mm', 0))
    
    if line_markup_exists and line_length_mm > 0:
        score += w_line_created
        feedback_parts.append(f"Line markup created ({line_length_mm:.1f}mm)")
        details['line_markup_created'] = True
    else:
        feedback_parts.append("No line markup found in Slicer")
        details['line_markup_created'] = False
    
    # ================================================================
    # CRITERION 2: Measurement file exported (15 points)
    # ================================================================
    measurement_file_exists = result.get('measurement_file_exists', False)
    measurement_file_created = result.get('measurement_file_created_during_task', False)
    reported_diameter = float(result.get('reported_diameter_mm', 0))
    
    if measurement_file_exists:
        if measurement_file_created:
            score += w_measurement_exported
            feedback_parts.append(f"Measurement exported ({reported_diameter:.1f}mm)")
            details['measurement_exported'] = True
            details['measurement_created_during_task'] = True
        else:
            # File exists but wasn't created during task - partial credit
            score += w_measurement_exported // 2
            feedback_parts.append("Measurement file existed before task")
            details['measurement_exported'] = True
            details['measurement_created_during_task'] = False
    else:
        feedback_parts.append("No measurement file exported")
        details['measurement_exported'] = False
    
    # ================================================================
    # Determine best available measurement
    # ================================================================
    best_measurement = float(result.get('best_measurement_mm', 0))
    measurement_source = result.get('measurement_source', 'none')
    gt_diameter = float(result.get('ground_truth_diameter_mm', 0))
    
    details['best_measurement_mm'] = best_measurement
    details['measurement_source'] = measurement_source
    details['ground_truth_diameter_mm'] = gt_diameter
    
    # ================================================================
    # CRITERION 3: Measurement accuracy (35 points - proportional)
    # ================================================================
    measurement_valid = False
    measurement_error = float(result.get('measurement_error_mm', 999))
    
    # Check if measurement is in plausible range for lung nodules
    min_valid = plausible_range.get('min', 3)
    max_valid = plausible_range.get('max', 30)
    
    if best_measurement > 0:
        in_plausible_range = min_valid <= best_measurement <= max_valid
        details['measurement_in_plausible_range'] = in_plausible_range
        
        if not in_plausible_range:
            feedback_parts.append(f"Measurement {best_measurement:.1f}mm outside plausible range ({min_valid}-{max_valid}mm)")
            details['measurement_accuracy_score'] = 0
        else:
            # Calculate accuracy score
            if gt_diameter > 0:
                measurement_error = abs(best_measurement - gt_diameter)
                details['measurement_error_mm'] = measurement_error
                
                if measurement_error <= 1.0:
                    # Excellent: within 1mm
                    accuracy_score = w_measurement_accuracy
                    measurement_valid = True
                    feedback_parts.append(f"Excellent accuracy ({measurement_error:.1f}mm error)")
                elif measurement_error <= 2.0:
                    # Good: within 2mm
                    accuracy_score = int(w_measurement_accuracy * 0.8)
                    measurement_valid = True
                    feedback_parts.append(f"Good accuracy ({measurement_error:.1f}mm error)")
                elif measurement_error <= tolerance_mm:
                    # Acceptable: within tolerance
                    accuracy_score = int(w_measurement_accuracy * 0.6)
                    measurement_valid = True
                    feedback_parts.append(f"Acceptable accuracy ({measurement_error:.1f}mm error)")
                elif measurement_error <= tolerance_mm * 1.5:
                    # Marginal: slightly outside tolerance
                    accuracy_score = int(w_measurement_accuracy * 0.3)
                    feedback_parts.append(f"Marginal accuracy ({measurement_error:.1f}mm error)")
                else:
                    # Poor: significantly outside tolerance
                    accuracy_score = 0
                    feedback_parts.append(f"Poor accuracy ({measurement_error:.1f}mm error vs GT {gt_diameter:.1f}mm)")
                
                score += accuracy_score
                details['measurement_accuracy_score'] = accuracy_score
            else:
                # No ground truth available - give partial credit for plausible measurement
                score += int(w_measurement_accuracy * 0.5)
                measurement_valid = True
                feedback_parts.append(f"Measurement {best_measurement:.1f}mm (no GT for comparison)")
                details['measurement_accuracy_score'] = int(w_measurement_accuracy * 0.5)
    else:
        feedback_parts.append("No valid measurement obtained")
        details['measurement_accuracy_score'] = 0
    
    details['measurement_valid'] = measurement_valid
    
    # ================================================================
    # CRITERION 4: Line position validity (15 points)
    # ================================================================
    line_in_lung = result.get('line_in_lung_region', False)
    line_z = float(result.get('line_z_coord', 0))
    nodule_centroid = result.get('nodule_centroid_ras', [0, 0, 0])
    
    if line_markup_exists:
        # Check if measurement is near the expected nodule location
        if isinstance(nodule_centroid, list) and len(nodule_centroid) >= 3:
            expected_z = nodule_centroid[2]
            z_distance = abs(line_z - expected_z)
            details['z_distance_from_nodule'] = z_distance
            
            # Allow some tolerance in z-direction (multiple valid slices)
            if z_distance < 30:  # Within 30mm of nodule z-coordinate
                score += w_line_position
                feedback_parts.append(f"Measurement near nodule location")
                details['line_position_valid'] = True
            elif z_distance < 60:
                score += w_line_position // 2
                feedback_parts.append(f"Measurement somewhat near nodule")
                details['line_position_valid'] = "partial"
            else:
                feedback_parts.append(f"Measurement far from nodule location")
                details['line_position_valid'] = False
        elif line_in_lung:
            # Fallback: just check if in lung region
            score += w_line_position
            feedback_parts.append("Measurement in lung region")
            details['line_position_valid'] = True
        else:
            feedback_parts.append("Cannot verify measurement position")
            details['line_position_valid'] = "unknown"
    else:
        details['line_position_valid'] = False
    
    # ================================================================
    # CRITERION 5: VLM trajectory verification (15 points)
    # ================================================================
    vlm_score = 0
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5) if traj else []
        final_frame = get_final_screenshot(traj) if traj else None
        
        if frames or final_frame:
            all_frames = frames + ([final_frame] if final_frame else [])
            
            vlm_prompt = """You are verifying a lung nodule measurement task in 3D Slicer medical imaging software.

The agent should have:
1. Navigated to a lung nodule in a chest CT scan
2. Used a line/ruler measurement tool to measure the nodule diameter
3. The measurement line should be visible across a round nodular structure in the lung

Analyze these screenshots (chronological order, earliest to latest) and determine:

1. SLICER_VISIBLE: Is 3D Slicer medical imaging software visible?
2. CT_LOADED: Is a chest CT scan loaded (grayscale lung images with air appearing dark)?
3. NODULE_VISIBLE: Can you see a lung nodule (small round/oval opacity in the lung field)?
4. MEASUREMENT_TOOL_USED: Is there a line/ruler measurement visible on the image?
5. MEASUREMENT_ON_NODULE: Does the measurement line appear to cross a nodular structure?
6. WORKFLOW_PROGRESSION: Do the frames show progression of work (not just static screens)?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "ct_loaded": true/false,
    "nodule_visible": true/false,
    "measurement_tool_used": true/false,
    "measurement_on_nodule": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                slicer_visible = parsed.get('slicer_visible', False)
                ct_loaded = parsed.get('ct_loaded', False)
                measurement_used = parsed.get('measurement_tool_used', False)
                measurement_on_nodule = parsed.get('measurement_on_nodule', False)
                workflow_ok = parsed.get('workflow_progression', False)
                
                # Score VLM verification
                if measurement_on_nodule and measurement_used:
                    vlm_score = w_vlm
                    feedback_parts.append("VLM confirms measurement on nodule")
                elif measurement_used and ct_loaded:
                    vlm_score = int(w_vlm * 0.7)
                    feedback_parts.append("VLM confirms measurement tool used")
                elif ct_loaded and slicer_visible:
                    vlm_score = int(w_vlm * 0.3)
                    feedback_parts.append("VLM confirms CT loaded in Slicer")
                else:
                    feedback_parts.append("VLM could not confirm task completion")
                
                details['vlm_score'] = vlm_score
            else:
                logger.warning("VLM query failed or returned no result")
                details['vlm_error'] = "Query failed"
                # Give partial credit if we have other evidence
                if measurement_valid and line_markup_exists:
                    vlm_score = int(w_vlm * 0.5)
                    feedback_parts.append("VLM unavailable but programmatic checks passed")
        else:
            logger.warning("No trajectory frames available for VLM verification")
            details['vlm_error'] = "No frames"
            # Give partial credit
            if measurement_valid:
                vlm_score = int(w_vlm * 0.3)
                
    except ImportError as e:
        logger.warning(f"VLM utilities not available: {e}")
        details['vlm_error'] = f"Import error: {e}"
        # Give partial credit if programmatic checks passed
        if measurement_valid and line_markup_exists:
            vlm_score = int(w_vlm * 0.5)
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)
        if measurement_valid:
            vlm_score = int(w_vlm * 0.3)
    
    score += vlm_score
    details['vlm_final_score'] = vlm_score
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    max_score = w_line_created + w_measurement_exported + w_measurement_accuracy + w_line_position + w_vlm
    
    # Key criteria for passing
    has_measurement_evidence = line_markup_exists or measurement_file_exists
    measurement_is_valid = measurement_valid or (best_measurement > min_valid and best_measurement < max_valid)
    
    # Pass if score >= 60 AND key criteria met
    passed = score >= 60 and has_measurement_evidence and measurement_is_valid
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary_parts = []
    if passed:
        summary_parts.append(f"PASSED ({score}/{max_score})")
    else:
        summary_parts.append(f"FAILED ({score}/{max_score})")
        if not has_measurement_evidence:
            summary_parts.append("No measurement created")
        if not measurement_is_valid:
            summary_parts.append("Measurement invalid or inaccurate")
    
    details['summary'] = " - ".join(summary_parts)
    details['final_score'] = score
    details['max_score'] = max_score
    details['passed'] = passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }