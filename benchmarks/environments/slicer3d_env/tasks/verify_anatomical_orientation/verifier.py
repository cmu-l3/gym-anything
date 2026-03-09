#!/usr/bin/env python3
"""
Verifier for verify_anatomical_orientation task.

VERIFICATION STRATEGY (Multi-signal):

Programmatic checks (70 points):
  1. Liver fiducial exists (15 pts)
  2. Liver position correct - on patient's right side, R < 0 in RAS (15 pts)
  3. Spine fiducial exists (15 pts)
  4. Spine position correct - most posterior A coordinate (15 pts)
  5. Heart fiducial exists (15 pts)
  6. Heart position correct - in mediastinum, superior to liver (15 pts)
  7. Spatial relationships correct (10 pts)

VLM checks (30 points) - uses TRAJECTORY frames:
  8. Process verification (15 pts): Trajectory shows agent navigating slices
     and placing markers
  9. Visual confirmation (15 pts): Final screenshot shows fiducials on
     anatomical structures

Pass threshold: 70 points with at least 2 fiducials correctly placed
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_anatomical_orientation(traj, env_info, task_info):
    """
    Verify anatomical orientation task completion.

    Uses multi-criteria scoring with anatomical position validation.
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
    weights = metadata.get('scoring_weights', {})
    position_tolerance = metadata.get('position_tolerance_mm', 30)
    z_tolerance = metadata.get('z_tolerance_mm', 50)

    # Default weights
    w_liver_exists = weights.get('liver_fiducial_exists', 15)
    w_liver_pos = weights.get('liver_position_correct', 15)
    w_spine_exists = weights.get('spine_fiducial_exists', 15)
    w_spine_pos = weights.get('spine_position_correct', 15)
    w_heart_exists = weights.get('heart_fiducial_exists', 15)
    w_heart_pos = weights.get('heart_position_correct', 15)
    w_relationships = weights.get('spatial_relationships_correct', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/orientation_task_result.json", temp_result.name)
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

    # Copy reference data
    temp_ref = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    reference = {}
    try:
        copy_from_env("/tmp/orientation_reference.json", temp_ref.name)
        with open(temp_ref.name, 'r') as f:
            reference = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load reference: {e}")
        reference = {"has_ground_truth": False}
    finally:
        if os.path.exists(temp_ref.name):
            os.unlink(temp_ref.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        "reference": reference,
        "result": result
    }

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion",
            "details": details
        }

    # Check anti-gaming: fiducials should be created during task
    fiducials_created = result.get('fiducials_created_during_task', False)
    if not fiducials_created:
        # Still allow verification but note the issue
        feedback_parts.append("Note: Fiducials may have been pre-existing")

    # Get fiducial data
    fiducials = result.get('fiducials', {})
    liver_fid = fiducials.get('liver')
    spine_fid = fiducials.get('spine')
    heart_fid = fiducials.get('heart')

    # Helper function to check if position is within bounding box
    def position_in_bbox(pos, bbox, tolerance=30):
        """Check if position is within bounding box (with tolerance)."""
        if not bbox or 'center_ras' not in bbox:
            return True  # No reference, accept
        
        center = bbox['center_ras']
        extent = bbox.get('extent_mm', [100, 100, 100])
        
        for i in range(3):
            half_extent = extent[i] / 2.0 + tolerance
            if abs(pos[i] - center[i]) > half_extent:
                return False
        return True

    # ============================================================
    # CRITERION 1: Liver fiducial exists (15 pts)
    # ============================================================
    if liver_fid:
        score += w_liver_exists
        feedback_parts.append("Liver fiducial: EXISTS")
        details['liver_fiducial'] = liver_fid
    else:
        feedback_parts.append("Liver fiducial: MISSING")

    # ============================================================
    # CRITERION 2: Liver position correct (15 pts)
    # Liver should be on patient's RIGHT (R < 0 in RAS coordinates)
    # ============================================================
    if liver_fid:
        liver_pos = liver_fid.get('position_ras', [0, 0, 0])
        liver_r = liver_pos[0]
        
        # In RAS: R < 0 means patient's right side
        liver_on_right = liver_r < 0
        
        # Also check against reference bounding box
        liver_bbox = reference.get('liver_bbox')
        liver_in_bbox = position_in_bbox(liver_pos, liver_bbox, position_tolerance)
        
        if liver_on_right:
            if liver_in_bbox:
                score += w_liver_pos
                feedback_parts.append(f"Liver position: CORRECT (R={liver_r:.1f}mm, patient's right)")
            else:
                score += w_liver_pos * 0.5
                feedback_parts.append(f"Liver position: PARTIAL (R={liver_r:.1f}mm, right side but outside expected region)")
        else:
            feedback_parts.append(f"Liver position: WRONG (R={liver_r:.1f}mm, should be negative/right)")
        
        details['liver_position_correct'] = liver_on_right

    # ============================================================
    # CRITERION 3: Spine fiducial exists (15 pts)
    # ============================================================
    if spine_fid:
        score += w_spine_exists
        feedback_parts.append("Spine fiducial: EXISTS")
        details['spine_fiducial'] = spine_fid
    else:
        feedback_parts.append("Spine fiducial: MISSING")

    # ============================================================
    # CRITERION 4: Spine position correct (15 pts)
    # Spine should be POSTERIOR (most positive A coordinate in RAS)
    # ============================================================
    if spine_fid:
        spine_pos = spine_fid.get('position_ras', [0, 0, 0])
        spine_a = spine_pos[1]
        
        # Check if spine is posterior (positive A, or at least the most posterior)
        spine_bbox = reference.get('spine_bbox')
        spine_in_bbox = position_in_bbox(spine_pos, spine_bbox, position_tolerance)
        
        # Compare A coordinates - spine should be more posterior (higher A) than liver/heart
        is_posterior = True
        if liver_fid:
            liver_a = liver_fid.get('position_ras', [0, 0, 0])[1]
            if spine_a < liver_a - 10:  # Allow 10mm tolerance
                is_posterior = False
        
        if heart_fid:
            heart_a = heart_fid.get('position_ras', [0, 0, 0])[1]
            if spine_a < heart_a - 10:
                is_posterior = False
        
        if is_posterior and spine_in_bbox:
            score += w_spine_pos
            feedback_parts.append(f"Spine position: CORRECT (A={spine_a:.1f}mm, posterior)")
        elif is_posterior:
            score += w_spine_pos * 0.7
            feedback_parts.append(f"Spine position: ACCEPTABLE (A={spine_a:.1f}mm, most posterior)")
        else:
            feedback_parts.append(f"Spine position: WRONG (A={spine_a:.1f}mm, not posterior)")
        
        details['spine_position_correct'] = is_posterior

    # ============================================================
    # CRITERION 5: Heart fiducial exists (15 pts)
    # ============================================================
    if heart_fid:
        score += w_heart_exists
        feedback_parts.append("Heart fiducial: EXISTS")
        details['heart_fiducial'] = heart_fid
    else:
        feedback_parts.append("Heart fiducial: MISSING")

    # ============================================================
    # CRITERION 6: Heart position correct (15 pts)
    # Heart should be in mediastinum, superior to liver
    # ============================================================
    if heart_fid:
        heart_pos = heart_fid.get('position_ras', [0, 0, 0])
        heart_s = heart_pos[2]
        
        # Check if heart is superior to liver
        is_superior = True
        if liver_fid:
            liver_s = liver_fid.get('position_ras', [0, 0, 0])[2]
            is_superior = heart_s > liver_s - 20  # Allow some overlap
        
        # Check against reference bounding box
        heart_bbox = reference.get('heart_region')
        heart_in_bbox = position_in_bbox(heart_pos, heart_bbox, position_tolerance + 20)
        
        if is_superior:
            if heart_in_bbox:
                score += w_heart_pos
                feedback_parts.append(f"Heart position: CORRECT (S={heart_s:.1f}mm, superior)")
            else:
                score += w_heart_pos * 0.6
                feedback_parts.append(f"Heart position: PARTIAL (S={heart_s:.1f}mm, superior but outside expected region)")
        else:
            feedback_parts.append(f"Heart position: QUESTIONABLE (S={heart_s:.1f}mm)")
        
        details['heart_position_correct'] = is_superior

    # ============================================================
    # CRITERION 7: Spatial relationships correct (10 pts)
    # ============================================================
    relationships_correct = 0
    total_relationships = 0
    
    # Check liver-spine relationship (spine more posterior)
    if liver_fid and spine_fid:
        total_relationships += 1
        liver_a = liver_fid.get('position_ras', [0, 0, 0])[1]
        spine_a = spine_fid.get('position_ras', [0, 0, 0])[1]
        if spine_a > liver_a:
            relationships_correct += 1
    
    # Check liver-heart relationship (heart more superior)
    if liver_fid and heart_fid:
        total_relationships += 1
        liver_s = liver_fid.get('position_ras', [0, 0, 0])[2]
        heart_s = heart_fid.get('position_ras', [0, 0, 0])[2]
        if heart_s > liver_s - 30:  # Allow some overlap
            relationships_correct += 1
    
    # Check heart-spine relationship (spine more posterior)
    if heart_fid and spine_fid:
        total_relationships += 1
        heart_a = heart_fid.get('position_ras', [0, 0, 0])[1]
        spine_a = spine_fid.get('position_ras', [0, 0, 0])[1]
        if spine_a > heart_a:
            relationships_correct += 1
    
    if total_relationships > 0:
        relationship_score = (relationships_correct / total_relationships) * w_relationships
        score += int(relationship_score)
        feedback_parts.append(f"Spatial relationships: {relationships_correct}/{total_relationships} correct")
    else:
        feedback_parts.append("Spatial relationships: Not enough fiducials to verify")
    
    details['spatial_relationships'] = {
        'correct': relationships_correct,
        'total': total_relationships
    }

    # ============================================================
    # VLM VERIFICATION (Optional bonus - trajectory analysis)
    # ============================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Try to get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                # Prepare VLM prompt
                vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to verify CT scan orientation by placing fiducial markers on:
1. The liver (patient's right side)
2. The spine (posterior)
3. The heart (if visible)

Looking at these images, assess:
1. MARKERS_VISIBLE: Are fiducial markers (small colored dots/spheres) visible on the CT scan?
2. NAVIGATION_SHOWN: Do the images show the user navigating through different slices?
3. ANATOMICALLY_PLACED: Do the markers appear to be on appropriate anatomical structures?
4. SLICER_INTERFACE: Is this the 3D Slicer interface with CT data loaded?

Respond in JSON format:
{
    "markers_visible": true/false,
    "navigation_shown": true/false,
    "anatomically_placed": true/false,
    "slicer_interface": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                images_to_analyze = trajectory_frames if trajectory_frames else []
                if final_screenshot:
                    images_to_analyze.append(final_screenshot)
                
                if images_to_analyze:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_analyze)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_analysis'] = parsed
                        
                        # Award points based on VLM findings
                        if parsed.get('markers_visible'):
                            vlm_score += 10
                        if parsed.get('anatomically_placed'):
                            vlm_score += 10
                        if parsed.get('navigation_shown'):
                            vlm_score += 5
                        
                        feedback_parts.append(f"VLM analysis: markers_visible={parsed.get('markers_visible')}")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)

    # Cap VLM bonus at 25 points
    vlm_score = min(vlm_score, 25)
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Calculate total (cap at 100)
    total_score = min(score + vlm_score, 100)
    
    # Determine pass/fail
    fiducials_found = sum([
        1 if liver_fid else 0,
        1 if spine_fid else 0,
        1 if heart_fid else 0
    ])
    
    fiducials_correct = sum([
        1 if liver_fid and details.get('liver_position_correct', False) else 0,
        1 if spine_fid and details.get('spine_position_correct', False) else 0,
        1 if heart_fid and details.get('heart_position_correct', False) else 0
    ])
    
    # Pass criteria: score >= 70 AND at least 2 fiducials correctly placed
    passed = total_score >= 70 and fiducials_correct >= 2
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "fiducials_found": fiducials_found,
            "fiducials_correct": fiducials_correct,
            "base_score": score,
            "vlm_bonus": vlm_score,
            "liver_found": liver_fid is not None,
            "spine_found": spine_fid is not None,
            "heart_found": heart_fid is not None,
            "spatial_relationships": details.get('spatial_relationships', {}),
            "vlm_analysis": details.get('vlm_analysis', {})
        }
    }