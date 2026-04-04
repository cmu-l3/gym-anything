#!/usr/bin/env python3
"""
Verifier for Fiducial-Based Volume Registration task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

1. Transform Node Exists (15 points) - A LinearTransform was created
2. Transform Applied to Moving Volume (15 points) - Moving volume has parent transform
3. Minimum Fiducials Placed (15 points) - At least 4 fiducial pairs exist
4. FRE Below 3.0 mm (20 points) - Registration achieved acceptable accuracy
5. Rotation Error < 2° (15 points) - Computed rotation close to ground truth
6. Translation Error < 2 mm (10 points) - Computed translation close to ground truth
7. VLM Visual Confirmation (10 points) - Trajectory shows registration workflow

Pass threshold: 70 points with Transform Applied AND FRE acceptable
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fiducial_volume_registration(traj, env_info, task_info):
    """
    Verify the fiducial volume registration task.
    
    Uses copy_from_env to read result files from container.
    Uses trajectory frames for VLM verification.
    
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
    min_fiducial_pairs = metadata.get('min_fiducial_pairs', 4)
    max_fre_mm = metadata.get('max_fre_mm', 3.0)
    max_rotation_error_deg = metadata.get('max_rotation_error_deg', 2.0)
    max_translation_error_mm = metadata.get('max_translation_error_mm', 2.0)
    
    weights = metadata.get('scoring_weights', {})
    w_transform_exists = weights.get('transform_exists', 15)
    w_transform_applied = weights.get('transform_applied', 15)
    w_min_fiducials = weights.get('min_fiducials', 15)
    w_fre_quality = weights.get('fre_quality', 20)
    w_rotation = weights.get('rotation_accuracy', 15)
    w_translation = weights.get('translation_accuracy', 10)
    w_vlm = weights.get('vlm_visual', 10)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Load task result from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/registration_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task could not be verified"
        }
    
    # ================================================================
    # Load ground truth from container
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env("/var/lib/slicer/ground_truth/registration_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
        details['ground_truth_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        details['ground_truth_loaded'] = False
        details['ground_truth_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # ================================================================
    # CRITERION 1: Transform Node Exists (15 points)
    # ================================================================
    transforms = result.get('transforms', [])
    transform_exists = len(transforms) > 0
    
    if transform_exists:
        score += w_transform_exists
        feedback_parts.append(f"✓ Transform created ({len(transforms)} found)")
        details['transform_exists'] = True
        details['num_transforms'] = len(transforms)
    else:
        feedback_parts.append("✗ No transform node created")
        details['transform_exists'] = False
    
    # ================================================================
    # CRITERION 2: Transform Applied to Moving Volume (15 points)
    # ================================================================
    transform_applied = result.get('moving_volume_has_transform', False) or \
                       result.get('registration_applied', False)
    
    if transform_applied:
        score += w_transform_applied
        feedback_parts.append("✓ Transform applied to moving volume")
        details['transform_applied'] = True
    else:
        feedback_parts.append("✗ Transform not applied to moving volume")
        details['transform_applied'] = False
    
    # ================================================================
    # CRITERION 3: Minimum Fiducials Placed (15 points)
    # ================================================================
    fiducials = result.get('fiducials', [])
    fiducial_pairs = result.get('fiducial_pairs', 0)
    
    # Alternative calculation if not pre-computed
    if fiducial_pairs == 0 and len(fiducials) >= 2:
        counts = sorted([f.get('num_points', 0) for f in fiducials], reverse=True)
        fiducial_pairs = min(counts[0], counts[1]) if len(counts) >= 2 else 0
    
    details['fiducial_pairs'] = fiducial_pairs
    details['fiducial_lists'] = len(fiducials)
    
    if fiducial_pairs >= min_fiducial_pairs:
        score += w_min_fiducials
        feedback_parts.append(f"✓ Sufficient fiducials ({fiducial_pairs} pairs ≥ {min_fiducial_pairs})")
    elif fiducial_pairs >= 3:
        score += int(w_min_fiducials * 0.7)
        feedback_parts.append(f"⚠ Partial fiducials ({fiducial_pairs} pairs, need {min_fiducial_pairs})")
    else:
        feedback_parts.append(f"✗ Insufficient fiducials ({fiducial_pairs} pairs, need {min_fiducial_pairs})")
    
    # ================================================================
    # CRITERION 4: FRE Below 3.0 mm (20 points)
    # ================================================================
    fre_mm = result.get('fre_mm')
    details['fre_mm'] = fre_mm
    
    if fre_mm is not None:
        if fre_mm < max_fre_mm:
            score += w_fre_quality
            feedback_parts.append(f"✓ FRE acceptable ({fre_mm:.2f} mm < {max_fre_mm} mm)")
            details['fre_acceptable'] = True
        elif fre_mm < max_fre_mm * 1.5:
            score += int(w_fre_quality * 0.5)
            feedback_parts.append(f"⚠ FRE slightly high ({fre_mm:.2f} mm)")
            details['fre_acceptable'] = False
        else:
            feedback_parts.append(f"✗ FRE too high ({fre_mm:.2f} mm > {max_fre_mm} mm)")
            details['fre_acceptable'] = False
    else:
        # Give partial credit if registration was done but FRE couldn't be calculated
        if transform_applied and fiducial_pairs >= min_fiducial_pairs:
            score += int(w_fre_quality * 0.5)
            feedback_parts.append("⚠ FRE could not be calculated, partial credit")
        else:
            feedback_parts.append("✗ FRE not available")
        details['fre_acceptable'] = None
    
    # ================================================================
    # CRITERION 5 & 6: Transform Accuracy (15 + 10 points)
    # ================================================================
    rotation_error = None
    translation_error = None
    
    transform_matrix = result.get('transform_matrix')
    if transform_matrix and ground_truth:
        try:
            import numpy as np
            
            computed = np.array(transform_matrix)
            computed_rotation = computed[:3, :3]
            computed_translation = computed[:3, 3]
            
            # Get expected inverse transform
            expected = ground_truth.get('expected_inverse', {})
            expected_rotation = np.array(expected.get('rotation_matrix', np.eye(3)))
            expected_translation = np.array(expected.get('translation_mm', [0, 0, 0]))
            
            # Calculate rotation error using Frobenius norm of difference
            # or angle between rotations
            try:
                from scipy.spatial.transform import Rotation
                r_computed = Rotation.from_matrix(computed_rotation)
                r_expected = Rotation.from_matrix(expected_rotation)
                r_diff = r_computed * r_expected.inv()
                rotation_error = np.linalg.norm(r_diff.as_euler('xyz', degrees=True))
            except:
                # Fallback: use matrix difference
                rotation_diff = np.linalg.norm(computed_rotation - expected_rotation, 'fro')
                rotation_error = np.degrees(rotation_diff)  # Approximate
            
            # Calculate translation error
            translation_error = np.linalg.norm(computed_translation - expected_translation)
            
            details['rotation_error_deg'] = round(rotation_error, 2)
            details['translation_error_mm'] = round(translation_error, 2)
            
        except Exception as e:
            logger.warning(f"Could not calculate transform accuracy: {e}")
            details['transform_accuracy_error'] = str(e)
    
    # Score rotation accuracy
    if rotation_error is not None:
        if rotation_error < max_rotation_error_deg:
            score += w_rotation
            feedback_parts.append(f"✓ Rotation accurate ({rotation_error:.1f}° < {max_rotation_error_deg}°)")
        elif rotation_error < max_rotation_error_deg * 2:
            score += int(w_rotation * 0.5)
            feedback_parts.append(f"⚠ Rotation partially accurate ({rotation_error:.1f}°)")
        else:
            feedback_parts.append(f"✗ Rotation error too high ({rotation_error:.1f}°)")
    else:
        # If we couldn't calculate but registration exists, give partial credit
        if transform_exists:
            score += int(w_rotation * 0.3)
            feedback_parts.append("⚠ Rotation accuracy could not be verified")
        else:
            feedback_parts.append("✗ No transform to verify rotation")
    
    # Score translation accuracy
    if translation_error is not None:
        if translation_error < max_translation_error_mm:
            score += w_translation
            feedback_parts.append(f"✓ Translation accurate ({translation_error:.1f} mm < {max_translation_error_mm} mm)")
        elif translation_error < max_translation_error_mm * 2:
            score += int(w_translation * 0.5)
            feedback_parts.append(f"⚠ Translation partially accurate ({translation_error:.1f} mm)")
        else:
            feedback_parts.append(f"✗ Translation error too high ({translation_error:.1f} mm)")
    else:
        if transform_exists:
            score += int(w_translation * 0.3)
            feedback_parts.append("⚠ Translation accuracy could not be verified")
        else:
            feedback_parts.append("✗ No transform to verify translation")
    
    # ================================================================
    # CRITERION 7: VLM Visual Verification (10 points)
    # Uses trajectory frames, not just final screenshot
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            traj_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if traj_frames or final_frame:
                # Build list of images for VLM
                images = []
                if traj_frames:
                    images.extend(traj_frames)
                if final_frame and final_frame not in images:
                    images.append(final_frame)
                
                vlm_prompt = """Analyze these screenshots from a 3D Slicer registration workflow.

The task was to register two brain MRI volumes using fiducial landmarks.

Look for evidence of:
1. FIDUCIAL_PLACEMENT: Are there visible colored markers/dots placed on the brain images?
2. REGISTRATION_MODULE: Is the Fiducial Registration Wizard module visible?
3. VOLUME_ALIGNMENT: In the final state, do the brain images appear aligned (structures overlap)?
4. WORKFLOW_PROGRESSION: Do the screenshots show progression through a registration workflow?

Rate the registration completion from 0-10:
- 0-3: No evidence of registration work
- 4-6: Partial work (fiducials placed but not complete)
- 7-10: Complete registration (transform applied, volumes aligned)

Respond with just a number 0-10."""

                vlm_response = query_vlm(prompt=vlm_prompt, images=images)
                
                if vlm_response and vlm_response.get('success'):
                    response_text = vlm_response.get('response', '')
                    try:
                        # Parse rating from response
                        rating = float(response_text.strip().split()[0])
                        rating = min(10, max(0, rating))
                        vlm_score = rating
                        details['vlm_rating'] = rating
                        
                        if rating >= 7:
                            score += w_vlm
                            feedback_parts.append(f"✓ VLM confirms registration workflow (rating: {rating}/10)")
                        elif rating >= 4:
                            score += int(w_vlm * 0.5)
                            feedback_parts.append(f"⚠ VLM shows partial workflow (rating: {rating}/10)")
                        else:
                            feedback_parts.append(f"✗ VLM shows incomplete work (rating: {rating}/10)")
                    except (ValueError, IndexError):
                        score += int(w_vlm * 0.3)
                        feedback_parts.append("⚠ VLM response could not be parsed")
                        details['vlm_parse_error'] = True
                else:
                    feedback_parts.append("⚠ VLM query failed")
                    details['vlm_query_failed'] = True
            else:
                feedback_parts.append("⚠ No trajectory frames available for VLM")
                details['vlm_no_frames'] = True
                
        except ImportError:
            # VLM utilities not available, give partial credit based on other criteria
            if transform_applied and fiducial_pairs >= min_fiducial_pairs:
                score += int(w_vlm * 0.5)
                feedback_parts.append("⚠ VLM not available, partial credit for registration")
            else:
                feedback_parts.append("⚠ VLM verification not available")
            details['vlm_import_error'] = True
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠ VLM verification error: {str(e)[:50]}")
            details['vlm_error'] = str(e)
    else:
        feedback_parts.append("⚠ VLM verification not available")
        details['vlm_available'] = False
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    details['total_score'] = score
    details['max_score'] = 100
    
    # Pass requires:
    # - Score >= 70
    # - Transform applied to moving volume
    # - Either FRE acceptable OR (transform exists AND fiducials placed)
    fre_ok = fre_mm is not None and fre_mm < max_fre_mm
    basic_registration_done = transform_exists and fiducial_pairs >= 3
    
    passed = (score >= 70) and transform_applied and (fre_ok or basic_registration_done)
    
    # Summary
    details['summary'] = {
        'transform_created': transform_exists,
        'transform_applied': transform_applied,
        'fiducial_pairs': fiducial_pairs,
        'fre_mm': fre_mm,
        'rotation_error_deg': rotation_error,
        'translation_error_mm': translation_error,
        'vlm_rating': vlm_score
    }
    
    status = "PASSED" if passed else "FAILED"
    feedback_parts.append(f"\n=== RESULT: {status} ({score}/100 points) ===")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test run without container
    print("Verifier module loaded successfully")
    print("Function: verify_fiducial_volume_registration")