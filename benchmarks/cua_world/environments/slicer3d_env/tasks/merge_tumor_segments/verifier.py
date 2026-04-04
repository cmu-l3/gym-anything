#!/usr/bin/env python3
"""
Verifier for merge_tumor_segments task.

VERIFICATION CRITERIA:
1. Total Tumor segment exists (30 points) - a segment with "total" and "tumor" in name
2. Correct name format (10 points) - named exactly "Total Tumor" or "Total_Tumor"
3. Volume consistency (25 points) - merged volume ≈ sum of original segments (±10%)
4. Original segments preserved (15 points) - all three original segments still exist
5. Segment Editor used (10 points) - evidence of using the correct module
6. VLM confirms merge (10 points) - visual verification of merged segment

Pass threshold: 55 points with Total Tumor segment exists
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_merge_tumor_segments(traj, env_info, task_info):
    """
    Verify that tumor segments were correctly merged.
    
    Uses multi-criteria scoring with volume consistency checks.
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
    volume_tolerance_pct = metadata.get('volume_tolerance_percent', 10)
    
    weights = metadata.get('scoring_weights', {})
    w_total_tumor_exists = weights.get('total_tumor_exists', 30)
    w_correct_name = weights.get('correct_name_format', 10)
    w_volume_consistency = weights.get('volume_consistency', 25)
    w_original_preserved = weights.get('original_segments_preserved', 15)
    w_segment_editor = weights.get('segment_editor_used', 10)
    w_vlm_confirms = weights.get('vlm_confirms_merge', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/merge_segments_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # CRITERION 1: Total Tumor segment exists (30 points)
    # ================================================================
    total_tumor_found = result.get('total_tumor_found', False)
    total_tumor_name = result.get('total_tumor_name', '')
    
    if total_tumor_found:
        score += w_total_tumor_exists
        feedback_parts.append(f"Total Tumor segment found: '{total_tumor_name}'")
        details['total_tumor_found'] = True
        details['total_tumor_name'] = total_tumor_name
    else:
        feedback_parts.append("Total Tumor segment NOT found")
        details['total_tumor_found'] = False
        # Critical failure - no point checking other criteria
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Correct name format (10 points)
    # ================================================================
    correct_name_format = result.get('correct_name_format', False)
    name_lower = total_tumor_name.lower().replace(' ', '_').replace('-', '_')
    
    if correct_name_format or name_lower in ['total_tumor', 'totaltumor']:
        score += w_correct_name
        feedback_parts.append("Correct name format")
        details['correct_name'] = True
    elif 'total' in name_lower and 'tumor' in name_lower:
        # Partial credit for having both words
        score += w_correct_name // 2
        feedback_parts.append(f"Name acceptable: '{total_tumor_name}'")
        details['correct_name'] = 'partial'
    else:
        feedback_parts.append(f"Name format issue: '{total_tumor_name}'")
        details['correct_name'] = False

    # ================================================================
    # CRITERION 3: Volume consistency (25 points)
    # ================================================================
    total_tumor_voxels = result.get('total_tumor_voxels', 0)
    expected_voxels = result.get('expected_total_voxels', 0)
    volume_consistent = result.get('volume_consistent', False)
    volume_diff_pct = result.get('volume_diff_percent', 100)
    
    details['total_tumor_voxels'] = total_tumor_voxels
    details['expected_voxels'] = expected_voxels
    details['volume_diff_percent'] = volume_diff_pct
    
    if volume_consistent:
        score += w_volume_consistency
        feedback_parts.append(f"Volume consistent ({volume_diff_pct:.1f}% diff)")
        details['volume_consistent'] = True
    elif total_tumor_voxels > 0 and expected_voxels > 0:
        # Partial credit based on how close
        if volume_diff_pct <= 20:
            partial_score = int(w_volume_consistency * 0.6)
            score += partial_score
            feedback_parts.append(f"Volume close ({volume_diff_pct:.1f}% diff)")
            details['volume_consistent'] = 'partial'
        elif volume_diff_pct <= 30:
            partial_score = int(w_volume_consistency * 0.3)
            score += partial_score
            feedback_parts.append(f"Volume differs ({volume_diff_pct:.1f}% diff)")
            details['volume_consistent'] = 'weak'
        else:
            feedback_parts.append(f"Volume mismatch ({volume_diff_pct:.1f}% diff)")
            details['volume_consistent'] = False
    else:
        feedback_parts.append("Volume not computed")
        details['volume_consistent'] = False

    # ================================================================
    # CRITERION 4: Original segments preserved (15 points)
    # ================================================================
    original_preserved = result.get('original_segments_preserved', False)
    found_necrotic = result.get('found_necrotic', False)
    found_edema = result.get('found_edema', False)
    found_enhancing = result.get('found_enhancing', False)
    
    details['found_necrotic'] = found_necrotic
    details['found_edema'] = found_edema
    details['found_enhancing'] = found_enhancing
    
    if original_preserved:
        score += w_original_preserved
        feedback_parts.append("Original segments preserved")
        details['original_preserved'] = True
    else:
        # Partial credit for some preserved
        preserved_count = sum([found_necrotic, found_edema, found_enhancing])
        if preserved_count >= 2:
            partial_score = int(w_original_preserved * 0.6)
            score += partial_score
            feedback_parts.append(f"{preserved_count}/3 original segments preserved")
            details['original_preserved'] = 'partial'
        elif preserved_count >= 1:
            partial_score = int(w_original_preserved * 0.3)
            score += partial_score
            feedback_parts.append(f"Only {preserved_count}/3 segments preserved")
            details['original_preserved'] = 'weak'
        else:
            feedback_parts.append("Original segments deleted")
            details['original_preserved'] = False

    # ================================================================
    # CRITERION 5: Segment Editor used (10 points)
    # ================================================================
    num_segments = result.get('num_segments', 0)
    segment_export_success = result.get('segment_export_success', False)
    
    # Heuristic: if we have 4+ segments and export worked, likely used Segment Editor
    if segment_export_success and num_segments >= 4:
        score += w_segment_editor
        feedback_parts.append(f"Segment Editor used ({num_segments} segments)")
        details['segment_editor_used'] = True
    elif segment_export_success and num_segments >= 1:
        score += w_segment_editor // 2
        feedback_parts.append(f"Segmentation modified ({num_segments} segments)")
        details['segment_editor_used'] = 'partial'
    else:
        feedback_parts.append("Could not verify Segment Editor usage")
        details['segment_editor_used'] = False

    # ================================================================
    # CRITERION 6: VLM verification (10 points)
    # ================================================================
    # Try to use VLM for visual verification if available
    vlm_score = 0
    try:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames to verify the process
        frames = sample_trajectory_frames(traj, n=4)
        final_screenshot = get_final_screenshot(traj)
        
        if final_screenshot or frames:
            # Use trajectory frames for process verification
            images_to_check = frames[-2:] + ([final_screenshot] if final_screenshot else [])
            
            vlm_prompt = """Analyze these screenshots from 3D Slicer showing a segmentation task.

I need to verify if the agent merged tumor segments. Look for:
1. Is Segment Editor module visible (panel on left with segment list)?
2. Are there multiple colored segments visible in the slice views?
3. Is there evidence of a "Total Tumor" or combined segment?
4. Do the slice views show overlapping/combined tumor regions?

Respond in JSON format:
{
    "segment_editor_visible": true/false,
    "multiple_segments_visible": true/false,
    "merged_segment_evidence": true/false,
    "tumor_visible_in_slices": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
            vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                if parsed.get('merged_segment_evidence', False):
                    vlm_score = w_vlm_confirms
                    feedback_parts.append("VLM confirms merge")
                elif parsed.get('multiple_segments_visible', False) and parsed.get('tumor_visible_in_slices', False):
                    vlm_score = w_vlm_confirms // 2
                    feedback_parts.append("VLM sees segmentation work")
                else:
                    feedback_parts.append("VLM inconclusive")
                
                details['vlm_result'] = parsed
            else:
                feedback_parts.append("VLM check failed")
                details['vlm_result'] = None
        else:
            feedback_parts.append("No screenshots for VLM")
            
    except ImportError:
        # VLM not available - give partial credit based on other signals
        if total_tumor_found and volume_consistent:
            vlm_score = w_vlm_confirms // 2
            feedback_parts.append("VLM unavailable, inferred from data")
        else:
            feedback_parts.append("VLM unavailable")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM error")
    
    score += vlm_score
    details['vlm_score'] = vlm_score

    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_total_tumor_exists + w_correct_name + w_volume_consistency + \
                w_original_preserved + w_segment_editor + w_vlm_confirms
    
    # Key criteria for passing
    key_criteria_met = (
        total_tumor_found and
        (volume_consistent or volume_diff_pct <= 20)
    )
    
    passed = score >= 55 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }