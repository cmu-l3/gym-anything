#!/usr/bin/env python3
"""
Verifier for aortic CPR (Curved Planar Reformation) task.

VERIFICATION STRATEGY:
1. CPR image exists (10 points) - file created at expected path
2. CPR image size adequate (10 points) - file >50KB and dimensions >=256x256
3. CPR image not blank (10 points) - has sufficient color variance
4. Curve file exists (10 points) - JSON markup file created
5. Minimum control points (15 points) - at least 8 control points
6. Curve length adequate (15 points) - total length >=100mm
7. Anatomical alignment (15 points) - >=75% of points near true aorta centerline
8. VLM vessel confirmation (15 points) - VLM confirms workflow and vessel in CPR

Pass threshold: 70 points with both CPR image and curve file existing
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_aortic_cpr(traj, env_info, task_info):
    """
    Verify that a curved planar reformation was created correctly.
    
    Uses multi-criteria scoring with anatomical validation.
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
    min_control_points = metadata.get('min_control_points', 8)
    min_curve_length_mm = metadata.get('min_curve_length_mm', 100)
    min_cpr_size_kb = metadata.get('min_cpr_size_kb', 50)
    min_cpr_dimension = metadata.get('min_cpr_dimension', 256)
    
    weights = metadata.get('scoring_weights', {})
    w_cpr_exists = weights.get('cpr_image_exists', 10)
    w_cpr_size = weights.get('cpr_image_size_ok', 10)
    w_cpr_not_blank = weights.get('cpr_image_not_blank', 10)
    w_curve_exists = weights.get('curve_file_exists', 10)
    w_min_points = weights.get('min_control_points', 15)
    w_curve_length = weights.get('curve_length_adequate', 15)
    w_alignment = weights.get('anatomical_alignment', 15)
    w_vlm = weights.get('vlm_vessel_confirmation', 15)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/aortic_cpr_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer not running")
    
    # ============================================================
    # CRITERION 1: CPR image exists (10 points)
    # ============================================================
    cpr_data = result.get('cpr_image', {})
    cpr_exists = cpr_data.get('exists', False)
    
    if cpr_exists:
        score += w_cpr_exists
        feedback_parts.append("CPR image exists")
        details['cpr_exists'] = True
    else:
        feedback_parts.append("CPR image NOT found")
        details['cpr_exists'] = False
    
    # ============================================================
    # CRITERION 2: CPR image size adequate (10 points)
    # ============================================================
    cpr_size_kb = cpr_data.get('size_bytes', 0) / 1024
    cpr_width = cpr_data.get('width', 0)
    cpr_height = cpr_data.get('height', 0)
    
    size_ok = cpr_size_kb >= min_cpr_size_kb
    dims_ok = cpr_width >= min_cpr_dimension and cpr_height >= min_cpr_dimension
    
    if size_ok and dims_ok:
        score += w_cpr_size
        feedback_parts.append(f"CPR size OK ({cpr_size_kb:.0f}KB, {cpr_width}x{cpr_height})")
    elif size_ok or dims_ok:
        score += w_cpr_size // 2
        feedback_parts.append(f"CPR size marginal ({cpr_size_kb:.0f}KB, {cpr_width}x{cpr_height})")
    else:
        if cpr_exists:
            feedback_parts.append(f"CPR too small ({cpr_size_kb:.0f}KB, {cpr_width}x{cpr_height})")
    
    details['cpr_size_kb'] = cpr_size_kb
    details['cpr_dimensions'] = f"{cpr_width}x{cpr_height}"
    
    # ============================================================
    # CRITERION 3: CPR image not blank (10 points)
    # ============================================================
    unique_colors = cpr_data.get('unique_colors', 0)
    
    if unique_colors >= 100:
        score += w_cpr_not_blank
        feedback_parts.append(f"CPR has content ({unique_colors} colors)")
    elif unique_colors >= 50:
        score += w_cpr_not_blank // 2
        feedback_parts.append(f"CPR may be low quality ({unique_colors} colors)")
    else:
        if cpr_exists:
            feedback_parts.append(f"CPR may be blank ({unique_colors} colors)")
    
    details['cpr_unique_colors'] = unique_colors
    
    # ============================================================
    # CRITERION 4: Curve file exists (10 points)
    # ============================================================
    curve_data = result.get('curve', {})
    curve_exists = curve_data.get('exists', False)
    
    if curve_exists:
        score += w_curve_exists
        feedback_parts.append("Curve file exists")
        details['curve_exists'] = True
    else:
        feedback_parts.append("Curve file NOT found")
        details['curve_exists'] = False
    
    # ============================================================
    # CRITERION 5: Minimum control points (15 points)
    # ============================================================
    num_points = curve_data.get('num_control_points', 0)
    
    if num_points >= min_control_points:
        score += w_min_points
        feedback_parts.append(f"Control points OK ({num_points})")
    elif num_points >= min_control_points * 0.75:
        score += w_min_points // 2
        feedback_parts.append(f"Control points marginal ({num_points})")
    else:
        if curve_exists:
            feedback_parts.append(f"Too few control points ({num_points})")
    
    details['num_control_points'] = num_points
    
    # ============================================================
    # CRITERION 6: Curve length adequate (15 points)
    # ============================================================
    curve_length = curve_data.get('length_mm', 0)
    
    if curve_length >= min_curve_length_mm:
        score += w_curve_length
        feedback_parts.append(f"Curve length OK ({curve_length:.0f}mm)")
    elif curve_length >= min_curve_length_mm * 0.75:
        score += w_curve_length // 2
        feedback_parts.append(f"Curve length marginal ({curve_length:.0f}mm)")
    else:
        if curve_exists and num_points > 0:
            feedback_parts.append(f"Curve too short ({curve_length:.0f}mm)")
    
    details['curve_length_mm'] = curve_length
    
    # ============================================================
    # CRITERION 7: Anatomical alignment (15 points)
    # ============================================================
    validation = result.get('validation', {})
    alignment_pct = validation.get('anatomical_alignment_pct', 0)
    points_near = validation.get('points_near_aorta', 0)
    
    if alignment_pct >= 75:
        score += w_alignment
        feedback_parts.append(f"Anatomical alignment good ({alignment_pct:.0f}%)")
    elif alignment_pct >= 50:
        score += w_alignment // 2
        feedback_parts.append(f"Anatomical alignment marginal ({alignment_pct:.0f}%)")
    elif alignment_pct > 0:
        score += w_alignment // 4
        feedback_parts.append(f"Poor alignment ({alignment_pct:.0f}%)")
    else:
        if num_points > 0:
            # Give partial credit if no ground truth available
            score += w_alignment // 3
            feedback_parts.append("Alignment not verified (no ground truth)")
    
    details['alignment_pct'] = alignment_pct
    details['points_near_aorta'] = points_near
    
    # ============================================================
    # CRITERION 8: VLM vessel confirmation (15 points)
    # ============================================================
    vlm_score = 0
    vlm_feedback = "VLM not available"
    
    # Try to use VLM on trajectory frames
    try:
        # Import VLM utilities
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
        except ImportError:
            # Try alternative import path
            import sys
            sys.path.insert(0, '/workspace/utils')
            from vlm_utils import sample_trajectory_frames, query_vlm
        
        # Get trajectory frames - use TRAJECTORY not just final
        frames = sample_trajectory_frames(traj, n=5) if traj else []
        
        if frames and len(frames) > 0:
            # Query VLM about the workflow progression
            vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The task was to create a curved planar reformation (CPR) of the aorta:
1. Navigate to find the aorta in CT scan
2. Create a curve along the aorta centerline using Markups
3. Generate a curved planar reformation using CPR module
4. Export the CPR image

Look at the progression of screenshots and assess:
1. Is there evidence of curve/markup placement on an abdominal CT? (colored line or points on the image)
2. Is there a curved planar reformation module dialog or output visible?
3. Does any image show a straightened/elongated tubular vessel structure (the CPR result)?
4. Was meaningful work performed progressing through the task steps?

Respond in JSON format:
{
    "curve_placement_visible": true/false,
    "cpr_module_used": true/false,
    "vessel_structure_visible": true/false,
    "meaningful_work_done": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                # Score based on VLM findings
                vlm_checks = 0
                if parsed.get('curve_placement_visible', False):
                    vlm_checks += 1
                if parsed.get('cpr_module_used', False):
                    vlm_checks += 1
                if parsed.get('vessel_structure_visible', False):
                    vlm_checks += 1
                if parsed.get('meaningful_work_done', False):
                    vlm_checks += 1
                
                if vlm_checks >= 3:
                    vlm_score = w_vlm
                    vlm_feedback = f"VLM confirms workflow ({vlm_checks}/4 checks)"
                elif vlm_checks >= 2:
                    vlm_score = w_vlm * 2 // 3
                    vlm_feedback = f"VLM partial confirmation ({vlm_checks}/4 checks)"
                elif vlm_checks >= 1:
                    vlm_score = w_vlm // 3
                    vlm_feedback = f"VLM minimal confirmation ({vlm_checks}/4 checks)"
                else:
                    vlm_feedback = "VLM could not confirm workflow"
                
                details['vlm_parsed'] = parsed
                details['vlm_checks'] = vlm_checks
            else:
                vlm_feedback = "VLM query failed"
        else:
            vlm_feedback = "No trajectory frames available"
            # Give partial credit if files exist
            if cpr_exists and curve_exists:
                vlm_score = w_vlm // 2
                vlm_feedback = "No VLM, but files exist"
                
    except ImportError as e:
        vlm_feedback = f"VLM module not available: {e}"
        # Give partial credit if outputs exist
        if cpr_exists and curve_exists:
            vlm_score = w_vlm // 2
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)}"
        logger.warning(f"VLM verification failed: {e}")
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ============================================================
    # ANTI-GAMING CHECKS
    # ============================================================
    
    # Check timestamps - files should be created during task
    cpr_created = cpr_data.get('created_during_task', False)
    curve_created = curve_data.get('created_during_task', False)
    files_created_during_task = cpr_created or curve_created
    
    if not files_created_during_task and (cpr_exists or curve_exists):
        # Files existed before task - likely gaming
        penalty = 20
        score = max(0, score - penalty)
        feedback_parts.append(f"WARNING: Files may predate task (-{penalty}pts)")
        details['timestamp_warning'] = True
    else:
        details['timestamp_warning'] = False
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Key criteria: both CPR image and curve file must exist
    key_criteria_met = cpr_exists and curve_exists
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Alternative pass: if one file missing but score still high
    if not passed and score >= 80:
        if cpr_exists or curve_exists:
            passed = True
            feedback_parts.append("Passed with partial outputs")
    
    # Cap score at 100
    score = min(100, max(0, score))
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }