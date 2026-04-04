#!/usr/bin/env python3
"""
Verifier for fill_segmentation_holes task.

VERIFICATION STRATEGY:
Uses multiple independent signals to verify the task was completed correctly:

1. Output file exists (15 pts) - Segmentation was saved
2. File recently modified (10 pts) - Anti-gaming: file created during task
3. Volume increased (25 pts) - Holes were filled (volume should increase 5-25%)
4. Volume not over-expanded (15 pts) - Didn't just dilate massively
5. Euler improved (15 pts) - Fewer topological holes
6. Bounding box stable (10 pts) - Outer boundary unchanged
7. VLM confirms solid (10 pts) - Visual check shows filled segment

Pass threshold: 70 points with output_exists AND volume_increased
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fill_segmentation_holes(traj, env_info, task_info):
    """
    Verify that internal holes in the lung segmentation were filled.
    
    Uses multi-criteria scoring with anti-gaming measures.
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
    min_increase = metadata.get('expected_volume_increase_min_percent', 5)
    max_increase = metadata.get('expected_volume_increase_max_percent', 30)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_file_exists', 15)
    w_file_modified = weights.get('file_recently_modified', 10)
    w_volume_increased = weights.get('volume_increased', 25)
    w_not_overexpanded = weights.get('volume_not_overexpanded', 15)
    w_euler = weights.get('euler_improved', 15)
    w_bbox = weights.get('bounding_box_stable', 10)
    w_vlm = weights.get('vlm_confirms_solid', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fill_holes_result.json", temp_result.name)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer not running")
        # Continue checking other criteria anyway
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    segment_found = result.get('segment_found', False)
    
    if output_exists and segment_found:
        score += w_output_exists
        feedback_parts.append("Output file exists with valid segment")
        details['output_exists'] = True
    elif output_exists:
        score += w_output_exists * 0.5
        feedback_parts.append("Output file exists (segment unclear)")
        details['output_exists'] = True
    else:
        feedback_parts.append("No output file found")
        details['output_exists'] = False
        # Early exit - nothing else to check meaningfully
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File recently modified (10 points) - Anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += w_file_modified
        feedback_parts.append("File created during task")
        details['file_modified_during_task'] = True
    else:
        feedback_parts.append("File may pre-exist task")
        details['file_modified_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Volume increased (25 points)
    # ================================================================
    initial_volume = result.get('initial_volume_voxels', 0)
    final_volume = result.get('final_volume_voxels', 0)
    volume_change_pct = result.get('volume_change_percent', 0)
    
    details['initial_volume_voxels'] = initial_volume
    details['final_volume_voxels'] = final_volume
    details['volume_change_percent'] = volume_change_pct
    
    if volume_change_pct >= min_increase:
        score += w_volume_increased
        feedback_parts.append(f"Volume increased by {volume_change_pct:.1f}%")
        details['volume_increased'] = True
    elif volume_change_pct > 0:
        # Partial credit for any increase
        partial = w_volume_increased * (volume_change_pct / min_increase)
        score += min(partial, w_volume_increased * 0.7)
        feedback_parts.append(f"Volume increased slightly ({volume_change_pct:.1f}%)")
        details['volume_increased'] = 'partial'
    else:
        feedback_parts.append(f"Volume did not increase ({volume_change_pct:.1f}%)")
        details['volume_increased'] = False
    
    # ================================================================
    # CRITERION 4: Volume not over-expanded (15 points)
    # ================================================================
    if volume_change_pct <= max_increase:
        score += w_not_overexpanded
        feedback_parts.append("Volume within expected range")
        details['not_overexpanded'] = True
    elif volume_change_pct <= max_increase * 1.5:
        # Slight over-expansion - partial credit
        score += w_not_overexpanded * 0.5
        feedback_parts.append(f"Volume slightly over-expanded ({volume_change_pct:.1f}%)")
        details['not_overexpanded'] = 'partial'
    else:
        feedback_parts.append(f"Volume over-expanded ({volume_change_pct:.1f}% > {max_increase}%)")
        details['not_overexpanded'] = False
    
    # ================================================================
    # CRITERION 5: Euler characteristic improved (15 points)
    # ================================================================
    euler_improved = result.get('euler_improved', False)
    
    if euler_improved:
        score += w_euler
        feedback_parts.append("Topological holes reduced")
        details['euler_improved'] = True
    else:
        # If volume increased substantially, give partial credit
        if volume_change_pct >= min_increase:
            score += w_euler * 0.5
            feedback_parts.append("Holes likely filled (volume increased)")
        else:
            feedback_parts.append("Topological improvement unclear")
        details['euler_improved'] = euler_improved
    
    # ================================================================
    # CRITERION 6: Bounding box stable (10 points)
    # ================================================================
    bbox_stable = result.get('bbox_stable', False)
    
    if bbox_stable:
        score += w_bbox
        feedback_parts.append("Segment boundary preserved")
        details['bbox_stable'] = True
    else:
        feedback_parts.append("Segment boundary may have changed")
        details['bbox_stable'] = False
    
    # ================================================================
    # CRITERION 7: VLM verification (10 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    vlm_score = 0
    vlm_feedback = "VLM not available"
    
    if query_vlm and traj:
        try:
            # Get trajectory frames to verify work was done
            frames = []
            if sample_trajectory_frames:
                frames = sample_trajectory_frames(traj, n=4)
            
            final_frame = None
            if get_final_screenshot:
                final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = frames + ([final_frame] if final_frame else [])
                
                vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging task.

The task was to fill internal holes in a lung segmentation using the Segment Editor.

Look for evidence of:
1. Segment Editor interface visible (tool panel on left)
2. Smoothing effect being used (or similar morphological operation)
3. A lung segmentation visible (green or colored region in the slice views)
4. The segmentation appearing solid/filled (no dark spots inside the colored region)

Respond in JSON format:
{
    "segment_editor_visible": true/false,
    "segmentation_visible": true/false,
    "segment_appears_solid": true/false,
    "smoothing_tool_used": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames[:5])
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    segment_visible = parsed.get('segmentation_visible', False)
                    appears_solid = parsed.get('segment_appears_solid', False)
                    editor_visible = parsed.get('segment_editor_visible', False)
                    
                    if appears_solid and segment_visible:
                        vlm_score = w_vlm
                        vlm_feedback = "VLM: Segment appears solid and filled"
                    elif segment_visible:
                        vlm_score = w_vlm * 0.5
                        vlm_feedback = "VLM: Segmentation visible"
                    elif editor_visible:
                        vlm_score = w_vlm * 0.3
                        vlm_feedback = "VLM: Segment Editor was used"
                    else:
                        vlm_feedback = "VLM: Could not confirm solid segment"
                    
                    details['vlm_analysis'] = parsed
                else:
                    vlm_feedback = "VLM query failed"
            else:
                vlm_feedback = "No trajectory frames available"
                
        except Exception as e:
            vlm_feedback = f"VLM error: {str(e)[:50]}"
            logger.warning(f"VLM verification failed: {e}")
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Final scoring
    # ================================================================
    
    # Key criteria for passing
    volume_increased = volume_change_pct >= min_increase or details.get('volume_increased') == 'partial'
    key_criteria_met = output_exists and volume_increased
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Clamp score to 0-100
    score = max(0, min(100, int(score)))
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }