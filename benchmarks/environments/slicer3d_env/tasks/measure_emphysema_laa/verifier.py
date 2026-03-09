#!/usr/bin/env python3
"""
Verifier for Emphysema LAA% Measurement task.

VERIFICATION STRATEGY (Multi-Signal + Anti-Gaming):

Programmatic checks (90 points):
1. JSON file exists at expected path (15 points)
2. Required fields present (15 points)
3. Total lung volume in valid range (15 points)
4. LAA% calculated and in plausible range (20 points)
5. Values internally consistent (ratio = percentage) (15 points)
6. Threshold value documented (10 points)

VLM check (10 points):
7. Trajectory shows lung segmentation workflow (10 points)

Anti-gaming measures:
- File must be created DURING task (timestamp check)
- Values must be internally consistent (can't just copy numbers)
- Lung volume must be physiologically plausible
- LAA% must be within expected range for this patient

Pass threshold: 70 points with key criteria met
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_emphysema_laa(traj, env_info, task_info):
    """
    Verify emphysema LAA% measurement task completion.
    
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
    output_path = metadata.get('output_path', '/home/ga/Documents/SlicerData/Exports/emphysema_analysis.json')
    lung_volume_range = metadata.get('total_lung_volume_range_ml', {"min": 3000, "max": 8000})
    laa_range = metadata.get('laa_percent_plausible_range', {"min": 0, "max": 50})
    laa_tolerance = metadata.get('laa_tolerance_percent', 5)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('json_file_exists', 15)
    w_fields_present = weights.get('required_fields_present', 15)
    w_lung_volume = weights.get('total_lung_volume_valid', 15)
    w_laa_calculated = weights.get('laa_percent_calculated', 20)
    w_consistent = weights.get('values_internally_consistent', 15)
    w_threshold = weights.get('threshold_documented', 10)
    w_vlm = weights.get('vlm_confirms_visualization', 10)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/emphysema_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    # ================================================================
    # CRITERION 1: JSON FILE EXISTS (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists:
        if file_created_during_task:
            score += w_file_exists
            feedback_parts.append("Output file created during task")
        else:
            # File existed before - partial credit
            score += w_file_exists * 0.5
            feedback_parts.append("Output file exists (but may pre-exist)")
    else:
        feedback_parts.append("Output file NOT found")
        # Early exit - can't verify anything else meaningfully
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"file_exists": False}
        }
    
    details['file_exists'] = output_exists
    details['file_created_during_task'] = file_created_during_task
    
    # ================================================================
    # CRITERION 2: REQUIRED FIELDS PRESENT (15 points)
    # ================================================================
    has_required = result.get('has_required_fields', False)
    json_valid = result.get('json_valid', False)
    
    if json_valid and has_required:
        score += w_fields_present
        feedback_parts.append("All required fields present")
    elif json_valid:
        score += w_fields_present * 0.5
        feedback_parts.append("JSON valid but missing some fields")
    else:
        feedback_parts.append("Invalid JSON or missing fields")
    
    details['json_valid'] = json_valid
    details['has_required_fields'] = has_required
    
    # ================================================================
    # CRITERION 3: TOTAL LUNG VOLUME VALID (15 points)
    # ================================================================
    reported_lung_vol_str = result.get('reported_total_lung_volume_ml', '')
    
    try:
        reported_lung_vol = float(reported_lung_vol_str) if reported_lung_vol_str else 0
    except (ValueError, TypeError):
        reported_lung_vol = 0
    
    details['reported_lung_volume_ml'] = reported_lung_vol
    
    if reported_lung_vol > 0:
        min_vol = lung_volume_range.get('min', 3000)
        max_vol = lung_volume_range.get('max', 8000)
        
        if min_vol <= reported_lung_vol <= max_vol:
            score += w_lung_volume
            feedback_parts.append(f"Lung volume valid ({reported_lung_vol:.0f} mL)")
        elif reported_lung_vol > 0:
            # Outside expected range but not zero
            score += w_lung_volume * 0.5
            feedback_parts.append(f"Lung volume out of range ({reported_lung_vol:.0f} mL)")
        else:
            feedback_parts.append("Invalid lung volume")
    else:
        feedback_parts.append("No lung volume reported")
    
    # ================================================================
    # CRITERION 4: LAA% CALCULATED (20 points)
    # ================================================================
    reported_laa_str = result.get('reported_laa_percent', '')
    
    try:
        reported_laa = float(reported_laa_str) if reported_laa_str else -1
    except (ValueError, TypeError):
        reported_laa = -1
    
    details['reported_laa_percent'] = reported_laa
    
    if reported_laa >= 0:
        min_laa = laa_range.get('min', 0)
        max_laa = laa_range.get('max', 50)
        
        if min_laa <= reported_laa <= max_laa:
            score += w_laa_calculated
            feedback_parts.append(f"LAA% in valid range ({reported_laa:.1f}%)")
        elif 0 <= reported_laa <= 100:
            # Outside expected but technically possible
            score += w_laa_calculated * 0.5
            feedback_parts.append(f"LAA% outside typical range ({reported_laa:.1f}%)")
        else:
            feedback_parts.append(f"LAA% invalid ({reported_laa})")
    else:
        feedback_parts.append("No LAA% reported")
    
    # Check against ground truth if available
    gt_laa_str = result.get('gt_laa_percent', '')
    try:
        gt_laa = float(gt_laa_str) if gt_laa_str else -1
    except (ValueError, TypeError):
        gt_laa = -1
    
    details['gt_laa_percent'] = gt_laa
    
    if gt_laa >= 0 and reported_laa >= 0:
        laa_error = abs(reported_laa - gt_laa)
        details['laa_error_percent'] = laa_error
        
        if laa_error <= laa_tolerance:
            feedback_parts.append(f"LAA% matches reference (within {laa_tolerance}%)")
        else:
            feedback_parts.append(f"LAA% differs from reference by {laa_error:.1f}%")
    
    # ================================================================
    # CRITERION 5: VALUES INTERNALLY CONSISTENT (15 points)
    # ================================================================
    values_consistent = result.get('values_internally_consistent', False)
    
    # Also verify ourselves
    reported_emph_str = result.get('reported_emphysema_volume_ml', '')
    try:
        reported_emph = float(reported_emph_str) if reported_emph_str else 0
    except (ValueError, TypeError):
        reported_emph = 0
    
    details['reported_emphysema_volume_ml'] = reported_emph
    
    internal_consistency_verified = False
    if reported_lung_vol > 0 and reported_emph >= 0 and reported_laa >= 0:
        calculated_laa = (reported_emph / reported_lung_vol) * 100.0
        laa_diff = abs(calculated_laa - reported_laa)
        
        details['calculated_laa_percent'] = calculated_laa
        details['laa_calculation_diff'] = laa_diff
        
        if laa_diff <= 1.0:  # Within 1% tolerance
            internal_consistency_verified = True
    
    if values_consistent or internal_consistency_verified:
        score += w_consistent
        feedback_parts.append("Values internally consistent")
    elif reported_emph > 0 and reported_lung_vol > 0:
        score += w_consistent * 0.5
        feedback_parts.append("Values present but inconsistent")
    else:
        feedback_parts.append("Cannot verify internal consistency")
    
    details['values_consistent'] = values_consistent or internal_consistency_verified
    
    # ================================================================
    # CRITERION 6: THRESHOLD DOCUMENTED (10 points)
    # ================================================================
    reported_threshold_str = result.get('reported_threshold_hu', '')
    
    try:
        reported_threshold = float(reported_threshold_str) if reported_threshold_str else 0
    except (ValueError, TypeError):
        reported_threshold = 0
    
    details['reported_threshold_hu'] = reported_threshold
    
    # Standard emphysema threshold is -950 HU
    if reported_threshold == -950:
        score += w_threshold
        feedback_parts.append("Correct threshold (-950 HU)")
    elif reported_threshold < -900:
        score += w_threshold * 0.7
        feedback_parts.append(f"Threshold documented ({reported_threshold} HU)")
    elif reported_threshold != 0:
        score += w_threshold * 0.3
        feedback_parts.append(f"Non-standard threshold ({reported_threshold} HU)")
    else:
        feedback_parts.append("Threshold not documented")
    
    # ================================================================
    # CRITERION 7: VLM TRAJECTORY VERIFICATION (10 points)
    # ================================================================
    vlm_score = 0
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample trajectory frames
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging task.
            
The task is emphysema quantification on chest CT:
1. Loading chest CT data
2. Creating lung segmentation 
3. Identifying low-attenuation areas (emphysema)
4. Calculating statistics

Look for evidence of:
- Chest CT images displayed (lung fields visible, dark areas = air/lung)
- Segment Editor module being used
- Segmentation visible on the CT images
- Segment Statistics or measurement results

Respond in JSON:
{
    "ct_images_visible": true/false,
    "lung_parenchyma_visible": true/false,
    "segmentation_work_visible": true/false,
    "segment_editor_used": true/false,
    "statistics_visible": true/false,
    "workflow_evidence": "describe what you see",
    "confidence": "low/medium/high"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                ct_visible = parsed.get('ct_images_visible', False)
                seg_visible = parsed.get('segmentation_work_visible', False)
                editor_used = parsed.get('segment_editor_used', False)
                
                if seg_visible or editor_used:
                    vlm_score = w_vlm
                    feedback_parts.append("VLM confirms segmentation workflow")
                elif ct_visible:
                    vlm_score = w_vlm * 0.5
                    feedback_parts.append("VLM sees CT images")
                else:
                    feedback_parts.append("VLM: limited workflow evidence")
            else:
                details['vlm_error'] = "VLM query failed"
                feedback_parts.append("VLM verification unavailable")
        else:
            details['vlm_error'] = "No trajectory frames"
            feedback_parts.append("No trajectory for VLM")
            
    except ImportError:
        details['vlm_error'] = "VLM module not available"
        feedback_parts.append("VLM not available")
    except Exception as e:
        details['vlm_error'] = str(e)
        feedback_parts.append(f"VLM error: {str(e)[:50]}")
    
    score += vlm_score
    
    # ================================================================
    # CLASSIFICATION CHECK (bonus info, not scored separately)
    # ================================================================
    reported_classification = result.get('reported_classification', '')
    gt_classification = result.get('gt_classification', '')
    
    details['reported_classification'] = reported_classification
    details['gt_classification'] = gt_classification
    
    # Verify classification matches LAA%
    expected_classification = ""
    if reported_laa >= 0:
        if reported_laa < 5:
            expected_classification = "Normal"
        elif reported_laa < 15:
            expected_classification = "Mild"
        elif reported_laa < 25:
            expected_classification = "Moderate"
        else:
            expected_classification = "Severe"
    
    details['expected_classification'] = expected_classification
    
    classification_correct = False
    if reported_classification and expected_classification:
        # Flexible matching
        if reported_classification.lower() in expected_classification.lower() or \
           expected_classification.lower() in reported_classification.lower():
            classification_correct = True
    
    details['classification_correct'] = classification_correct
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_file_exists + w_fields_present + w_lung_volume + w_laa_calculated + \
                w_consistent + w_threshold + w_vlm
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        reported_laa >= 0 and
        reported_lung_vol > 0
    )
    
    passed = score >= 70 and key_criteria_met
    
    details['max_score'] = max_score
    details['key_criteria_met'] = key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }