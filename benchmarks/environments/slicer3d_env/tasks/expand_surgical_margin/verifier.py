#!/usr/bin/env python3
"""
Verifier for Expand Surgical Margin task in 3D Slicer.

VERIFICATION CRITERIA (Multi-signal approach):
1. Output file exists (15 points) - segmentation file saved at expected path
2. Valid segmentation (15 points) - file can be loaded and contains non-empty data
3. Volume increased (20 points) - expanded volume > 150% of original
4. Volume ratio correct (20 points) - ratio between 1.5x and 8x (realistic margin)
5. Surface distance ~5mm (20 points) - average distance from original surface ~5mm
6. VLM visual confirmation (10 points) - trajectory shows margin expansion workflow

Pass threshold: 65 points with output file exists AND volume increased
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_expand_surgical_margin(traj, env_info, task_info):
    """
    Verify that surgical margin was correctly expanded.
    
    Uses multiple independent signals to prevent gaming.
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
    expected_output_path = metadata.get('expected_output_path', 
        '/home/ga/Documents/SlicerData/BraTS/surgical_margin_segmentation.seg.nrrd')
    margin_size_mm = metadata.get('margin_size_mm', 5.0)
    margin_tolerance_mm = metadata.get('margin_tolerance_mm', 1.5)
    min_volume_ratio = metadata.get('min_volume_ratio', 1.5)
    max_volume_ratio = metadata.get('max_volume_ratio', 8.0)
    expected_surface_dist = metadata.get('expected_surface_distance_mm', 5.0)
    surface_dist_tolerance = metadata.get('surface_distance_tolerance_mm', 2.0)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('output_file_exists', 15)
    w_valid_seg = weights.get('valid_segmentation', 15)
    w_vol_increased = weights.get('volume_increased', 20)
    w_vol_ratio = weights.get('volume_ratio_correct', 20)
    w_surface_dist = weights.get('surface_distance_correct', 20)
    w_vlm = weights.get('vlm_visual_confirmation', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/margin_task_result.json", temp_result.name)
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
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and file_created_during_task and output_size > 1000:
        score += w_file_exists
        feedback_parts.append(f"Output file created ({output_size/1024:.1f}KB)")
        details['output_file'] = 'created'
    elif output_exists and output_size > 1000:
        score += w_file_exists * 0.7  # Partial credit if exists but may be pre-existing
        feedback_parts.append(f"Output file exists (may be pre-existing)")
        details['output_file'] = 'exists_not_verified_new'
    else:
        feedback_parts.append("Output file NOT found or empty")
        details['output_file'] = 'missing'
        # Early exit - can't verify anything else without output
        return {
            "passed": False,
            "score": int(score),
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Valid segmentation (15 points)
    # ================================================================
    output_voxel_count = result.get('output_voxel_count', 0)
    output_load_error = result.get('output_load_error', None)
    
    if output_voxel_count > 100 and not output_load_error:
        score += w_valid_seg
        feedback_parts.append(f"Valid segmentation ({output_voxel_count} voxels)")
        details['segmentation_valid'] = True
    elif output_voxel_count > 0:
        score += w_valid_seg * 0.5
        feedback_parts.append(f"Small segmentation ({output_voxel_count} voxels)")
        details['segmentation_valid'] = 'small'
    else:
        feedback_parts.append(f"Invalid/empty segmentation: {output_load_error or 'no voxels'}")
        details['segmentation_valid'] = False
    
    # ================================================================
    # CRITERION 3: Volume increased (20 points)
    # ================================================================
    initial_volume = result.get('initial_volume_mm3', 0)
    output_volume = result.get('output_volume_mm3', 0)
    volume_ratio = result.get('volume_ratio', 0)
    
    details['initial_volume_ml'] = initial_volume / 1000 if initial_volume else 0
    details['output_volume_ml'] = output_volume / 1000 if output_volume else 0
    details['volume_ratio'] = volume_ratio
    
    if volume_ratio >= min_volume_ratio:
        score += w_vol_increased
        feedback_parts.append(f"Volume increased ({volume_ratio:.2f}x)")
        details['volume_increased'] = True
    elif volume_ratio > 1.0:
        # Partial credit for some increase
        partial = (volume_ratio - 1.0) / (min_volume_ratio - 1.0) * w_vol_increased
        score += partial
        feedback_parts.append(f"Volume slightly increased ({volume_ratio:.2f}x, expected >={min_volume_ratio}x)")
        details['volume_increased'] = 'partial'
    else:
        feedback_parts.append(f"Volume NOT increased (ratio: {volume_ratio:.2f})")
        details['volume_increased'] = False
    
    # ================================================================
    # CRITERION 4: Volume ratio in correct range (20 points)
    # ================================================================
    if min_volume_ratio <= volume_ratio <= max_volume_ratio:
        score += w_vol_ratio
        feedback_parts.append(f"Volume ratio correct ({volume_ratio:.2f}x in [{min_volume_ratio}, {max_volume_ratio}])")
        details['volume_ratio_correct'] = True
    elif volume_ratio > max_volume_ratio:
        # Too much expansion - partial credit
        score += w_vol_ratio * 0.3
        feedback_parts.append(f"Volume ratio too high ({volume_ratio:.2f}x > {max_volume_ratio}x)")
        details['volume_ratio_correct'] = 'too_high'
    elif volume_ratio >= 1.2:
        # Some expansion but not enough - partial credit
        partial = (volume_ratio - 1.0) / (min_volume_ratio - 1.0) * w_vol_ratio
        score += partial
        feedback_parts.append(f"Volume ratio too low ({volume_ratio:.2f}x < {min_volume_ratio}x)")
        details['volume_ratio_correct'] = 'too_low'
    else:
        details['volume_ratio_correct'] = False
    
    # ================================================================
    # CRITERION 5: Surface distance ~5mm (20 points)
    # ================================================================
    surface_dist_mean = result.get('surface_distance_mean_mm', None)
    surface_dist_median = result.get('surface_distance_median_mm', None)
    
    if surface_dist_mean is not None or surface_dist_median is not None:
        # Use median if available (more robust), otherwise mean
        dist_value = surface_dist_median if surface_dist_median is not None else surface_dist_mean
        details['surface_distance_mm'] = dist_value
        
        # Check if within tolerance of expected margin
        dist_error = abs(dist_value - expected_surface_dist)
        
        if dist_error <= surface_dist_tolerance:
            score += w_surface_dist
            feedback_parts.append(f"Surface distance correct ({dist_value:.1f}mm ≈ {expected_surface_dist}mm)")
            details['surface_distance_correct'] = True
        elif dist_error <= surface_dist_tolerance * 2:
            # Partial credit for close but not perfect
            partial = (1 - dist_error / (surface_dist_tolerance * 2)) * w_surface_dist
            score += partial
            feedback_parts.append(f"Surface distance approximate ({dist_value:.1f}mm, expected {expected_surface_dist}±{surface_dist_tolerance}mm)")
            details['surface_distance_correct'] = 'approximate'
        else:
            feedback_parts.append(f"Surface distance incorrect ({dist_value:.1f}mm, expected {expected_surface_dist}±{surface_dist_tolerance}mm)")
            details['surface_distance_correct'] = False
    else:
        # Couldn't compute surface distance
        feedback_parts.append("Surface distance not computed")
        details['surface_distance_correct'] = 'not_computed'
    
    # ================================================================
    # CRITERION 6: VLM Visual Confirmation (10 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Get trajectory frames
        frames = sample_trajectory_frames(traj, n=5) if traj else []
        
        if frames and len(frames) >= 2:
            # Query VLM about the workflow
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.
            
The task was to expand a brain tumor segmentation by 5mm using the Margin effect in Segment Editor.

Look for evidence of:
1. Segment Editor module being used (segment editing tools visible)
2. A segmentation overlay visible on brain MRI
3. The Margin effect being applied (margin tool in effects panel)
4. The segmentation appearing to grow/expand between frames

Based on the screenshots, assess:
- Was Segment Editor used? (yes/no/unclear)
- Is tumor segmentation visible? (yes/no/unclear)
- Does the segmentation appear to have been expanded? (yes/no/unclear)
- Overall confidence that margin expansion was performed (low/medium/high)

Respond in JSON format:
{
    "segment_editor_used": "yes/no/unclear",
    "segmentation_visible": "yes/no/unclear",
    "expansion_visible": "yes/no/unclear",
    "confidence": "low/medium/high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                segment_editor = parsed.get('segment_editor_used', 'unclear')
                seg_visible = parsed.get('segmentation_visible', 'unclear')
                expansion = parsed.get('expansion_visible', 'unclear')
                confidence = parsed.get('confidence', 'low')
                
                details['vlm_segment_editor'] = segment_editor
                details['vlm_segmentation_visible'] = seg_visible
                details['vlm_expansion_visible'] = expansion
                details['vlm_confidence'] = confidence
                details['vlm_observations'] = parsed.get('observations', '')
                
                # Score based on VLM assessment
                if expansion == 'yes' or (seg_visible == 'yes' and segment_editor == 'yes'):
                    if confidence in ['high', 'medium']:
                        vlm_score = w_vlm
                        vlm_feedback = "VLM confirms margin expansion workflow"
                    else:
                        vlm_score = w_vlm * 0.6
                        vlm_feedback = "VLM partially confirms workflow"
                elif seg_visible == 'yes':
                    vlm_score = w_vlm * 0.4
                    vlm_feedback = "VLM sees segmentation but unclear on expansion"
                else:
                    vlm_feedback = "VLM could not confirm margin expansion"
            else:
                vlm_feedback = "VLM query failed"
                details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no result'
        else:
            vlm_feedback = "Insufficient trajectory frames for VLM"
            details['vlm_error'] = 'no_frames'
            
    except ImportError:
        vlm_feedback = "VLM not available"
        details['vlm_error'] = 'import_error'
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Additional checks
    slicer_running = result.get('slicer_was_running', False)
    contains_original = result.get('expanded_contains_original', False)
    original_coverage = result.get('original_coverage', 0)
    
    details['slicer_was_running'] = slicer_running
    details['contains_original'] = contains_original
    details['original_coverage'] = original_coverage
    
    # Determine pass/fail
    # Key criteria: output exists AND volume increased
    key_criteria_met = (
        output_exists and 
        output_voxel_count > 100 and 
        volume_ratio >= 1.2  # At least some increase
    )
    
    passed = score >= 65 and key_criteria_met
    
    # Compile final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }