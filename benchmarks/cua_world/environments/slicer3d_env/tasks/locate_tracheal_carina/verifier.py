#!/usr/bin/env python3
"""
Verifier for locate_tracheal_carina task.

VERIFICATION CRITERIA:
1. Fiducial Exists (20 points) - A point markup was created
2. Named Correctly (10 points) - Fiducial is named "Carina"
3. Z-Coordinate Valid (20 points) - Within expected superior-inferior range
4. XY-Coordinate Valid (15 points) - Near midline and in mediastinum
5. Airway Adjacent VLM (20 points) - VLM confirms marker at airway bifurcation
6. Distance from GT (15 points) - Within 10-20mm of computed ground truth

Pass threshold: 70 points with fiducial existing
"""

import json
import os
import math
import tempfile
import logging
from typing import Tuple, Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_locate_tracheal_carina(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify the tracheal carina localization task.
    
    Uses multi-criteria scoring with programmatic coordinate validation
    and VLM verification of trajectory frames.
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
    scoring_weights = metadata.get('scoring_weights', {})
    
    w_fiducial_exists = scoring_weights.get('fiducial_exists', 20)
    w_named_correctly = scoring_weights.get('named_correctly', 10)
    w_z_valid = scoring_weights.get('z_coordinate_valid', 20)
    w_xy_valid = scoring_weights.get('xy_coordinate_valid', 15)
    w_vlm = scoring_weights.get('airway_adjacent_vlm', 20)
    w_distance = scoring_weights.get('distance_from_gt', 15)
    
    dist_excellent = metadata.get('distance_threshold_excellent_mm', 10)
    dist_good = metadata.get('distance_threshold_good_mm', 15)
    dist_acceptable = metadata.get('distance_threshold_acceptable_mm', 20)

    score = 0
    max_score = 100
    feedback_parts = []
    details = {}

    # ================================================================
    # Load result data from container
    # ================================================================
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metrics = result_data.get('metrics', {})
    fiducial_data = result_data.get('fiducial_data', {})
    gt_data = result_data.get('ground_truth', {})
    
    details['metrics'] = metrics
    details['has_ground_truth'] = bool(gt_data and 'carina_ras' in gt_data)

    # Check anti-gaming: task duration
    task_duration = metrics.get('task_duration_seconds', 0)
    if task_duration < 10:
        feedback_parts.append("WARNING: Task completed suspiciously fast")
        details['suspicious_timing'] = True

    # ================================================================
    # Criterion 1: Fiducial Exists (20 points)
    # ================================================================
    fiducial_exists = metrics.get('fiducial_exists', False)
    num_fiducials = metrics.get('num_fiducials', 0)
    
    if fiducial_exists and num_fiducials > 0:
        score += w_fiducial_exists
        feedback_parts.append(f"✓ Fiducial marker created ({num_fiducials} total)")
        details['fiducial_exists'] = True
    else:
        feedback_parts.append("✗ No fiducial markers found - task incomplete")
        details['fiducial_exists'] = False
        # Cannot pass without fiducials
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # Criterion 2: Named Correctly (10 points)
    # ================================================================
    carina_named = metrics.get('carina_named_correctly', False)
    carina_fid = fiducial_data.get('carina_fiducial')
    
    if carina_named and carina_fid:
        score += w_named_correctly
        node_name = carina_fid.get('node_name', '')
        point_label = carina_fid.get('point_label', '')
        feedback_parts.append(f"✓ Fiducial named 'Carina' found")
        details['correctly_named'] = True
    else:
        feedback_parts.append("✗ No fiducial named 'Carina' found")
        details['correctly_named'] = False
        
        # Use first available fiducial for remaining checks
        fiducials = fiducial_data.get('fiducials_found', [])
        if fiducials:
            carina_fid = fiducials[0]
            feedback_parts.append(f"  (Using first fiducial for position validation)")

    # Get position for remaining checks
    carina_pos = None
    if carina_fid:
        carina_pos = carina_fid.get('position_ras')
    elif metrics.get('carina_position_ras'):
        carina_pos = metrics['carina_position_ras']
    
    details['carina_position'] = carina_pos
    
    if not carina_pos:
        feedback_parts.append("✗ Could not determine fiducial position")
        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # Criterion 3: Z-Coordinate Valid (20 points)
    # ================================================================
    z_valid = metrics.get('z_coordinate_valid', False)
    
    if z_valid:
        score += w_z_valid
        feedback_parts.append(f"✓ Z-coordinate within expected range")
        details['z_valid'] = True
    else:
        # Manual validation if metrics didn't compute it
        if gt_data and 'bounds_min_ras' in gt_data:
            bounds_min = gt_data.get('bounds_min_ras', [-1000, -1000, -1000])
            bounds_max = gt_data.get('bounds_max_ras', [1000, 1000, 1000])
            
            if bounds_min[2] <= carina_pos[2] <= bounds_max[2]:
                score += w_z_valid
                feedback_parts.append(f"✓ Z-coordinate {carina_pos[2]:.1f} within range")
                details['z_valid'] = True
            else:
                feedback_parts.append(f"✗ Z-coordinate {carina_pos[2]:.1f} outside range [{bounds_min[2]:.1f}, {bounds_max[2]:.1f}]")
                details['z_valid'] = False
        else:
            feedback_parts.append("~ Cannot validate Z-coordinate (no ground truth bounds)")
            details['z_valid'] = None

    # ================================================================
    # Criterion 4: XY-Coordinate Valid (15 points)
    # ================================================================
    xy_valid = metrics.get('xy_coordinate_valid', False)
    
    if xy_valid:
        score += w_xy_valid
        feedback_parts.append(f"✓ XY-coordinates within mediastinum bounds")
        details['xy_valid'] = True
    else:
        if gt_data and 'bounds_min_ras' in gt_data:
            bounds_min = gt_data.get('bounds_min_ras', [-1000, -1000, -1000])
            bounds_max = gt_data.get('bounds_max_ras', [1000, 1000, 1000])
            
            in_x = bounds_min[0] <= carina_pos[0] <= bounds_max[0]
            in_y = bounds_min[1] <= carina_pos[1] <= bounds_max[1]
            
            if in_x and in_y:
                score += w_xy_valid
                feedback_parts.append(f"✓ XY-coordinates within mediastinum")
                details['xy_valid'] = True
            else:
                feedback_parts.append(f"✗ XY-coordinates outside expected range")
                details['xy_valid'] = False
        else:
            feedback_parts.append("~ Cannot validate XY-coordinates (no ground truth)")
            details['xy_valid'] = None

    # ================================================================
    # Criterion 5: VLM Airway Adjacent (20 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Sample trajectory frames for process verification
            trajectory_images = traj.get('images', []) if isinstance(traj, dict) else []
            if not trajectory_images and hasattr(traj, 'images'):
                trajectory_images = traj.images
            
            # Use last few frames
            images_to_check = trajectory_images[-5:] if len(trajectory_images) > 5 else trajectory_images
            
            if images_to_check:
                vlm_prompt = """Examine these 3D Slicer screenshots showing chest CT imaging.

Look for:
1. Is there a fiducial marker (point/sphere/crosshair) visible on the images?
2. Is the marker placed at or near the tracheal bifurcation (carina)?
3. Can you see the trachea (dark tube) splitting into two bronchi near the marker?

The carina is where the trachea divides into left and right main bronchi.
- In axial view: appears as a Y-shape of dark (air) in the center of the chest
- In coronal view: appears as an inverted-V or Y-shape

Respond in JSON format:
{
    "fiducial_visible": true/false,
    "appears_at_bifurcation": true/false,
    "airway_anatomy_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
                
                vlm_response = query_vlm(prompt=vlm_prompt, images=images_to_check)
                
                vlm_result = {}
                if vlm_response and vlm_response.get('success'):
                    vlm_result = vlm_response.get('parsed', {})
                    if not vlm_result and 'response' in vlm_response:
                        # Try to parse from raw response
                        import re
                        raw = vlm_response.get('response', '')
                        json_match = re.search(r'\{[^{}]*\}', raw, re.DOTALL)
                        if json_match:
                            try:
                                vlm_result = json.loads(json_match.group())
                            except:
                                pass
                
                details['vlm_analysis'] = vlm_result
                
                if vlm_result.get('fiducial_visible') and vlm_result.get('appears_at_bifurcation'):
                    vlm_score = w_vlm
                    feedback_parts.append("✓ VLM confirms marker at airway bifurcation")
                elif vlm_result.get('fiducial_visible'):
                    vlm_score = int(w_vlm * 0.5)
                    feedback_parts.append("~ VLM sees marker but uncertain about bifurcation")
                elif vlm_result.get('airway_anatomy_visible'):
                    vlm_score = int(w_vlm * 0.25)
                    feedback_parts.append("~ VLM sees airway but cannot confirm marker location")
                else:
                    feedback_parts.append("✗ VLM cannot confirm marker at airway")
            else:
                feedback_parts.append("~ No trajectory images for VLM verification")
                # Give partial credit based on coordinate validation
                if details.get('z_valid') and details.get('xy_valid'):
                    vlm_score = int(w_vlm * 0.5)
                    feedback_parts.append("  (Partial credit from coordinate validation)")
                    
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"~ VLM check failed: {str(e)[:50]}")
            # Give partial credit based on coordinates
            if details.get('z_valid') and details.get('xy_valid'):
                vlm_score = int(w_vlm * 0.5)
    else:
        # No VLM available - give partial credit based on coordinate validation
        if details.get('z_valid') and details.get('xy_valid'):
            vlm_score = int(w_vlm * 0.5)
            feedback_parts.append("~ Airway adjacency estimated from coordinates (no VLM)")
        else:
            feedback_parts.append("~ No VLM available for verification")
    
    score += vlm_score
    details['vlm_score'] = vlm_score

    # ================================================================
    # Criterion 6: Distance from Ground Truth (15 points)
    # ================================================================
    distance = metrics.get('distance_from_gt_mm')
    
    if distance is not None:
        details['distance_mm'] = distance
        
        if distance <= dist_excellent:
            score += w_distance
            feedback_parts.append(f"✓ Excellent accuracy: {distance:.1f}mm from ground truth")
        elif distance <= dist_good:
            dist_score = int(w_distance * 0.7)
            score += dist_score
            feedback_parts.append(f"~ Good accuracy: {distance:.1f}mm from ground truth")
        elif distance <= dist_acceptable:
            dist_score = int(w_distance * 0.4)
            score += dist_score
            feedback_parts.append(f"~ Acceptable accuracy: {distance:.1f}mm from ground truth")
        else:
            feedback_parts.append(f"✗ Poor accuracy: {distance:.1f}mm from ground truth (>{dist_acceptable}mm)")
    else:
        feedback_parts.append("~ Could not compute distance from ground truth")

    # ================================================================
    # Final Results
    # ================================================================
    details['score'] = score
    details['max_score'] = max_score
    details['percentage'] = round(100 * score / max_score, 1)
    
    # Determine pass/fail
    # Must have fiducial and score >= 70
    passed = score >= 70 and fiducial_exists
    
    if passed:
        feedback_parts.append(f"\n✓ PASSED: {score}/{max_score} points ({details['percentage']}%)")
    else:
        feedback_parts.append(f"\n✗ FAILED: {score}/{max_score} points ({details['percentage']}%)")
        if not fiducial_exists:
            feedback_parts.append("  Must create at least one fiducial marker")
        else:
            feedback_parts.append("  Need at least 70 points to pass")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test with sample data
    sample_result = {
        "metrics": {
            "task_duration_seconds": 180,
            "slicer_running": True,
            "fiducial_exists": True,
            "carina_named_correctly": True,
            "num_fiducials": 1,
            "z_coordinate_valid": True,
            "xy_coordinate_valid": True,
            "distance_from_gt_mm": 8.5,
            "carina_position_ras": [-5.2, -45.3, -122.8]
        },
        "fiducial_data": {
            "fiducials_found": [{
                "node_name": "Carina",
                "point_label": "Carina",
                "position_ras": [-5.2, -45.3, -122.8]
            }],
            "carina_fiducial": {
                "node_name": "Carina",
                "point_label": "Carina",
                "position_ras": [-5.2, -45.3, -122.8]
            }
        },
        "ground_truth": {
            "carina_ras": [-3.1, -42.5, -118.5],
            "bounds_min_ras": [-18.1, -57.5, -138.5],
            "bounds_max_ras": [11.9, -27.5, -98.5]
        }
    }
    
    # Mock env_info and task_info
    class MockEnv:
        @staticmethod
        def copy_from_env(src, dst):
            import json
            with open(dst, 'w') as f:
                json.dump(sample_result, f)
    
    env_info = {'copy_from_env': MockEnv.copy_from_env}
    task_info = {'metadata': {}}
    
    result = verify_locate_tracheal_carina({}, env_info, task_info)
    print(f"Passed: {result['passed']}")
    print(f"Score: {result['score']}")
    print(f"\nFeedback:\n{result['feedback']}")