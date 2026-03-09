#!/usr/bin/env python3
"""
Verifier for Boolean Segment Subtraction Task.

Checks that NecroticCore was correctly subtracted from WholeTumor.

VERIFICATION CRITERIA:
1. Segment was modified (20 points) - WholeTumor voxel count changed
2. Subtraction applied (25 points) - Volume decreased (not increased)
3. Volume accurate (25 points) - Result within 5% of expected
4. No overlap (20 points) - Modified segment doesn't overlap with NecroticCore
5. Visual confirmation (10 points) - VLM confirms operation completed

Pass threshold: 70 points with subtraction_applied AND volume_accurate met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_subtract_segment_boolean(traj, env_info, task_info):
    """
    Verify the segment boolean subtraction task.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info including copy_from_env function
        task_info: Task metadata
    
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    results = {
        "score": 0.0,
        "max_score": 100.0,
        "passed": False,
        "criteria": {},
        "feedback": []
    }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    w_segment_modified = weights.get('segment_modified', 20)
    w_subtraction = weights.get('subtraction_applied', 25)
    w_volume = weights.get('volume_accurate', 25)
    w_overlap = weights.get('no_overlap', 20)
    w_visual = weights.get('visual_confirmation', 10)
    volume_tolerance = metadata.get('volume_tolerance_percent', 5.0)

    # ============================================================
    # Load task result from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        copy_from_env("/tmp/task_result/result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except FileNotFoundError:
        results["feedback"].append("Task result file not found - export may have failed")
        return {"passed": False, "score": 0, "feedback": "Task result file not found"}
    except json.JSONDecodeError as e:
        results["feedback"].append(f"Invalid JSON in result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        results["feedback"].append(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ============================================================
    # Load ground truth from container
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env("/tmp/task_result/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        results["feedback"].append(f"Warning: Ground truth unavailable: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # ============================================================
    # Check basic prerequisites
    # ============================================================
    if not task_result.get('slicer_running', False):
        results["feedback"].append("3D Slicer was not running")
        return {"passed": False, "score": 0, "feedback": "3D Slicer was not running"}

    if not task_result.get('segmentation_found', False):
        results["feedback"].append("No segmentation found in scene")
        return {"passed": False, "score": 0, "feedback": "No segmentation found"}

    total_score = 0.0

    # Get values from results
    original_whole_tumor_voxels = ground_truth.get("whole_tumor_voxels", 0)
    necrotic_voxels = ground_truth.get("necrotic_voxels", 0)
    expected_viable_voxels = ground_truth.get("expected_viable_voxels", 0)
    
    # If ground truth is missing key values, estimate from what we have
    if expected_viable_voxels == 0 and original_whole_tumor_voxels > 0 and necrotic_voxels > 0:
        expected_viable_voxels = original_whole_tumor_voxels - necrotic_voxels

    current_whole_tumor_voxels = task_result.get("whole_tumor_voxels", 0)
    overlap_voxels = task_result.get("overlap_voxels", -1)

    # ============================================================
    # Criterion 1: Segment was modified (w_segment_modified points)
    # ============================================================
    segment_modified = (
        task_result.get("whole_tumor_found", False) and
        current_whole_tumor_voxels != original_whole_tumor_voxels and
        current_whole_tumor_voxels > 0
    )

    if segment_modified:
        total_score += w_segment_modified
        results["criteria"]["segment_modified"] = {
            "passed": True,
            "points": w_segment_modified,
            "message": f"WholeTumor modified: {original_whole_tumor_voxels} → {current_whole_tumor_voxels} voxels"
        }
        results["feedback"].append(f"✓ WholeTumor segment modified ({original_whole_tumor_voxels} → {current_whole_tumor_voxels} voxels)")
    else:
        results["criteria"]["segment_modified"] = {
            "passed": False,
            "points": 0,
            "message": "WholeTumor segment not modified"
        }
        results["feedback"].append("✗ WholeTumor segment was not modified")

    # ============================================================
    # Criterion 2: Subtraction was applied (volume decreased)
    # ============================================================
    volume_decreased = current_whole_tumor_voxels < original_whole_tumor_voxels

    if volume_decreased:
        total_score += w_subtraction
        reduction = original_whole_tumor_voxels - current_whole_tumor_voxels
        results["criteria"]["subtraction_applied"] = {
            "passed": True,
            "points": w_subtraction,
            "message": f"Volume decreased by {reduction} voxels"
        }
        results["feedback"].append(f"✓ Subtraction applied - volume reduced by {reduction} voxels")
    else:
        results["criteria"]["subtraction_applied"] = {
            "passed": False,
            "points": 0,
            "message": "Volume did not decrease"
        }
        if current_whole_tumor_voxels > original_whole_tumor_voxels:
            results["feedback"].append("✗ Volume INCREASED - wrong operation applied")
        else:
            results["feedback"].append("✗ Volume unchanged - subtraction not applied")

    # ============================================================
    # Criterion 3: Volume is accurate (within tolerance)
    # ============================================================
    if expected_viable_voxels > 0:
        tolerance_voxels = expected_viable_voxels * (volume_tolerance / 100.0)
        volume_error = abs(current_whole_tumor_voxels - expected_viable_voxels)
        volume_accurate = volume_error <= tolerance_voxels
        error_percent = (volume_error / expected_viable_voxels * 100) if expected_viable_voxels > 0 else 100

        if volume_accurate:
            total_score += w_volume
            results["criteria"]["volume_accurate"] = {
                "passed": True,
                "points": w_volume,
                "message": f"Volume {current_whole_tumor_voxels} within {volume_tolerance}% of expected {expected_viable_voxels}"
            }
            results["feedback"].append(f"✓ Volume accurate: {current_whole_tumor_voxels} ≈ {expected_viable_voxels} (±{volume_tolerance}%)")
        else:
            # Partial credit for close values
            if error_percent < 15:
                partial = int(w_volume * 0.5)
                total_score += partial
                results["criteria"]["volume_accurate"] = {
                    "passed": False,
                    "points": partial,
                    "message": f"Volume {current_whole_tumor_voxels} differs by {error_percent:.1f}% (partial credit)"
                }
            else:
                results["criteria"]["volume_accurate"] = {
                    "passed": False,
                    "points": 0,
                    "message": f"Volume {current_whole_tumor_voxels} differs from expected {expected_viable_voxels} by {error_percent:.1f}%"
                }
            results["feedback"].append(f"✗ Volume inaccurate: {current_whole_tumor_voxels} vs expected {expected_viable_voxels} ({error_percent:.1f}% error)")
    else:
        results["criteria"]["volume_accurate"] = {
            "passed": False,
            "points": 0,
            "message": "Could not verify volume accuracy (missing ground truth)"
        }
        results["feedback"].append("○ Could not verify volume accuracy")

    # ============================================================
    # Criterion 4: No overlap with NecroticCore
    # ============================================================
    if overlap_voxels == 0:
        total_score += w_overlap
        results["criteria"]["no_overlap"] = {
            "passed": True,
            "points": w_overlap,
            "message": "No overlap - necrotic region fully removed"
        }
        results["feedback"].append("✓ No overlap - necrotic region completely removed from WholeTumor")
    elif overlap_voxels > 0:
        # Partial credit if overlap is small
        if necrotic_voxels > 0:
            overlap_fraction = overlap_voxels / necrotic_voxels
            if overlap_fraction < 0.1:
                partial = int(w_overlap * 0.5)
                total_score += partial
                results["criteria"]["no_overlap"] = {
                    "passed": False,
                    "points": partial,
                    "message": f"Small overlap: {overlap_voxels} voxels ({overlap_fraction*100:.1f}% of necrotic)"
                }
            else:
                results["criteria"]["no_overlap"] = {
                    "passed": False,
                    "points": 0,
                    "message": f"Significant overlap: {overlap_voxels} voxels ({overlap_fraction*100:.1f}% of necrotic)"
                }
        else:
            results["criteria"]["no_overlap"] = {
                "passed": False,
                "points": 0,
                "message": f"Overlap detected: {overlap_voxels} voxels"
            }
        results["feedback"].append(f"✗ Overlap detected: {overlap_voxels} voxels still overlap with NecroticCore")
    else:
        results["criteria"]["no_overlap"] = {
            "passed": False,
            "points": 0,
            "message": "Could not determine overlap (query failed)"
        }
        results["feedback"].append("○ Could not verify overlap status")

    # ============================================================
    # Criterion 5: Visual confirmation (VLM or screenshot check)
    # ============================================================
    screenshot_exists = task_result.get("screenshot_exists", False)
    
    # Try VLM verification on trajectory if available
    vlm_confirmed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=3)
        
        if frames:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.
The task was to use Segment Editor's Logical Operators to subtract one segment from another.

Look for evidence that:
1. The Segment Editor module is visible
2. The Logical operators effect was used (look for the effects panel)
3. A segmentation with tumor regions is visible
4. The operation was applied (look for Apply button or changed visualization)

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "logical_operators_used": true/false,
    "segmentation_visible": true/false,
    "operation_appears_complete": true/false,
    "confidence": "low"/"medium"/"high"
}"""
            
            result = query_vlm(prompt=vlm_prompt, images=frames)
            if result.get("success"):
                parsed = result.get("parsed", {})
                if (parsed.get("logical_operators_used", False) or 
                    parsed.get("operation_appears_complete", False)):
                    vlm_confirmed = True
                    
    except ImportError:
        logger.info("VLM not available, using screenshot-based check")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Award visual confirmation points
    if vlm_confirmed:
        total_score += w_visual
        results["criteria"]["visual_confirmation"] = {
            "passed": True,
            "points": w_visual,
            "message": "VLM confirmed operation was performed"
        }
        results["feedback"].append("✓ Visual confirmation: Logical operators effect used")
    elif screenshot_exists and volume_decreased and (overlap_voxels == 0 or overlap_voxels == -1):
        # Award points if other evidence is strong
        total_score += w_visual
        results["criteria"]["visual_confirmation"] = {
            "passed": True,
            "points": w_visual,
            "message": "Screenshot captured, task appears complete"
        }
        results["feedback"].append("✓ Visual confirmation: screenshot shows completed state")
    else:
        results["criteria"]["visual_confirmation"] = {
            "passed": False,
            "points": 0,
            "message": "Could not visually confirm operation"
        }
        results["feedback"].append("○ Visual confirmation unavailable")

    # ============================================================
    # Anti-gaming checks
    # ============================================================
    task_start = task_result.get("task_start_time", 0)
    task_end = task_result.get("task_end_time", 0)
    
    if task_start > 0 and task_end > 0:
        elapsed = task_end - task_start
        if elapsed < 5:
            results["feedback"].append("⚠ Warning: Task completed suspiciously fast")
        results["criteria"]["time_elapsed"] = {
            "value": elapsed,
            "message": f"Task took {elapsed} seconds"
        }

    # ============================================================
    # Final score calculation
    # ============================================================
    results["score"] = total_score
    
    # Pass requirements:
    # - Score >= 70 AND
    # - Subtraction was applied (volume decreased) AND
    # - Volume is reasonably accurate (within tolerance or close)
    subtraction_ok = results["criteria"].get("subtraction_applied", {}).get("passed", False)
    volume_ok = results["criteria"].get("volume_accurate", {}).get("passed", False)
    volume_partial = results["criteria"].get("volume_accurate", {}).get("points", 0) > 0
    
    results["passed"] = (
        total_score >= 70 and
        subtraction_ok and
        (volume_ok or volume_partial)
    )

    # Summary feedback
    results["feedback"].append(f"\nFinal Score: {total_score}/100")
    if results["passed"]:
        results["feedback"].append("PASSED: Boolean subtraction completed successfully!")
    else:
        if not subtraction_ok:
            results["feedback"].append("FAILED: Subtraction operation was not performed correctly")
        elif not (volume_ok or volume_partial):
            results["feedback"].append("FAILED: Result volume does not match expected")
        else:
            results["feedback"].append("FAILED: Score below threshold")

    return {
        "passed": results["passed"],
        "score": int(results["score"]),
        "feedback": " | ".join(results["feedback"]),
        "details": results
    }


if __name__ == "__main__":
    # For testing
    import sys
    print("Verifier module loaded. Run via framework for actual verification.")