#!/usr/bin/env python3
"""
Verifier for gastric volume estimation task for bariatric surgery planning.

VERIFICATION METRICS:
1. Dice Coefficient - overlap between agent segmentation and ground truth stomach
2. Volume Accuracy - how close is measured volume to ground truth
3. Classification Correctness - did agent classify size correctly
4. Segmentation Quality:
   - Single connected component (stomach is one organ)
   - No spillover into adjacent organs (liver, spleen)
5. Report Completeness - all required fields present

AMOS Labels:
- 9: Stomach (target)
- 6: Liver (should not be included)
- 1: Spleen (should not be included)
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if isinstance(val, (np.integer, np.int32, np.int64)):
        return int(val)
    elif isinstance(val, (np.floating, np.float32, np.float64)):
        return float(val)
    elif isinstance(val, np.ndarray):
        return val.tolist()
    elif isinstance(val, np.bool_):
        return bool(val)
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def classify_stomach_size(volume_ml):
    """Classify stomach size based on volume."""
    if volume_ml < 400:
        return "Small"
    elif volume_ml < 1000:
        return "Normal"
    elif volume_ml < 1500:
        return "Enlarged"
    else:
        return "Markedly_enlarged"


def verify_gastric_volume(traj, env_info, task_info):
    """
    Verify gastric volume estimation task completion.

    Scoring (100 points total + 15 bonus):
    - Dice coefficient >= 0.70: 30 points
    - Dice >= 0.80 bonus: 10 points
    - Volume within 20%: 20 points
    - Volume within 10% bonus: 5 points
    - Correct classification: 15 points
    - Segmentation contiguous: 10 points
    - No organ spillover: 5 points
    - Report complete: 10 points
    - Valid recommendation: 5 points
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
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})

    dice_min = thresholds.get('dice_minimum', 0.60)
    dice_good = thresholds.get('dice_good', 0.70)
    dice_excellent = thresholds.get('dice_excellent', 0.80)
    vol_err_max = thresholds.get('volume_error_max_percent', 30)
    vol_err_good = thresholds.get('volume_error_good_percent', 20)
    vol_err_excellent = thresholds.get('volume_error_excellent_percent', 10)
    spillover_max = thresholds.get('spillover_max_percent', 5)

    w_dice = weights.get('dice_coefficient', 30)
    w_dice_bonus = weights.get('dice_bonus', 10)
    w_volume = weights.get('volume_accuracy', 20)
    w_volume_bonus = weights.get('volume_bonus', 5)
    w_classification = weights.get('correct_classification', 15)
    w_contiguous = weights.get('segmentation_contiguous', 10)
    w_spillover = weights.get('no_organ_spillover', 5)
    w_report = weights.get('report_complete', 10)
    w_recommendation = weights.get('valid_recommendation', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/gastric_task_result.json", temp_result.name)
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ============================================================
    # CHECK SEGMENTATION EXISTS
    # ============================================================
    if not result.get('agent_segmentation_exists', False):
        feedback_parts.append("No segmentation file found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": {"segmentation_exists": False}
        }

    # Check if created during task (anti-gaming)
    if not result.get('segmentation_created_during_task', False):
        feedback_parts.append("Segmentation file may have existed before task (anti-gaming check)")
        # Don't fail, but note it
        details['anti_gaming_warning'] = True

    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/stomach_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_volume_ml = gt_data.get('stomach_volume_ml', 0)
    gt_classification = gt_data.get('classification', '')

    details['gt_volume_ml'] = gt_volume_ml
    details['gt_classification'] = gt_classification

    # ============================================================
    # LOAD PRE-COMPUTED METRICS (from export script)
    # ============================================================
    temp_metrics = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    metrics = {}
    try:
        copy_from_env("/tmp/gastric_seg_metrics.json", temp_metrics.name)
        with open(temp_metrics.name, 'r') as f:
            metrics = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load metrics: {e}")
    finally:
        if os.path.exists(temp_metrics.name):
            os.unlink(temp_metrics.name)

    # ============================================================
    # CRITERION 1: DICE COEFFICIENT (30 + 10 bonus points)
    # ============================================================
    dice = 0.0
    dice_str = result.get('computed_dice', '')
    if dice_str:
        try:
            dice = float(dice_str)
        except ValueError:
            pass
    
    if not dice and 'dice_coefficient' in metrics:
        dice = metrics.get('dice_coefficient', 0)

    details['dice_coefficient'] = dice

    if dice >= dice_excellent:
        score += w_dice + w_dice_bonus
        feedback_parts.append(f"Excellent segmentation overlap (Dice={dice:.3f})")
    elif dice >= dice_good:
        score += w_dice
        feedback_parts.append(f"Good segmentation overlap (Dice={dice:.3f})")
    elif dice >= dice_min:
        score += int(w_dice * 0.7)
        feedback_parts.append(f"Acceptable segmentation (Dice={dice:.3f})")
    elif dice > 0:
        score += int(w_dice * 0.3)
        feedback_parts.append(f"Poor segmentation overlap (Dice={dice:.3f})")
    else:
        feedback_parts.append("No valid Dice coefficient computed")

    # ============================================================
    # CRITERION 2: VOLUME ACCURACY (20 + 5 bonus points)
    # ============================================================
    agent_volume = 0.0
    vol_str = result.get('computed_volume_ml', '')
    if vol_str:
        try:
            agent_volume = float(vol_str)
        except ValueError:
            pass
    
    if not agent_volume and 'agent_volume_ml' in metrics:
        agent_volume = metrics.get('agent_volume_ml', 0)

    details['agent_volume_ml'] = agent_volume

    if gt_volume_ml > 0 and agent_volume > 0:
        volume_error_pct = abs(agent_volume - gt_volume_ml) / gt_volume_ml * 100
        details['volume_error_percent'] = round(volume_error_pct, 2)

        if volume_error_pct <= vol_err_excellent:
            score += w_volume + w_volume_bonus
            feedback_parts.append(f"Excellent volume accuracy ({agent_volume:.1f}mL vs {gt_volume_ml:.1f}mL, error={volume_error_pct:.1f}%)")
        elif volume_error_pct <= vol_err_good:
            score += w_volume
            feedback_parts.append(f"Good volume accuracy ({agent_volume:.1f}mL, error={volume_error_pct:.1f}%)")
        elif volume_error_pct <= vol_err_max:
            score += int(w_volume * 0.6)
            feedback_parts.append(f"Acceptable volume ({agent_volume:.1f}mL, error={volume_error_pct:.1f}%)")
        else:
            feedback_parts.append(f"Volume inaccurate ({agent_volume:.1f}mL vs {gt_volume_ml:.1f}mL, error={volume_error_pct:.1f}%)")
    else:
        feedback_parts.append("Could not verify volume accuracy")

    # ============================================================
    # CRITERION 3: CORRECT CLASSIFICATION (15 points)
    # ============================================================
    reported_classification = result.get('reported_classification', '')
    details['reported_classification'] = reported_classification

    # Also compute expected classification from agent's volume
    if agent_volume > 0:
        computed_classification = classify_stomach_size(agent_volume)
        details['computed_classification'] = computed_classification
    else:
        computed_classification = ''

    classification_correct = False
    if reported_classification and gt_classification:
        # Normalize for comparison
        reported_norm = reported_classification.lower().replace('_', '').replace(' ', '')
        gt_norm = gt_classification.lower().replace('_', '').replace(' ', '')
        
        if reported_norm == gt_norm:
            classification_correct = True
            score += w_classification
            feedback_parts.append(f"Correct classification: {reported_classification}")
        else:
            feedback_parts.append(f"Classification incorrect: reported '{reported_classification}', expected '{gt_classification}'")
    elif not reported_classification:
        feedback_parts.append("No classification reported")
    else:
        feedback_parts.append("Could not verify classification")

    details['classification_correct'] = classification_correct

    # ============================================================
    # CRITERION 4: SEGMENTATION CONTIGUOUS (10 points)
    # ============================================================
    is_contiguous = result.get('segmentation_is_contiguous', False)
    if isinstance(is_contiguous, str):
        is_contiguous = is_contiguous.lower() == 'true'
    
    details['is_contiguous'] = is_contiguous

    if is_contiguous:
        score += w_contiguous
        feedback_parts.append("Segmentation is contiguous (single component)")
    else:
        num_components = metrics.get('num_components', 0)
        feedback_parts.append(f"Segmentation not contiguous ({num_components} components)")

    # ============================================================
    # CRITERION 5: NO ORGAN SPILLOVER (5 points)
    # ============================================================
    spillover_liver = 0.0
    spillover_spleen = 0.0
    
    try:
        spillover_liver = float(result.get('spillover_liver_percent', 0))
        spillover_spleen = float(result.get('spillover_spleen_percent', 0))
    except (ValueError, TypeError):
        pass

    details['spillover_liver_percent'] = spillover_liver
    details['spillover_spleen_percent'] = spillover_spleen

    total_spillover = spillover_liver + spillover_spleen
    if total_spillover < spillover_max:
        score += w_spillover
        feedback_parts.append(f"Minimal organ spillover ({total_spillover:.1f}%)")
    else:
        feedback_parts.append(f"Excessive organ spillover ({total_spillover:.1f}% into liver/spleen)")

    # ============================================================
    # CRITERION 6: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    reported_volume = result.get('reported_volume_ml', '')
    reported_fundus = result.get('reported_fundus_included', '')
    reported_recommendation = result.get('reported_recommendation', '')

    report_fields_present = 0
    required_fields = 4

    if reported_volume:
        report_fields_present += 1
    if reported_classification:
        report_fields_present += 1
    if reported_fundus:
        report_fields_present += 1
    if reported_recommendation:
        report_fields_present += 1

    details['report_fields_present'] = report_fields_present

    if report_exists and report_fields_present >= 3:
        score += w_report
        feedback_parts.append(f"Report complete ({report_fields_present}/{required_fields} fields)")
    elif report_exists:
        score += int(w_report * report_fields_present / required_fields)
        feedback_parts.append(f"Report partially complete ({report_fields_present}/{required_fields} fields)")
    else:
        feedback_parts.append("No report file found")

    # ============================================================
    # CRITERION 7: VALID RECOMMENDATION (5 points)
    # ============================================================
    if reported_recommendation:
        # Check if recommendation seems reasonable (non-empty, mentions surgery or stomach)
        rec_lower = reported_recommendation.lower()
        if any(kw in rec_lower for kw in ['surgery', 'sleeve', 'gastric', 'bariatric', 'proceed', 'consider', 'recommend', 'standard', 'modified']):
            score += w_recommendation
            feedback_parts.append("Valid surgical recommendation provided")
        else:
            score += int(w_recommendation * 0.5)
            feedback_parts.append("Recommendation provided but may not be clinically specific")
    else:
        feedback_parts.append("No surgical recommendation provided")

    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Must have: reasonable Dice AND volume within range AND segmentation exists
    key_criteria_met = (
        dice >= dice_min and 
        result.get('agent_segmentation_exists', False) and
        (agent_volume > 50 and agent_volume < 3000)  # Sanity check
    )

    passed = score >= 60 and key_criteria_met

    details['key_criteria_met'] = key_criteria_met

    # ============================================================
    # COMPILE RESULT
    # ============================================================
    feedback = " | ".join(feedback_parts)

    return to_python_type({
        "passed": passed,
        "score": min(score, 115),  # Cap at max with bonuses
        "feedback": feedback,
        "details": details,
        "subscores": {
            "dice_coefficient": dice,
            "volume_accuracy": details.get('volume_error_percent', 100),
            "classification_correct": classification_correct,
            "segmentation_contiguous": is_contiguous,
            "organ_spillover_percent": total_spillover,
            "report_completeness": report_fields_present / required_fields
        }
    })