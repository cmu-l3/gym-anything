#!/usr/bin/env python3
"""
Verifier for mark_portal_bifurcation task.

VERIFICATION STRATEGY (Multi-criteria scoring):

1. Fiducial Exists (15 pts) - A fiducial marker was created
2. Appropriate Name (10 pts) - Fiducial named with portal/bifurcation
3. Correct Region (20 pts) - Fiducial within hepatic hilum area (±25mm)
4. Accurate Placement (35 pts) - Distance to ground truth ≤8mm
5. Near-Accurate Placement (20 pts) - Distance 8-15mm (partial, exclusive with accurate)
6. VLM Confirmation (20 pts) - Visual verification of workflow

Pass threshold: 65 points with fiducial_exists and (accurate or near_accurate)
"""

import json
import math
import os
import tempfile
import logging
from typing import Dict, Any, Tuple, Optional, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_distance(coords1: List[float], coords2: List[float]) -> float:
    """Calculate Euclidean distance between two 3D points."""
    if not coords1 or not coords2:
        return float('inf')
    if len(coords1) != 3 or len(coords2) != 3:
        return float('inf')
    try:
        return math.sqrt(sum((float(a) - float(b)) ** 2 for a, b in zip(coords1, coords2)))
    except (TypeError, ValueError):
        return float('inf')


def verify_fiducial_name(name: str) -> bool:
    """Check if fiducial name indicates portal bifurcation."""
    if not name:
        return False
    name_lower = name.lower()
    portal_terms = ['portal', 'pv', 'bifurc', 'branch', 'hilum', 'hepatic', 'vein']
    return any(term in name_lower for term in portal_terms)


def verify_mark_portal_bifurcation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the portal vein bifurcation marking task.
    
    Uses multiple independent signals:
    - Fiducial file existence and creation time
    - Coordinate accuracy against ground truth
    - VLM verification of workflow progression
    
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details'
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
    tolerance_mm = metadata.get('tolerance_mm', 8.0)
    acceptable_tolerance_mm = metadata.get('acceptable_tolerance_mm', 15.0)
    region_tolerance_mm = metadata.get('region_tolerance_mm', 25.0)
    
    weights = metadata.get('scoring_weights', {})
    w_fiducial_exists = weights.get('fiducial_exists', 15)
    w_appropriate_name = weights.get('appropriate_name', 10)
    w_correct_region = weights.get('correct_region', 20)
    w_accurate = weights.get('accurate_placement', 35)
    w_near_accurate = weights.get('near_accurate_placement', 20)
    w_vlm = weights.get('vlm_confirmation', 20)
    
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/portal_task_result.json", temp_result.name)
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
    # Check if Slicer was running
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - task not attempted"
        }
    
    details['slicer_running'] = True
    
    # ================================================================
    # CRITERION 1: Fiducial Exists (15 points)
    # ================================================================
    fiducial_exists = result.get('fiducial_exists', False)
    fiducial_created_during_task = result.get('fiducial_created_during_task', False)
    initial_existed = result.get('initial_fiducial_existed', False)
    
    if fiducial_exists:
        if fiducial_created_during_task or not initial_existed:
            score += w_fiducial_exists
            feedback_parts.append("Fiducial marker created")
        else:
            # Fiducial existed before task - give partial credit
            score += w_fiducial_exists * 0.5
            feedback_parts.append("Fiducial exists (may have been pre-existing)")
        details['fiducial_exists'] = True
    else:
        feedback_parts.append("No fiducial marker found")
        details['fiducial_exists'] = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": int(score),
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Appropriate Name (10 points)
    # ================================================================
    fiducial_name = result.get('fiducial_name', '')
    details['fiducial_name'] = fiducial_name
    
    if verify_fiducial_name(fiducial_name):
        score += w_appropriate_name
        feedback_parts.append(f"Appropriate name: '{fiducial_name}'")
    else:
        feedback_parts.append(f"Name '{fiducial_name}' doesn't indicate portal bifurcation")
    
    # ================================================================
    # CRITERION 3-5: Coordinate Accuracy
    # ================================================================
    fiducial_ras = result.get('fiducial_ras', [])
    gt_ras = result.get('ground_truth_ras', [])
    
    details['fiducial_ras'] = fiducial_ras
    details['ground_truth_ras'] = gt_ras
    
    # Try to get distance from export (already computed)
    distance_str = result.get('distance_to_gt_mm', '')
    distance = float('inf')
    
    if distance_str:
        try:
            distance = float(distance_str)
        except (ValueError, TypeError):
            pass
    
    # Fallback: compute distance ourselves
    if distance == float('inf') and fiducial_ras and gt_ras:
        distance = calculate_distance(fiducial_ras, gt_ras)
    
    details['distance_mm'] = distance if distance != float('inf') else None
    
    if distance != float('inf'):
        feedback_parts.append(f"Distance from target: {distance:.1f}mm")
        
        # Criterion 3: Correct Region (within 25mm)
        if distance <= region_tolerance_mm:
            score += w_correct_region
            feedback_parts.append("Within hepatic hilum region")
            details['correct_region'] = True
        else:
            feedback_parts.append("Outside expected hepatic hilum region")
            details['correct_region'] = False
        
        # Criterion 4: Accurate Placement (within 8mm)
        if distance <= tolerance_mm:
            score += w_accurate
            feedback_parts.append(f"Accurate placement (≤{tolerance_mm}mm)")
            details['accurate_placement'] = True
            details['near_accurate_placement'] = False
        # Criterion 5: Near-Accurate (8-15mm) - mutually exclusive with accurate
        elif distance <= acceptable_tolerance_mm:
            score += w_near_accurate
            feedback_parts.append(f"Near-accurate placement ({tolerance_mm}-{acceptable_tolerance_mm}mm)")
            details['accurate_placement'] = False
            details['near_accurate_placement'] = True
        else:
            feedback_parts.append(f"Placement too far from target (>{acceptable_tolerance_mm}mm)")
            details['accurate_placement'] = False
            details['near_accurate_placement'] = False
    else:
        feedback_parts.append("Could not compute distance to ground truth")
        details['correct_region'] = False
        details['accurate_placement'] = False
        details['near_accurate_placement'] = False
    
    # ================================================================
    # CRITERION 6: VLM Verification (20 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    # Try to use trajectory frames for VLM verification
    trajectory_frames = []
    if traj:
        # Sample frames from trajectory
        observations = traj.get('observations', [])
        if observations:
            # Sample up to 5 frames evenly distributed
            n_frames = min(5, len(observations))
            if n_frames > 0:
                step = max(1, len(observations) // n_frames)
                for i in range(0, len(observations), step):
                    if len(trajectory_frames) < n_frames:
                        obs = observations[i]
                        if isinstance(obs, dict) and 'screenshot' in obs:
                            trajectory_frames.append(obs['screenshot'])
                        elif isinstance(obs, str):
                            trajectory_frames.append(obs)
    
    if query_vlm and trajectory_frames:
        try:
            vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer where the user was asked to mark the portal vein bifurcation in a liver CT scan.

The portal vein is a blood vessel that appears as a bright tubular structure in contrast-enhanced CT. The bifurcation is where it splits into left and right branches.

Evaluate the workflow progression across these frames:
1. Was CT data loaded and visible? (abdominal anatomy visible)
2. Did the user navigate to find vascular structures? (scrolling through slices)
3. Is there a fiducial marker (small colored point/sphere) visible in later frames?
4. Does the marker appear to be placed at a vascular structure in the liver region?

Rate your confidence (0-100) that the task was completed correctly.

Respond in JSON:
{
    "ct_loaded": true/false,
    "navigation_observed": true/false,
    "fiducial_visible": true/false,
    "fiducial_at_vessel": true/false,
    "confidence": 0-100,
    "observations": "brief description"
}"""

            vlm_response = query_vlm(
                images=trajectory_frames,
                prompt=vlm_prompt
            )
            
            if vlm_response and vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                
                # Extract confidence
                vlm_confidence = 50  # default
                if isinstance(parsed, dict):
                    vlm_confidence = parsed.get('confidence', 50)
                    details['vlm_ct_loaded'] = parsed.get('ct_loaded', False)
                    details['vlm_fiducial_visible'] = parsed.get('fiducial_visible', False)
                    details['vlm_observations'] = parsed.get('observations', '')
                
                # Scale confidence to points
                vlm_score = min(w_vlm, vlm_confidence * w_vlm / 100)
                score += vlm_score
                feedback_parts.append(f"VLM verification: {vlm_confidence}% confidence")
                details['vlm_confidence'] = vlm_confidence
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # Fallback: give partial VLM credit if screenshot exists
    if vlm_score == 0 and result.get('screenshot_exists', False):
        vlm_score = w_vlm * 0.5
        score += vlm_score
        feedback_parts.append("Screenshot captured (partial visual credit)")
        details['vlm_fallback'] = True
    
    # ================================================================
    # Final scoring
    # ================================================================
    score = max(0, min(100, int(score)))
    
    # Determine pass/fail
    # Must have: fiducial exists AND (accurate OR near-accurate placement)
    placement_ok = details.get('accurate_placement', False) or details.get('near_accurate_placement', False)
    key_criteria_met = fiducial_exists and placement_ok
    
    passed = score >= 65 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


if __name__ == "__main__":
    # Test verification locally
    result = verify_mark_portal_bifurcation({}, {}, {})
    print(f"Score: {result['score']}")
    print(f"Passed: {result['passed']}")
    print(f"Feedback: {result['feedback']}")