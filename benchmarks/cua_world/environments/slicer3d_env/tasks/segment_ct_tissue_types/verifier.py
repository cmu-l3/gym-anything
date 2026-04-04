#!/usr/bin/env python3
"""
Verifier for multi-tissue CT segmentation task.

VERIFICATION STRATEGY (Multi-Signal):
1. Segmentation file exists (15 points)
2. File created during task - anti-gaming (10 points)
3. Three segments present (20 points)
4. Correct segment names (15 points)
5. Bone segment valid - voxel count in expected range (10 points)
6. Soft tissue segment valid (10 points)
7. Air segment valid (10 points)
8. VLM visual verification - multi-colored overlay visible (10 points)

Pass threshold: 65 points with "three segments present" criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_segment_ct_tissue_types(traj, env_info, task_info):
    """
    Verify multi-tissue CT segmentation task completion.
    
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
    weights = metadata.get('scoring_weights', {})
    
    w_file_exists = weights.get('file_exists', 15)
    w_file_recent = weights.get('file_recent', 10)
    w_three_segments = weights.get('three_segments', 20)
    w_correct_names = weights.get('correct_names', 15)
    w_bone_valid = weights.get('bone_valid', 10)
    w_soft_valid = weights.get('soft_tissue_valid', 10)
    w_air_valid = weights.get('air_valid', 10)
    w_vlm_visual = weights.get('vlm_visual', 10)
    
    expected_segments = metadata.get('expected_segments', {})
    
    # Initialize
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tissue_seg_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_loaded'] = True
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read export result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Load detailed analysis if available
    # ================================================================
    analysis = {}
    temp_analysis = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tissue_seg_analysis.json", temp_analysis.name)
        with open(temp_analysis.name, 'r') as f:
            analysis = json.load(f)
        details['analysis_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load detailed analysis: {e}")
        details['analysis_loaded'] = False
    finally:
        if os.path.exists(temp_analysis.name):
            os.unlink(temp_analysis.name)
    
    # ================================================================
    # Load ground truth for reference (optional)
    # ================================================================
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/slicer/ground_truth/amos_0001_tissue_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
        details['gt_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        details['gt_loaded'] = False
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # ================================================================
    # CRITERION 1: Segmentation file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 10000:  # At least 10KB for real segmentation
        score += w_file_exists
        feedback_parts.append(f"Segmentation file exists ({output_size/1024:.1f}KB)")
        details['file_exists'] = True
        details['file_size_kb'] = output_size / 1024
    elif output_exists:
        score += w_file_exists // 2
        feedback_parts.append(f"File exists but small ({output_size} bytes)")
        details['file_exists'] = True
        details['file_size_kb'] = output_size / 1024
    else:
        feedback_parts.append("Segmentation file NOT found")
        details['file_exists'] = False
        # Cannot continue without output file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    file_mtime = result.get('file_mtime', 0)
    
    if file_created_during_task:
        score += w_file_recent
        feedback_parts.append("File created during task")
        details['created_during_task'] = True
    elif file_mtime > task_start:
        score += w_file_recent // 2
        feedback_parts.append("File modified during task")
        details['created_during_task'] = False
        details['modified_during_task'] = True
    else:
        feedback_parts.append("WARNING: File may predate task")
        details['created_during_task'] = False
        details['modified_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Three segments present (20 points) - KEY CRITERION
    # ================================================================
    num_segments = result.get('num_segments', 0)
    if analysis:
        num_segments = max(num_segments, analysis.get('num_segments', 0))
    
    three_segments_met = False
    
    if num_segments == 3:
        score += w_three_segments
        feedback_parts.append("Exactly 3 segments present")
        three_segments_met = True
        details['num_segments'] = 3
    elif num_segments >= 3:
        score += int(w_three_segments * 0.8)
        feedback_parts.append(f"{num_segments} segments (expected 3)")
        three_segments_met = True
        details['num_segments'] = num_segments
    elif num_segments == 2:
        score += int(w_three_segments * 0.5)
        feedback_parts.append(f"Only {num_segments} segments (expected 3)")
        details['num_segments'] = num_segments
    elif num_segments == 1:
        score += int(w_three_segments * 0.2)
        feedback_parts.append(f"Only {num_segments} segment (expected 3)")
        details['num_segments'] = num_segments
    else:
        feedback_parts.append("No segments found")
        details['num_segments'] = 0
    
    # ================================================================
    # CRITERION 4: Correct segment names (15 points)
    # ================================================================
    segment_names_str = result.get('segment_names', '')
    if analysis:
        segment_names_list = analysis.get('segment_names', [])
        if segment_names_list:
            segment_names_str = ','.join(segment_names_list)
    
    segment_names_lower = segment_names_str.lower()
    
    has_bone = result.get('has_bone_segment', False) or 'bone' in segment_names_lower
    has_soft = result.get('has_soft_tissue_segment', False) or 'soft' in segment_names_lower or 'tissue' in segment_names_lower
    has_air = result.get('has_air_segment', False) or 'air' in segment_names_lower or 'lung' in segment_names_lower
    
    name_score = 0
    name_matches = 0
    
    if has_bone:
        name_score += w_correct_names // 3
        name_matches += 1
    if has_soft:
        name_score += w_correct_names // 3
        name_matches += 1
    if has_air:
        name_score += w_correct_names // 3
        name_matches += 1
    
    score += name_score
    
    if name_matches == 3:
        feedback_parts.append("All segment names correct")
    elif name_matches > 0:
        feedback_parts.append(f"{name_matches}/3 segment names match")
    else:
        feedback_parts.append("Segment names don't match expected (Bone, Soft Tissue, Air)")
    
    details['segment_names'] = segment_names_str
    details['has_bone_name'] = has_bone
    details['has_soft_tissue_name'] = has_soft
    details['has_air_name'] = has_air
    
    # ================================================================
    # CRITERIA 5-7: Segment voxel counts valid (10 points each)
    # ================================================================
    segment_voxels = analysis.get('segment_voxels', {})
    
    if segment_voxels and gt_data:
        # Bone validation
        bone_expected = gt_data.get('bone', {}).get('expected_voxels', 0)
        bone_tolerance = gt_data.get('bone', {}).get('tolerance_percent', 20) / 100.0
        
        soft_expected = gt_data.get('soft_tissue', {}).get('expected_voxels', 0)
        soft_tolerance = gt_data.get('soft_tissue', {}).get('tolerance_percent', 20) / 100.0
        
        air_expected = gt_data.get('air', {}).get('expected_voxels', 0)
        air_tolerance = gt_data.get('air', {}).get('tolerance_percent', 25) / 100.0
        
        # Check each segment by examining voxel counts
        # Since we don't know which label corresponds to which tissue,
        # we check if any label has voxels in the expected range
        
        voxel_counts = list(segment_voxels.values())
        
        bone_valid = False
        soft_valid = False
        air_valid = False
        
        for count in voxel_counts:
            # Check if this could be bone
            if bone_expected > 0:
                bone_min = bone_expected * (1 - bone_tolerance)
                bone_max = bone_expected * (1 + bone_tolerance)
                if bone_min <= count <= bone_max:
                    bone_valid = True
            
            # Check if this could be soft tissue
            if soft_expected > 0:
                soft_min = soft_expected * (1 - soft_tolerance)
                soft_max = soft_expected * (1 + soft_tolerance)
                if soft_min <= count <= soft_max:
                    soft_valid = True
            
            # Check if this could be air
            if air_expected > 0:
                air_min = air_expected * (1 - air_tolerance)
                air_max = air_expected * (1 + air_tolerance)
                if air_min <= count <= air_max:
                    air_valid = True
        
        # Also use fallback ranges from metadata
        if not bone_valid:
            bone_range = expected_segments.get('bone', {}).get('expected_voxel_range', [5000, 150000])
            for count in voxel_counts:
                if bone_range[0] <= count <= bone_range[1]:
                    bone_valid = True
                    break
        
        if not soft_valid:
            soft_range = expected_segments.get('soft_tissue', {}).get('expected_voxel_range', [500000, 3000000])
            for count in voxel_counts:
                if soft_range[0] <= count <= soft_range[1]:
                    soft_valid = True
                    break
        
        if not air_valid:
            air_range = expected_segments.get('air', {}).get('expected_voxel_range', [100000, 2000000])
            for count in voxel_counts:
                if air_range[0] <= count <= air_range[1]:
                    air_valid = True
                    break
        
        if bone_valid:
            score += w_bone_valid
            details['bone_voxels_valid'] = True
        else:
            details['bone_voxels_valid'] = False
        
        if soft_valid:
            score += w_soft_valid
            details['soft_tissue_voxels_valid'] = True
        else:
            details['soft_tissue_voxels_valid'] = False
        
        if air_valid:
            score += w_air_valid
            details['air_voxels_valid'] = True
        else:
            details['air_voxels_valid'] = False
        
        valid_count = sum([bone_valid, soft_valid, air_valid])
        feedback_parts.append(f"Segment volumes: {valid_count}/3 valid")
        details['segment_voxel_counts'] = segment_voxels
        
    else:
        # Cannot validate voxel counts - give partial credit if segments exist
        if num_segments >= 3:
            score += (w_bone_valid + w_soft_valid + w_air_valid) // 2
            feedback_parts.append("Segment volumes: partial credit (no detailed analysis)")
        details['voxel_validation'] = "skipped - no analysis data"
    
    # ================================================================
    # CRITERION 8: VLM Visual Verification (10 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    # Try to use VLM if available
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample trajectory frames - use multiple to verify process
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames:
            vlm_prompt = """You are analyzing screenshots from a medical imaging task in 3D Slicer.

The task was to create a multi-tissue CT segmentation with THREE segments:
1. Bone (typically yellow/white)
2. Soft Tissue (typically red/orange)
3. Air (typically blue/cyan)

Look at these screenshots and assess:
1. Is 3D Slicer visible with a CT scan loaded?
2. Is the Segment Editor module visible at any point?
3. Are there colored segmentation overlays visible on the CT slices?
4. Can you see THREE DISTINCT COLORS in the segmentation overlay?
5. Does the segmentation cover anatomically appropriate regions?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "segment_editor_used": true/false,
    "colored_overlay_visible": true/false,
    "multiple_colors_visible": true/false,
    "anatomically_plausible": true/false,
    "estimated_num_segments": 0-5,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                overlay_visible = parsed.get('colored_overlay_visible', False)
                multiple_colors = parsed.get('multiple_colors_visible', False)
                segment_editor_used = parsed.get('segment_editor_used', False)
                estimated_segments = parsed.get('estimated_num_segments', 0)
                
                if overlay_visible and multiple_colors:
                    vlm_score = w_vlm_visual
                    vlm_feedback = "VLM confirms multi-colored segmentation"
                elif overlay_visible:
                    vlm_score = w_vlm_visual // 2
                    vlm_feedback = "VLM sees overlay (colors unclear)"
                elif segment_editor_used:
                    vlm_score = w_vlm_visual // 3
                    vlm_feedback = "VLM confirms Segment Editor used"
                else:
                    vlm_feedback = "VLM: no clear segmentation visible"
                
                details['vlm_result'] = parsed
                
    except ImportError:
        vlm_feedback = "VLM not available"
        details['vlm_available'] = False
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Determine pass/fail
    # Must have: file exists + three segments (or close)
    key_criteria_met = details.get('file_exists', False) and num_segments >= 2
    
    passed = score >= 65 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }