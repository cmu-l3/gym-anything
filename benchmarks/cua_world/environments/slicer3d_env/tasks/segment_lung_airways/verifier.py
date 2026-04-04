#!/usr/bin/env python3
"""
Verifier for Segment Lung Airways task.

VERIFICATION STRATEGY (Multi-Signal Hybrid):

Programmatic checks (85 points):
1. Segmentation file exists (15 pts)
2. Correct file location (10 pts)
3. Volume in valid anatomical range 50-300 mL (20 pts)
4. Airways isolated - few connected components (15 pts)
5. Centroid in mediastinal region (15 pts)
6. Air density confirmed (10 pts)

VLM checks (15 points):
7. Trajectory shows workflow progression (10 pts)
8. 3D visualization visible (5 pts)

Anti-gaming:
- File must be created DURING the task (timestamp check)
- Centroid must be central (not external air at edges)
- Volume must be anatomically plausible

Pass threshold: 60 points AND airways_isolated criterion met
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_segment_lung_airways(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the Segment Lung Airways task completion.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info including copy_from_env function
        task_info: Task metadata
        
    Returns:
        Dict with 'passed', 'score', 'feedback' keys
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
    volume_min = metadata.get('volume_ml_min', 50)
    volume_max = metadata.get('volume_ml_max', 300)
    max_components = metadata.get('max_components', 3)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('segmentation_exists', 15)
    w_location = weights.get('correct_location', 10)
    w_volume = weights.get('volume_valid', 20)
    w_isolated = weights.get('isolated_correctly', 15)
    w_central = weights.get('centroid_central', 15)
    w_density = weights.get('air_density', 10)
    w_vlm_3d = weights.get('vlm_3d_visible', 10)
    w_vlm_workflow = weights.get('vlm_workflow', 5)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info("Successfully loaded task result JSON")
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
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
    
    details['result_data'] = result
    
    # ================================================================
    # Check 1: Segmentation file exists (15 points)
    # ================================================================
    seg_exists = result.get('segmentation_exists', False)
    
    if seg_exists:
        score += w_exists
        feedback_parts.append(f"✓ Segmentation file created (+{w_exists})")
        details['segmentation_exists'] = True
    else:
        feedback_parts.append("✗ Segmentation file NOT found")
        details['segmentation_exists'] = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + "\n\nNo segmentation was saved. Ensure you save to the specified path.",
            "details": details
        }
    
    # ================================================================
    # Check 2: Correct file location (10 points)
    # ================================================================
    expected_path = "/home/ga/Documents/SlicerData/Exports/airways_segmentation.seg.nrrd"
    actual_path = result.get('segmentation_file', '')
    
    if actual_path == expected_path:
        score += w_location
        feedback_parts.append(f"✓ Correct file location (+{w_location})")
        details['correct_location'] = True
    elif actual_path and 'airways' in actual_path.lower():
        # Partial credit for reasonable location
        partial = w_location // 2
        score += partial
        feedback_parts.append(f"△ File saved to alternate location (+{partial})")
        details['correct_location'] = 'partial'
    else:
        feedback_parts.append("✗ File not in expected location")
        details['correct_location'] = False
    
    # ================================================================
    # Check 3: Anti-gaming - File created during task
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if not file_created_during_task:
        # Major penalty - likely pre-existing file
        penalty = 30
        score = max(0, score - penalty)
        feedback_parts.append(f"⚠ File timestamp issue - may predate task (-{penalty})")
        details['anti_gaming_failed'] = True
    else:
        details['anti_gaming_failed'] = False
    
    # ================================================================
    # Check 4: Volume in valid anatomical range (20 points)
    # ================================================================
    volume_ml = result.get('volume_ml', 0)
    details['volume_ml'] = volume_ml
    
    if volume_min <= volume_ml <= volume_max:
        score += w_volume
        feedback_parts.append(f"✓ Volume anatomically plausible ({volume_ml:.1f} mL) (+{w_volume})")
        details['volume_valid'] = True
    elif volume_ml > 0:
        # Some segmentation exists but wrong size
        if volume_ml < volume_min:
            feedback_parts.append(f"△ Volume too small ({volume_ml:.1f} mL < {volume_min} mL expected)")
            partial = w_volume // 3
            score += partial
        else:
            # Volume too large - likely includes external air
            feedback_parts.append(f"✗ Volume too large ({volume_ml:.1f} mL > {volume_max} mL) - may include external air")
        details['volume_valid'] = False
    else:
        feedback_parts.append("✗ Zero or invalid volume")
        details['volume_valid'] = False
    
    # ================================================================
    # Check 5: Airways isolated - few connected components (15 points)
    # ================================================================
    num_components = result.get('num_components', 999)
    details['num_components'] = num_components
    
    airways_isolated = num_components <= max_components
    
    if airways_isolated:
        score += w_isolated
        feedback_parts.append(f"✓ Airways properly isolated ({num_components} component(s)) (+{w_isolated})")
        details['isolated_correctly'] = True
    else:
        feedback_parts.append(f"✗ Too many components ({num_components}) - external air likely included")
        details['isolated_correctly'] = False
    
    # ================================================================
    # Check 6: Centroid in mediastinal region (15 points)
    # ================================================================
    is_central = result.get('is_central', False)
    details['is_central'] = is_central
    
    if is_central:
        score += w_central
        feedback_parts.append(f"✓ Segmentation centered in chest (+{w_central})")
    else:
        feedback_parts.append("✗ Segmentation not centered - may include edge regions")
    
    # ================================================================
    # Check 7: Air density (10 points)
    # Inferred from valid volume + isolation
    # ================================================================
    if details.get('volume_valid') and airways_isolated:
        score += w_density
        feedback_parts.append(f"✓ Air density threshold correctly applied (+{w_density})")
        details['air_density_correct'] = True
    else:
        details['air_density_correct'] = False
    
    # ================================================================
    # Check 8: VLM Verification - Trajectory Analysis (15 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Get trajectory frames for workflow verification
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample 5 frames across the trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if trajectory_frames or final_frame:
                # Analyze trajectory for workflow progression
                workflow_prompt = """Analyze these screenshots from a medical image segmentation task in 3D Slicer.

The agent was asked to segment lung airways from a chest CT scan.

Look for evidence of:
1. Segment Editor module being used (panel on left with segment list)
2. Threshold effect being applied (threshold slider or threshold markers visible)
3. Islands effect or selection operation (isolating connected regions)
4. 3D visualization of airways (tubular branching structure in 3D view)
5. Save dialog or successful save indication

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "threshold_applied": true/false,
    "isolation_performed": true/false,
    "3d_airways_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low/medium/high",
    "observations": "brief description"
}"""
                
                all_frames = (trajectory_frames or []) + ([final_frame] if final_frame else [])
                
                if all_frames:
                    vlm_result = query_vlm(prompt=workflow_prompt, images=all_frames[:6])
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        # Score based on VLM findings
                        if parsed.get('segment_editor_visible'):
                            vlm_score += 3
                        if parsed.get('threshold_applied'):
                            vlm_score += 2
                        if parsed.get('isolation_performed'):
                            vlm_score += 3
                        if parsed.get('3d_airways_visible'):
                            vlm_score += 5
                        if parsed.get('workflow_progression'):
                            vlm_score += 2
                        
                        vlm_score = min(vlm_score, w_vlm_3d + w_vlm_workflow)
                        details['vlm_analysis'] = parsed
                        
        except ImportError:
            logger.warning("VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM analysis failed: {e}")
    
    # Apply VLM score or give partial credit if VLM unavailable
    if vlm_score > 0:
        score += vlm_score
        feedback_parts.append(f"✓ Visual verification positive (+{vlm_score})")
    elif seg_exists and airways_isolated:
        # Award partial VLM points if file checks passed but VLM unavailable
        partial_vlm = 5
        score += partial_vlm
        feedback_parts.append(f"△ VLM unavailable, partial visual credit (+{partial_vlm})")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Calculate final result
    # ================================================================
    # Normalize score to 0-100
    score = min(max(score, 0), max_score)
    
    # Determine pass/fail
    # Must have 60+ points AND airways must be properly isolated (key criterion)
    passed = score >= 60 and airways_isolated
    
    details['final_score'] = score
    details['max_score'] = max_score
    details['airways_isolated'] = airways_isolated
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nFinal Score: {score}/{max_score}"
    feedback += f"\nKey Criterion (Airways Isolated): {'MET' if airways_isolated else 'NOT MET'}"
    feedback += f"\nResult: {'PASSED' if passed else 'FAILED'}"
    
    if not passed:
        if not airways_isolated:
            feedback += "\n\n💡 Tip: Use the Islands effect with 'Keep selected island' "
            feedback += "after clicking inside the trachea to remove external air."
        elif score < 60:
            feedback += "\n\n💡 Tip: Ensure the segmentation is saved to the correct path "
            feedback += "and represents anatomically plausible airways (50-300 mL)."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }