#!/usr/bin/env python3
"""
Verifier for measure_vertebral_compression_ratio task.

VERIFICATION CRITERIA:
1. Report JSON file exists (15 points)
2. All required fields present (10 points)
3. Anterior height accurate vs ground truth (15 points)
4. Posterior height accurate vs ground truth (15 points)
5. Compression ratio correctly calculated (15 points)
6. Classification matches ratio (10 points)
7. Markup nodes present in Slicer scene (10 points)
8. VLM visual confirmation of measurements (10 points)

Pass threshold: 70 points with report existing and ratio calculated
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vertebral_compression_ratio(traj, env_info, task_info):
    """
    Verify vertebral compression ratio measurement task completion.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
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
    expected_anterior = metadata.get('expected_anterior_height_mm', 28.5)
    expected_posterior = metadata.get('expected_posterior_height_mm', 32.0)
    expected_ratio = metadata.get('expected_compression_ratio', 0.8906)
    expected_classification = metadata.get('expected_classification', 'Normal')
    height_tolerance = metadata.get('height_tolerance_mm', 3.0)
    ratio_tolerance = metadata.get('ratio_tolerance', 0.05)
    plausible_range = metadata.get('plausible_height_range_mm', {"min": 15, "max": 45})
    
    weights = metadata.get('scoring_weights', {})
    w_report = weights.get('report_exists', 15)
    w_fields = weights.get('all_fields_present', 10)
    w_anterior = weights.get('anterior_height_accurate', 15)
    w_posterior = weights.get('posterior_height_accurate', 15)
    w_ratio = weights.get('ratio_correctly_calculated', 15)
    w_classification = weights.get('classification_correct', 10)
    w_markup = weights.get('markup_nodes_present', 10)
    w_vlm = weights.get('vlm_visual_confirmation', 10)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ============================================================
    # Copy result JSON from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/vcr_task_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("✗ Slicer was not running")
        # Don't return early - still check for report file
    else:
        feedback_parts.append("✓ Slicer was running")
    
    # Load ground truth from result (was embedded by export script)
    gt_data = result.get('ground_truth', {})
    if gt_data:
        expected_anterior = gt_data.get('anterior_height_mm', expected_anterior)
        expected_posterior = gt_data.get('posterior_height_mm', expected_posterior)
        expected_ratio = gt_data.get('compression_ratio', expected_ratio)
        expected_classification = gt_data.get('classification', expected_classification)
    
    details['expected_anterior_mm'] = expected_anterior
    details['expected_posterior_mm'] = expected_posterior
    details['expected_ratio'] = expected_ratio
    details['expected_classification'] = expected_classification
    
    # ============================================================
    # CRITERION 1: Report JSON exists (15 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    if report_exists:
        if report_created:
            score += w_report
            feedback_parts.append(f"✓ Report JSON created during task ({w_report} pts)")
        else:
            score += w_report // 2
            feedback_parts.append(f"~ Report exists but may be pre-existing ({w_report//2} pts)")
    else:
        feedback_parts.append(f"✗ Report JSON not found at expected path")
        # Without report, limited scoring possible
        
        # Still check for markup nodes
        markup_count = result.get('markup_line_count', 0)
        if markup_count >= 2:
            score += w_markup
            feedback_parts.append(f"✓ {markup_count} line markups in scene ({w_markup} pts)")
        elif markup_count == 1:
            score += w_markup // 2
            feedback_parts.append(f"~ Only 1 line markup (expected 2) ({w_markup//2} pts)")
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ============================================================
    # CRITERION 2: All required fields present (10 points)
    # ============================================================
    all_fields = result.get('all_fields_present', False)
    
    if all_fields:
        score += w_fields
        feedback_parts.append(f"✓ All required fields present ({w_fields} pts)")
    else:
        feedback_parts.append("✗ Missing required fields in report")
    
    # ============================================================
    # Extract reported values
    # ============================================================
    reported_anterior = 0.0
    reported_posterior = 0.0
    reported_ratio = 0.0
    reported_classification = ""
    
    try:
        ant_str = result.get('reported_anterior_height_mm', '')
        if ant_str:
            reported_anterior = float(ant_str)
    except (ValueError, TypeError):
        pass
    
    try:
        post_str = result.get('reported_posterior_height_mm', '')
        if post_str:
            reported_posterior = float(post_str)
    except (ValueError, TypeError):
        pass
    
    try:
        ratio_str = result.get('reported_compression_ratio', '')
        if ratio_str:
            reported_ratio = float(ratio_str)
    except (ValueError, TypeError):
        pass
    
    reported_classification = result.get('reported_classification', '').strip()
    
    details['reported_anterior_mm'] = reported_anterior
    details['reported_posterior_mm'] = reported_posterior
    details['reported_ratio'] = reported_ratio
    details['reported_classification'] = reported_classification
    
    # ============================================================
    # CRITERION 3: Anterior height accurate (15 points)
    # ============================================================
    if reported_anterior > 0:
        # Check plausibility
        if plausible_range['min'] <= reported_anterior <= plausible_range['max']:
            ant_diff = abs(reported_anterior - expected_anterior)
            details['anterior_diff_mm'] = ant_diff
            
            if ant_diff <= height_tolerance:
                score += w_anterior
                feedback_parts.append(f"✓ Anterior height accurate: {reported_anterior:.1f}mm (expected {expected_anterior:.1f}±{height_tolerance}mm) ({w_anterior} pts)")
            elif ant_diff <= height_tolerance * 2:
                score += w_anterior // 2
                feedback_parts.append(f"~ Anterior height close: {reported_anterior:.1f}mm (expected {expected_anterior:.1f}mm, diff {ant_diff:.1f}mm) ({w_anterior//2} pts)")
            else:
                feedback_parts.append(f"✗ Anterior height inaccurate: {reported_anterior:.1f}mm (expected {expected_anterior:.1f}mm, diff {ant_diff:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Anterior height implausible: {reported_anterior:.1f}mm (expected {plausible_range['min']}-{plausible_range['max']}mm)")
    else:
        feedback_parts.append("✗ No anterior height measurement")
    
    # ============================================================
    # CRITERION 4: Posterior height accurate (15 points)
    # ============================================================
    if reported_posterior > 0:
        if plausible_range['min'] <= reported_posterior <= plausible_range['max']:
            post_diff = abs(reported_posterior - expected_posterior)
            details['posterior_diff_mm'] = post_diff
            
            if post_diff <= height_tolerance:
                score += w_posterior
                feedback_parts.append(f"✓ Posterior height accurate: {reported_posterior:.1f}mm (expected {expected_posterior:.1f}±{height_tolerance}mm) ({w_posterior} pts)")
            elif post_diff <= height_tolerance * 2:
                score += w_posterior // 2
                feedback_parts.append(f"~ Posterior height close: {reported_posterior:.1f}mm (expected {expected_posterior:.1f}mm, diff {post_diff:.1f}mm) ({w_posterior//2} pts)")
            else:
                feedback_parts.append(f"✗ Posterior height inaccurate: {reported_posterior:.1f}mm (expected {expected_posterior:.1f}mm, diff {post_diff:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Posterior height implausible: {reported_posterior:.1f}mm")
    else:
        feedback_parts.append("✗ No posterior height measurement")
    
    # ============================================================
    # CRITERION 5: Compression ratio correctly calculated (15 points)
    # ============================================================
    ratio_calculated_correctly = False
    
    if reported_anterior > 0 and reported_posterior > 0:
        expected_calculated_ratio = reported_anterior / reported_posterior
        details['expected_calculated_ratio'] = round(expected_calculated_ratio, 4)
        
        if reported_ratio > 0:
            ratio_calc_diff = abs(reported_ratio - expected_calculated_ratio)
            details['ratio_calculation_diff'] = ratio_calc_diff
            
            if ratio_calc_diff <= 0.01:
                score += w_ratio
                ratio_calculated_correctly = True
                feedback_parts.append(f"✓ Ratio correctly calculated: {reported_ratio:.4f} (from {reported_anterior:.1f}/{reported_posterior:.1f}) ({w_ratio} pts)")
            elif ratio_calc_diff <= 0.05:
                score += w_ratio // 2
                feedback_parts.append(f"~ Ratio calculation slightly off: {reported_ratio:.4f} vs expected {expected_calculated_ratio:.4f} ({w_ratio//2} pts)")
            else:
                feedback_parts.append(f"✗ Ratio miscalculated: {reported_ratio:.4f} vs expected {expected_calculated_ratio:.4f}")
        else:
            feedback_parts.append("✗ No compression ratio reported")
    else:
        feedback_parts.append("✗ Cannot verify ratio - missing height measurements")
    
    # ============================================================
    # CRITERION 6: Classification correct (10 points)
    # ============================================================
    if reported_classification and reported_ratio > 0:
        # Determine expected classification based on reported ratio
        if reported_ratio >= 0.85:
            expected_class = "Normal"
        elif reported_ratio >= 0.75:
            expected_class = "Mild"
        elif reported_ratio >= 0.60:
            expected_class = "Moderate"
        else:
            expected_class = "Severe"
        
        details['expected_class_for_ratio'] = expected_class
        
        if reported_classification.lower() == expected_class.lower():
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {reported_classification} for ratio {reported_ratio:.3f} ({w_classification} pts)")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {reported_classification} (expected {expected_class} for ratio {reported_ratio:.3f})")
    elif reported_classification:
        feedback_parts.append(f"~ Classification provided ({reported_classification}) but cannot verify without ratio")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ============================================================
    # CRITERION 7: Markup nodes present (10 points)
    # ============================================================
    markup_count = result.get('markup_line_count', 0)
    details['markup_line_count'] = markup_count
    
    if markup_count >= 2:
        score += w_markup
        feedback_parts.append(f"✓ {markup_count} line measurements in Slicer scene ({w_markup} pts)")
    elif markup_count == 1:
        score += w_markup // 2
        feedback_parts.append(f"~ Only 1 line measurement found (expected 2) ({w_markup//2} pts)")
    else:
        feedback_parts.append("✗ No line measurements found in Slicer scene")
    
    # ============================================================
    # CRITERION 8: VLM visual confirmation (10 points)
    # ============================================================
    call_vlm = env_info.get('call_vlm')
    vlm_confirmed = False
    
    if call_vlm:
        try:
            # Copy final screenshot
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final_screenshot.png", temp_screenshot.name)
                
                # Check screenshot size
                screenshot_size = os.path.getsize(temp_screenshot.name)
                if screenshot_size > 50000:  # > 50KB
                    vlm_prompt = """Analyze this 3D Slicer screenshot for vertebral body measurement.

Look for:
1. Is a sagittal view of the spine visible (side view showing vertebrae stacked)?
2. Are there ruler/line measurement annotations visible on a vertebral body?
3. Do the measurements appear to span from top to bottom of a vertebral body (measuring height)?

Respond in JSON format:
{
    "sagittal_spine_visible": true/false,
    "measurements_visible": true/false,
    "measurements_on_vertebra": true/false,
    "confidence": "low"/"medium"/"high",
    "observation": "brief description"
}"""
                    
                    vlm_result = call_vlm(prompt=vlm_prompt, image=temp_screenshot.name)
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_response'] = parsed
                        
                        meas_visible = parsed.get('measurements_visible', False)
                        spine_visible = parsed.get('sagittal_spine_visible', False)
                        on_vertebra = parsed.get('measurements_on_vertebra', False)
                        
                        if meas_visible and spine_visible:
                            if on_vertebra:
                                score += w_vlm
                                vlm_confirmed = True
                                feedback_parts.append(f"✓ VLM confirms measurements on vertebra ({w_vlm} pts)")
                            else:
                                score += w_vlm // 2
                                feedback_parts.append(f"~ VLM sees measurements but uncertain if on vertebra ({w_vlm//2} pts)")
                        elif meas_visible or spine_visible:
                            score += w_vlm // 3
                            feedback_parts.append(f"~ VLM partial confirmation ({w_vlm//3} pts)")
                        else:
                            feedback_parts.append("✗ VLM did not confirm measurements")
                    else:
                        feedback_parts.append("~ VLM query failed")
                else:
                    feedback_parts.append("~ Screenshot too small for VLM analysis")
            finally:
                if os.path.exists(temp_screenshot.name):
                    os.unlink(temp_screenshot.name)
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"~ VLM verification skipped: {e}")
    else:
        feedback_parts.append("~ VLM not available")
    
    # ============================================================
    # Final assessment
    # ============================================================
    # Key criteria: report exists, ratio calculated
    key_criteria_met = report_exists and ratio_calculated_correctly
    passed = score >= 70 and key_criteria_met
    
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    # Summary
    feedback_parts.append("")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Total Score: {score}/100")
    feedback_parts.append(f"Pass Threshold: 70 with report + ratio calculated")
    feedback_parts.append(f"Result: {'PASS' if passed else 'FAIL'}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }