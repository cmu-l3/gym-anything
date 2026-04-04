#!/usr/bin/env python3
"""
Verifier for Invert Brain Mask task.

VERIFICATION CRITERIA:
1. Inverse segment exists (25 points) - A new segment was created
2. Segment has voxels (15 points) - The inverse segment is not empty
3. Voxel count complementary (25 points) - Brain + NonBrain covers ~95-105% of volume
4. Minimal overlap (15 points) - Overlap between segments < 1% of brain volume
5. VLM visual confirmation (20 points) - Visual verification that inverse surrounds brain

Pass threshold: 70 points with "Inverse Segment Exists" and "Segment Has Voxels" met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_invert_brain_mask(traj, env_info, task_info):
    """
    Verify that an inverse brain mask was created correctly.

    Uses multi-criteria scoring with complementarity checks.
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
    min_brain_voxels = metadata.get('min_brain_voxels', 100000)
    max_overlap_ratio = metadata.get('max_overlap_ratio', 0.01)
    coverage_tolerance = metadata.get('coverage_tolerance', 0.10)
    expected_inverse_names = metadata.get('expected_inverse_names', 
        ["NonBrain", "Inverse", "Background", "Skull", "NonBrain_1"])
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('inverse_segment_exists', 25)
    w_has_voxels = weights.get('segment_has_voxels', 15)
    w_complementary = weights.get('voxel_count_complementary', 25)
    w_minimal_overlap = weights.get('minimal_overlap', 15)
    w_vlm = weights.get('vlm_visual_confirmation', 20)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/invert_mask_result.json", temp_result.name)
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
    key_criteria_met = True

    # Check for export errors
    if result.get('error'):
        feedback_parts.append(f"Export error: {result['error']}")
        details['export_error'] = result['error']

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ============================================================
    # CRITERION 1: Inverse segment exists (25 points)
    # ============================================================
    inverse_found = result.get('inverse_segment_found', False)
    inverse_name = result.get('inverse_segment_name', '')
    total_segments = result.get('total_segments', 0)
    segment_names = result.get('segment_names', [])
    
    details['total_segments'] = total_segments
    details['segment_names'] = segment_names
    details['inverse_found'] = inverse_found
    details['inverse_name'] = inverse_name

    if inverse_found:
        score += w_exists
        feedback_parts.append(f"Inverse segment '{inverse_name}' found")
    elif total_segments >= 2:
        # Partial credit - they created a second segment
        score += w_exists * 0.6
        feedback_parts.append(f"Second segment exists ({segment_names})")
        key_criteria_met = False
    else:
        feedback_parts.append("No inverse segment found")
        key_criteria_met = False

    # ============================================================
    # CRITERION 2: Segment has voxels (15 points)
    # ============================================================
    inverse_voxels = result.get('inverse_voxels', 0)
    brain_voxels = result.get('brain_voxels', 0)
    
    details['inverse_voxels'] = inverse_voxels
    details['brain_voxels'] = brain_voxels

    if inverse_voxels > min_brain_voxels:
        score += w_has_voxels
        feedback_parts.append(f"Inverse has {inverse_voxels:,} voxels")
    elif inverse_voxels > min_brain_voxels * 0.5:
        score += w_has_voxels * 0.7
        feedback_parts.append(f"Inverse has {inverse_voxels:,} voxels (somewhat small)")
    elif inverse_voxels > 0:
        score += w_has_voxels * 0.3
        feedback_parts.append(f"Inverse has only {inverse_voxels:,} voxels")
        key_criteria_met = False
    else:
        feedback_parts.append("Inverse segment is empty")
        key_criteria_met = False

    # ============================================================
    # CRITERION 3: Voxel count complementary (25 points)
    # Brain + NonBrain should cover approximately the whole volume
    # ============================================================
    total_volume_voxels = result.get('total_volume_voxels', 0)
    initial_total_voxels = result.get('initial_total_voxels', total_volume_voxels)
    coverage_ratio = result.get('coverage_ratio', 0)
    
    # Use whichever total we have
    total_voxels = max(total_volume_voxels, initial_total_voxels)
    
    details['total_volume_voxels'] = total_voxels
    details['coverage_ratio'] = coverage_ratio

    if total_voxels > 0 and brain_voxels > 0 and inverse_voxels > 0:
        # Calculate expected coverage
        combined_voxels = brain_voxels + inverse_voxels
        
        # For a proper inverse, brain + inverse should roughly equal total
        # But there might be overlap, so use coverage_ratio if available
        if coverage_ratio > 0:
            expected_coverage = coverage_ratio
        else:
            expected_coverage = combined_voxels / total_voxels
        
        details['calculated_coverage'] = expected_coverage
        
        # Perfect inverse: coverage should be ~1.0 (accounting for slight overlap)
        # Allow some tolerance
        if 0.90 <= expected_coverage <= 1.10:
            score += w_complementary
            feedback_parts.append(f"Coverage ratio: {expected_coverage:.2%} (excellent)")
        elif 0.80 <= expected_coverage <= 1.20:
            score += w_complementary * 0.7
            feedback_parts.append(f"Coverage ratio: {expected_coverage:.2%} (good)")
        elif 0.60 <= expected_coverage <= 1.40:
            score += w_complementary * 0.4
            feedback_parts.append(f"Coverage ratio: {expected_coverage:.2%} (partial)")
        else:
            feedback_parts.append(f"Coverage ratio: {expected_coverage:.2%} (incorrect)")
    else:
        feedback_parts.append("Cannot calculate coverage (missing data)")

    # ============================================================
    # CRITERION 4: Minimal overlap (15 points)
    # ============================================================
    overlap_voxels = result.get('overlap_voxels', 0)
    overlap_ratio = result.get('overlap_ratio', 0)
    
    details['overlap_voxels'] = overlap_voxels
    details['overlap_ratio'] = overlap_ratio

    if brain_voxels > 0:
        if overlap_ratio < max_overlap_ratio:
            score += w_minimal_overlap
            feedback_parts.append(f"Overlap: {overlap_ratio:.2%} (minimal)")
        elif overlap_ratio < max_overlap_ratio * 3:
            score += w_minimal_overlap * 0.7
            feedback_parts.append(f"Overlap: {overlap_ratio:.2%} (acceptable)")
        elif overlap_ratio < max_overlap_ratio * 10:
            score += w_minimal_overlap * 0.3
            feedback_parts.append(f"Overlap: {overlap_ratio:.2%} (high)")
        else:
            feedback_parts.append(f"Overlap: {overlap_ratio:.2%} (too high)")
    elif inverse_voxels > 0 and overlap_voxels == 0:
        # No overlap data but inverse exists - give partial credit
        score += w_minimal_overlap * 0.5
        feedback_parts.append("Overlap not measured but segments exist")

    # ============================================================
    # CRITERION 5: VLM visual confirmation (20 points)
    # ============================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        frames = sample_trajectory_frames(traj, n=5) if traj else []
        final_screenshot = get_final_screenshot(traj) if traj else None
        
        if final_screenshot or frames:
            vlm_prompt = """Analyze this 3D Slicer screenshot showing brain MRI segmentation.

Look for evidence of:
1. TWO SEGMENTS visible (Brain segment AND an inverse/NonBrain segment)
2. The inverse segment should SURROUND the brain (covering skull, background, CSF)
3. Both segments visible in the segment list (left panel)
4. Different colors for each segment

Respond in JSON:
{
    "two_segments_visible": true/false,
    "brain_segment_visible": true/false,
    "inverse_segment_visible": true/false,
    "inverse_surrounds_brain": true/false,
    "segment_colors_different": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see"
}"""
            
            images_to_use = frames[-3:] if frames else []
            if final_screenshot:
                images_to_use.append(final_screenshot)
            
            if images_to_use:
                vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_use)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    two_segs = parsed.get('two_segments_visible', False)
                    inverse_surrounds = parsed.get('inverse_surrounds_brain', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    if two_segs and inverse_surrounds:
                        if confidence == 'high':
                            vlm_score = w_vlm
                        elif confidence == 'medium':
                            vlm_score = w_vlm * 0.8
                        else:
                            vlm_score = w_vlm * 0.6
                        vlm_feedback = f"VLM: inverse confirmed ({confidence})"
                    elif two_segs:
                        vlm_score = w_vlm * 0.5
                        vlm_feedback = "VLM: two segments but inverse unclear"
                    else:
                        vlm_feedback = "VLM: could not confirm inverse"
                else:
                    vlm_feedback = "VLM: query failed"
        else:
            vlm_feedback = "VLM: no screenshots available"
            
    except ImportError:
        vlm_feedback = "VLM: module not available"
        # Give partial credit if other criteria are met
        if inverse_found and inverse_voxels > min_brain_voxels:
            vlm_score = w_vlm * 0.5
            vlm_feedback = "VLM: skipped (module unavailable)"
    except Exception as e:
        vlm_feedback = f"VLM: error - {str(e)[:50]}"
        logger.warning(f"VLM verification error: {e}")

    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Calculate pass/fail
    # Pass requires: score >= 70 AND key criteria met (inverse exists and has voxels)
    passed = score >= 70 and key_criteria_met
    
    # Ensure score is within bounds
    score = max(0, min(100, int(score)))
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }