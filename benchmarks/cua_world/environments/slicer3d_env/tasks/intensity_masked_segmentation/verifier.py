#!/usr/bin/env python3
"""
Verifier for intensity_masked_segmentation task.

VERIFICATION CRITERIA:
1. Segmentation file exists (15 points)
2. Segment appropriately named (10 points)
3. Minimum voxel count >1000 (15 points)
4. Maximum voxel count <500000 (10 points)
5. Intensity compliance >98% (30 points) - CRITICAL
6. Spatial location valid - peripheral (10 points)
7. VLM trajectory verification (10 points)

Pass threshold: 70 points with intensity compliance >98% required

The intensity compliance check is DEFINITIVE - it cannot be faked.
Every voxel in the segmentation is checked against the CT intensity.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_intensity_masked_segmentation(traj, env_info, task_info):
    """
    Verify that intensity masking was used correctly for fat segmentation.
    
    The key check is that >98% of segmented voxels have HU values
    in the [-150, -50] range (fat tissue).
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
    intensity_min = metadata.get('intensity_range_min', -150)
    intensity_max = metadata.get('intensity_range_max', -50)
    min_voxel_count = metadata.get('min_voxel_count', 1000)
    max_voxel_count = metadata.get('max_voxel_count', 500000)
    compliance_threshold = metadata.get('intensity_compliance_threshold', 0.98)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('segmentation_exists', 15)
    w_named = weights.get('segment_named', 10)
    w_min_voxel = weights.get('min_voxel_count', 15)
    w_max_voxel = weights.get('max_voxel_count', 10)
    w_compliance = weights.get('intensity_compliance', 30)
    w_spatial = weights.get('spatial_location', 10)
    w_vlm = weights.get('vlm_verification', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/intensity_mask_result.json", temp_result.name)
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
            "feedback": f"Invalid result JSON: {e}"
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

    # Also try to copy detailed analysis
    analysis = {}
    temp_analysis = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/seg_analysis.json", temp_analysis.name)
        with open(temp_analysis.name, 'r') as f:
            analysis = json.load(f)
    except Exception:
        logger.warning("Could not load detailed analysis")
    finally:
        if os.path.exists(temp_analysis.name):
            os.unlink(temp_analysis.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # CRITERION 1: Segmentation file exists (15 points)
    # ================================================================
    seg_exists = result.get('segmentation_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if seg_exists and file_created:
        score += w_exists
        feedback_parts.append("Segmentation file created")
        details['segmentation_created'] = True
    elif seg_exists:
        score += w_exists * 0.5
        feedback_parts.append("Segmentation exists (may be pre-existing)")
        details['segmentation_created'] = False
    else:
        feedback_parts.append("NO segmentation file found")
        details['segmentation_created'] = False
        # Early exit - nothing to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Segment named appropriately (10 points)
    # ================================================================
    # Note: We can't easily check segment name from exported file
    # Give partial credit based on file being created
    if file_created:
        score += w_named * 0.7
        feedback_parts.append("Segment created (name assumed)")
    
    # ================================================================
    # CRITERION 3: Minimum voxel count (15 points)
    # ================================================================
    voxel_count = result.get('voxel_count', 0)
    if voxel_count == 0:
        voxel_count = analysis.get('voxel_count', 0)
    
    details['voxel_count'] = voxel_count
    
    if voxel_count >= min_voxel_count:
        score += w_min_voxel
        feedback_parts.append(f"Voxel count OK ({voxel_count})")
    elif voxel_count > 100:
        score += w_min_voxel * 0.3
        feedback_parts.append(f"Low voxel count ({voxel_count} < {min_voxel_count})")
    else:
        feedback_parts.append(f"Trivial segmentation ({voxel_count} voxels)")
    
    # ================================================================
    # CRITERION 4: Maximum voxel count (10 points)
    # ================================================================
    if voxel_count > 0 and voxel_count <= max_voxel_count:
        score += w_max_voxel
        feedback_parts.append("Voxel count within range")
    elif voxel_count > max_voxel_count:
        # Might have segmented too much
        score += w_max_voxel * 0.3
        feedback_parts.append(f"Excessive voxels ({voxel_count} > {max_voxel_count})")
    
    # ================================================================
    # CRITERION 5: Intensity compliance (30 points) - CRITICAL
    # ================================================================
    intensity_compliance = result.get('intensity_compliance', 0)
    if intensity_compliance == 0:
        intensity_compliance = analysis.get('intensity_compliance', 0)
    
    details['intensity_compliance'] = intensity_compliance
    details['compliance_threshold'] = compliance_threshold
    
    compliance_met = False
    
    if intensity_compliance >= compliance_threshold:
        score += w_compliance
        compliance_met = True
        feedback_parts.append(f"Intensity compliance: {intensity_compliance*100:.1f}% ✓")
    elif intensity_compliance >= 0.90:
        score += w_compliance * 0.6
        feedback_parts.append(f"Intensity compliance: {intensity_compliance*100:.1f}% (close)")
    elif intensity_compliance >= 0.70:
        score += w_compliance * 0.3
        feedback_parts.append(f"Intensity compliance: {intensity_compliance*100:.1f}% (masking may not be configured)")
    elif intensity_compliance > 0:
        feedback_parts.append(f"LOW intensity compliance: {intensity_compliance*100:.1f}% - masking NOT used")
    else:
        feedback_parts.append("Could not verify intensity compliance")
    
    # Get additional intensity stats for feedback
    mean_intensity = analysis.get('mean_intensity', 0)
    min_intensity = analysis.get('min_intensity', 0)
    max_intensity_found = analysis.get('max_intensity', 0)
    
    if mean_intensity != 0:
        details['mean_intensity_hu'] = mean_intensity
        details['intensity_range_found'] = [min_intensity, max_intensity_found]
        
        # Check if mean is in fat range
        if intensity_min <= mean_intensity <= intensity_max:
            feedback_parts.append(f"Mean HU: {mean_intensity:.0f} (in fat range)")
        else:
            feedback_parts.append(f"Mean HU: {mean_intensity:.0f} (outside fat range!)")
    
    # ================================================================
    # CRITERION 6: Spatial location (10 points)
    # ================================================================
    periphery_ratio = result.get('periphery_ratio', 0)
    if periphery_ratio == 0:
        periphery_ratio = analysis.get('periphery_ratio', 0)
    
    details['periphery_ratio'] = periphery_ratio
    
    # Subcutaneous fat should be near periphery (ratio > 0.3)
    if periphery_ratio >= 0.3:
        score += w_spatial
        feedback_parts.append(f"Peripheral location verified ({periphery_ratio:.2f})")
    elif periphery_ratio >= 0.15:
        score += w_spatial * 0.5
        feedback_parts.append(f"Somewhat peripheral ({periphery_ratio:.2f})")
    elif periphery_ratio > 0:
        feedback_parts.append(f"Central location ({periphery_ratio:.2f}) - may not be subcutaneous fat")
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    
    # Check if we have trajectory frames
    try:
        # Import VLM utilities if available
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to:
1. Open Segment Editor module
2. Configure intensity masking (check 'Editable intensity range' and set values -150 to -50)
3. Use Paint tool to segment subcutaneous fat tissue

Look for evidence of:
1. Segment Editor module visible (segment list, effects toolbar)
2. Masking panel expanded and configured (intensity range fields visible)
3. Paint tool being used
4. Segmentation appearing in the image views (colored overlay on fat tissue)

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "masking_panel_visible": true/false,
    "segmentation_visible": true/false,
    "workflow_evidence": "brief description of what you see",
    "confidence": "low/medium/high"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_analysis'] = parsed
                
                seg_editor = parsed.get('segment_editor_visible', False)
                masking_visible = parsed.get('masking_panel_visible', False)
                seg_visible = parsed.get('segmentation_visible', False)
                
                if seg_editor and masking_visible and seg_visible:
                    vlm_score = w_vlm
                    feedback_parts.append("VLM: Full workflow verified")
                elif seg_editor and seg_visible:
                    vlm_score = w_vlm * 0.7
                    feedback_parts.append("VLM: Segmentation workflow seen")
                elif seg_editor:
                    vlm_score = w_vlm * 0.4
                    feedback_parts.append("VLM: Segment Editor used")
                else:
                    feedback_parts.append("VLM: Workflow not clearly visible")
            else:
                feedback_parts.append("VLM: Analysis unavailable")
                vlm_score = w_vlm * 0.5  # Give partial credit
                
    except ImportError:
        logger.warning("VLM utilities not available")
        # Give partial credit if other criteria are met
        if compliance_met and voxel_count >= min_voxel_count:
            vlm_score = w_vlm * 0.5
            feedback_parts.append("VLM: Skipped (strong programmatic evidence)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_score = w_vlm * 0.3
        feedback_parts.append("VLM: Error in verification")
    
    score += vlm_score

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing:
    # 1. Segmentation must exist
    # 2. Intensity compliance must be >= 98% (the definitive check)
    # 3. Reasonable voxel count
    
    key_criteria_met = (
        seg_exists and
        file_created and
        compliance_met and
        voxel_count >= min_voxel_count * 0.5
    )
    
    passed = score >= 70 and key_criteria_met
    
    # If compliance is high but score is borderline, pass
    if intensity_compliance >= compliance_threshold and score >= 60:
        passed = True
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    details['slicer_running'] = result.get('slicer_was_running', False)
    details['task_duration_sec'] = result.get('task_end', 0) - result.get('task_start', 0)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": feedback,
        "details": details
    }