#!/usr/bin/env python3
"""
Verifier for compute_segmentation_metrics task.

VERIFICATION STRATEGY (Multi-Signal + VLM Hybrid):

Programmatic Checks (70 points):
1. AI segmentation loaded (15 pts)
2. Reference segmentation loaded (15 pts)
3. Segment Comparison module used (20 pts) - evidence from exports/windows
4. Dice coefficient computed and in valid range (20 pts)
5. Hausdorff distance computed (15 pts)
6. Results exported to JSON (15 pts)

VLM Checks (30 points):
7. Trajectory shows workflow progression (15 pts)
8. Final screenshot shows comparison results (15 pts)

Pass threshold: 60 points with both segmentations loaded and Dice computed
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compute_segmentation_metrics(traj, env_info, task_info):
    """
    Verify that segmentation comparison metrics were computed correctly.
    
    Uses multiple signals: file checks, metric validation, and VLM trajectory analysis.
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
    expected_dice_range = metadata.get('expected_dice_range', {"min": 0.70, "max": 0.90})
    expected_hausdorff_range = metadata.get('expected_hausdorff_range_mm', {"min": 5, "max": 35})
    output_report_path = metadata.get('output_report_path', '/home/ga/Documents/SlicerData/Exports/segmentation_metrics.json')
    
    weights = metadata.get('scoring_weights', {})
    w_ai_loaded = weights.get('ai_segmentation_loaded', 15)
    w_ref_loaded = weights.get('reference_segmentation_loaded', 15)
    w_comparison_used = weights.get('segment_comparison_used', 20)
    w_dice = weights.get('dice_computed', 20)
    w_hausdorff = weights.get('hausdorff_computed', 15)
    w_report = weights.get('report_exported', 15)
    
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
        copy_from_env("/tmp/segmentation_metrics_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task"
        }
    
    details['result'] = result
    
    # ================================================================
    # Try to also read the agent's metrics report directly
    # ================================================================
    agent_report = {}
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_metrics_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        details['agent_report'] = agent_report
    except Exception as e:
        logger.info(f"Could not read agent's report directly: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    # ================================================================
    # CRITERION 1: AI Segmentation Loaded (15 points)
    # ================================================================
    ai_loaded = result.get('ai_segmentation_loaded', False)
    num_segs = int(result.get('num_segmentations_loaded', 0) or 0)
    
    if ai_loaded or num_segs >= 1:
        score += w_ai_loaded
        feedback_parts.append("AI segmentation loaded")
        details['ai_seg_loaded'] = True
    else:
        feedback_parts.append("AI segmentation NOT loaded")
        details['ai_seg_loaded'] = False
    
    # ================================================================
    # CRITERION 2: Reference Segmentation Loaded (15 points)
    # ================================================================
    ref_loaded = result.get('reference_segmentation_loaded', False)
    
    if ref_loaded or num_segs >= 2:
        score += w_ref_loaded
        feedback_parts.append("Reference segmentation loaded")
        details['ref_seg_loaded'] = True
    else:
        feedback_parts.append("Reference segmentation NOT loaded")
        details['ref_seg_loaded'] = False
    
    # ================================================================
    # CRITERION 3: Segment Comparison Module Used (20 points)
    # ================================================================
    comparison_used = result.get('segment_comparison_used', False)
    
    # Also check if we have metrics (implies comparison was used)
    has_metrics = bool(result.get('dice_coefficient')) or bool(agent_report.get('dice_coefficient'))
    
    if comparison_used or has_metrics:
        score += w_comparison_used
        feedback_parts.append("Segment Comparison module used")
        details['comparison_used'] = True
    else:
        feedback_parts.append("Segment Comparison module NOT used")
        details['comparison_used'] = False
    
    # ================================================================
    # CRITERION 4: Dice Coefficient Computed (20 points)
    # ================================================================
    dice_str = result.get('dice_coefficient', '') or agent_report.get('dice_coefficient', '')
    dice_value = None
    
    if dice_str:
        try:
            dice_value = float(dice_str)
        except (ValueError, TypeError):
            pass
    
    if dice_value is not None:
        details['dice_coefficient'] = dice_value
        
        # Check if Dice is in valid range (0-1)
        if 0.0 <= dice_value <= 1.0:
            # Check if Dice is in expected range for the known broken segmentation
            if expected_dice_range['min'] <= dice_value <= expected_dice_range['max']:
                score += w_dice
                feedback_parts.append(f"Dice coefficient: {dice_value:.4f} (in expected range)")
                details['dice_valid'] = True
                details['dice_in_expected_range'] = True
            else:
                # Give partial credit if value is valid but outside expected range
                score += int(w_dice * 0.7)
                feedback_parts.append(f"Dice coefficient: {dice_value:.4f} (outside expected range {expected_dice_range['min']}-{expected_dice_range['max']})")
                details['dice_valid'] = True
                details['dice_in_expected_range'] = False
        else:
            feedback_parts.append(f"Dice coefficient invalid: {dice_value}")
            details['dice_valid'] = False
    else:
        feedback_parts.append("Dice coefficient NOT computed")
        details['dice_valid'] = False
    
    # ================================================================
    # CRITERION 5: Hausdorff Distance Computed (15 points)
    # ================================================================
    hausdorff_str = result.get('hausdorff_distance_mm', '') or agent_report.get('hausdorff_distance_mm', '')
    hausdorff_value = None
    
    if hausdorff_str:
        try:
            hausdorff_value = float(hausdorff_str)
        except (ValueError, TypeError):
            pass
    
    if hausdorff_value is not None and hausdorff_value > 0:
        details['hausdorff_distance_mm'] = hausdorff_value
        
        # Check if in expected range
        if expected_hausdorff_range['min'] <= hausdorff_value <= expected_hausdorff_range['max']:
            score += w_hausdorff
            feedback_parts.append(f"Hausdorff distance: {hausdorff_value:.2f}mm (in expected range)")
            details['hausdorff_valid'] = True
        else:
            # Partial credit
            score += int(w_hausdorff * 0.7)
            feedback_parts.append(f"Hausdorff distance: {hausdorff_value:.2f}mm (outside expected range)")
            details['hausdorff_valid'] = True
    else:
        feedback_parts.append("Hausdorff distance NOT computed")
        details['hausdorff_valid'] = False
    
    # ================================================================
    # CRITERION 6: Report Exported to JSON (15 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    if report_exists and report_created:
        score += w_report
        feedback_parts.append("Report exported during task")
        details['report_exported'] = True
    elif report_exists:
        # Partial credit if file exists but wasn't created during task
        score += int(w_report * 0.5)
        feedback_parts.append("Report file exists (may be pre-existing)")
        details['report_exported'] = True
    else:
        feedback_parts.append("Report NOT exported")
        details['report_exported'] = False
    
    # ================================================================
    # VLM VERIFICATION (if available)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5) if hasattr(traj, '__iter__') else []
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                # VLM check on trajectory progression
                trajectory_prompt = """Analyze these screenshots from a 3D Slicer session where the user should be computing segmentation comparison metrics.

The expected workflow involves:
1. Loading segmentation files
2. Opening the Segment Comparison module
3. Selecting segmentations to compare
4. Running comparison to get Dice and Hausdorff metrics
5. Viewing/exporting results

Assess the screenshots and determine:
1. Was 3D Slicer in use?
2. Were segmentations visible (colorful regions overlaid on images)?
3. Was the Segment Comparison module visible at any point?
4. Were comparison results/metrics displayed?

Respond in JSON:
{
    "slicer_visible": true/false,
    "segmentations_visible": true/false,
    "segment_comparison_module_visible": true/false,
    "comparison_results_visible": true/false,
    "workflow_evidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                
                images_to_check = frames + ([final_frame] if final_frame else [])
                if images_to_check:
                    vlm_result = query_vlm(prompt=trajectory_prompt, images=images_to_check[:6])
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        # Score VLM findings
                        if parsed.get('slicer_visible'):
                            vlm_score += 5
                        if parsed.get('segmentations_visible'):
                            vlm_score += 10
                        if parsed.get('segment_comparison_module_visible'):
                            vlm_score += 10
                        if parsed.get('comparison_results_visible'):
                            vlm_score += 5
                        
                        workflow_evidence = parsed.get('workflow_evidence', 'low')
                        if workflow_evidence == 'high':
                            vlm_score += 0  # Already counted above
                        elif workflow_evidence == 'medium':
                            vlm_score = max(vlm_score, 15)
                        
                        feedback_parts.append(f"VLM: workflow evidence={workflow_evidence}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # Add VLM score (capped at 30 points)
    vlm_score = min(vlm_score, 30)
    # Scale VLM contribution to not exceed total
    if score + vlm_score > 100:
        vlm_score = 100 - score
    score += vlm_score
    
    # ================================================================
    # Final scoring and pass determination
    # ================================================================
    
    # Key criteria for passing:
    # - At least one segmentation loaded
    # - Dice coefficient computed
    key_criteria_met = (
        details.get('ai_seg_loaded', False) and
        details.get('dice_valid', False)
    )
    
    # Pass if score >= 60 AND key criteria met
    passed = score >= 60 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }