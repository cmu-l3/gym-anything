#!/usr/bin/env python3
"""
Verifier for Coronary Artery Calcium Agatston Score task.

VERIFICATION METRICS:
1. Total Agatston Score Accuracy - compare to ground truth (±15% or ±15 points)
2. Risk Category Correctness - must match the appropriate category for the score
3. Per-Vessel Attribution - calcium attributed to correct coronary vessels
4. Lesion Detection - percentage of lesions identified
5. Report Completeness - all required fields present
6. Segmentation Quality - calcium properly isolated (HU >= 130 equivalent regions)

Pass threshold: 60 points with risk category correct
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


def get_risk_category(score):
    """Determine risk category from Agatston score."""
    if score == 0:
        return "No identifiable disease"
    elif score <= 10:
        return "Minimal plaque burden"
    elif score <= 100:
        return "Mild plaque burden"
    elif score <= 400:
        return "Moderate plaque burden"
    else:
        return "Severe plaque burden"


def normalize_category(cat_str):
    """Normalize risk category string for comparison."""
    if not cat_str:
        return ""
    cat_lower = cat_str.lower().strip()
    
    # Map various phrasings to canonical categories
    if "no " in cat_lower or cat_lower == "0" or "none" in cat_lower:
        return "none"
    elif "minimal" in cat_lower or "very low" in cat_lower:
        return "minimal"
    elif "mild" in cat_lower or "low" in cat_lower:
        return "mild"
    elif "moderate" in cat_lower or "medium" in cat_lower:
        return "moderate"
    elif "severe" in cat_lower or "high" in cat_lower or "extensive" in cat_lower:
        return "severe"
    return cat_lower


def categories_match(cat1, cat2):
    """Check if two risk categories are equivalent."""
    norm1 = normalize_category(cat1)
    norm2 = normalize_category(cat2)
    return norm1 == norm2


def verify_coronary_calcium_agatston(traj, env_info, task_info):
    """
    Verify coronary calcium Agatston score task completion.
    
    Scoring (100 points total):
    - Total Agatston score accuracy: 35 points (within ±15% or ±15 points)
    - Risk category correct: 20 points
    - Per-vessel attribution: 15 points (≥3 vessels within ±25%)
    - Lesion detection: 10 points (≥75% identified)
    - Report completeness: 10 points
    - Segmentation quality: 10 points
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
    
    score_error_pct = thresholds.get('score_error_percent', 15)
    score_error_min = thresholds.get('score_error_min_points', 15)
    
    w_score = weights.get('total_score_accuracy', 35)
    w_category = weights.get('risk_category_correct', 20)
    w_vessel = weights.get('per_vessel_attribution', 15)
    w_lesion = weights.get('lesion_detection', 10)
    w_report = weights.get('report_completeness', 10)
    w_seg = weights.get('segmentation_quality', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/calcium_task_result.json", temp_result.name)
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/calcium_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_score = gt_data.get('total_agatston_score', 0)
    gt_category = gt_data.get('risk_category', '')
    gt_vessel_scores = gt_data.get('per_vessel_scores', {})
    gt_lesion_count = gt_data.get('lesion_count', 0)
    
    details['gt_agatston_score'] = gt_score
    details['gt_risk_category'] = gt_category
    details['gt_vessel_scores'] = gt_vessel_scores
    details['gt_lesion_count'] = gt_lesion_count
    
    # ============================================================
    # LOAD AGENT'S REPORT
    # ============================================================
    agent_score = 0.0
    agent_category = ""
    agent_vessel_scores = {}
    agent_lesion_count = 0
    report_fields_present = []
    
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_report = {}
    try:
        copy_from_env("/tmp/agent_calcium_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        
        # Extract values with flexible field names
        agent_score = float(agent_report.get('total_agatston_score', 
                           agent_report.get('agatston_score',
                           agent_report.get('total_score',
                           agent_report.get('score', 0)))))
        
        agent_category = agent_report.get('risk_category',
                        agent_report.get('classification',
                        agent_report.get('risk', '')))
        
        agent_vessel_scores = agent_report.get('per_vessel_scores',
                             agent_report.get('vessel_scores', {}))
        
        agent_lesion_count = int(agent_report.get('lesion_count',
                               agent_report.get('num_lesions',
                               len(agent_report.get('lesions', [])))))
        
        # Track which fields are present
        if agent_score > 0 or 'total_agatston_score' in agent_report or 'agatston_score' in agent_report:
            report_fields_present.append('score')
        if agent_category:
            report_fields_present.append('category')
        if agent_vessel_scores:
            report_fields_present.append('vessel_scores')
        if agent_lesion_count > 0 or 'lesion_count' in agent_report:
            report_fields_present.append('lesion_count')
            
    except FileNotFoundError:
        logger.info("Agent report not found")
        # Try to get from result.json
        reported_score = result.get('reported_agatston_score', '')
        if reported_score:
            try:
                agent_score = float(reported_score)
                report_fields_present.append('score')
            except:
                pass
        reported_cat = result.get('reported_risk_category', '')
        if reported_cat:
            agent_category = reported_cat
            report_fields_present.append('category')
    except Exception as e:
        logger.warning(f"Error reading agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    details['agent_agatston_score'] = agent_score
    details['agent_risk_category'] = agent_category
    details['agent_vessel_scores'] = agent_vessel_scores
    details['agent_lesion_count'] = agent_lesion_count
    details['report_fields_present'] = report_fields_present
    
    # ============================================================
    # CRITERION 1: Total Agatston Score Accuracy (35 points)
    # ============================================================
    score_accurate = False
    score_error = abs(agent_score - gt_score)
    score_error_pct_actual = (score_error / gt_score * 100) if gt_score > 0 else (100 if agent_score > 0 else 0)
    
    # Allow either percentage error or absolute error
    allowed_error = max(gt_score * score_error_pct / 100, score_error_min)
    
    if score_error <= allowed_error:
        score += w_score
        score_accurate = True
        feedback_parts.append(f"✅ Agatston score accurate ({agent_score:.1f} vs {gt_score:.1f}, error: {score_error:.1f})")
    elif score_error <= allowed_error * 1.5:
        partial = int(w_score * 0.6)
        score += partial
        feedback_parts.append(f"⚠️ Agatston score partially accurate ({agent_score:.1f} vs {gt_score:.1f}, error: {score_error:.1f})")
    elif agent_score > 0:
        partial = int(w_score * 0.2)
        score += partial
        feedback_parts.append(f"❌ Agatston score inaccurate ({agent_score:.1f} vs {gt_score:.1f}, error: {score_error:.1f})")
    else:
        feedback_parts.append(f"❌ No Agatston score provided (expected: {gt_score:.1f})")
    
    details['score_error'] = score_error
    details['score_error_percent'] = score_error_pct_actual
    details['score_allowed_error'] = allowed_error
    
    # ============================================================
    # CRITERION 2: Risk Category Correct (20 points)
    # ============================================================
    category_correct = False
    
    # Calculate what category the agent's score would produce
    expected_category_from_score = get_risk_category(agent_score)
    
    if categories_match(agent_category, gt_category):
        score += w_category
        category_correct = True
        feedback_parts.append(f"✅ Risk category correct: {agent_category}")
    elif categories_match(expected_category_from_score, gt_category) and agent_score > 0:
        # Give partial credit if score implies correct category
        partial = int(w_category * 0.7)
        score += partial
        category_correct = True
        feedback_parts.append(f"⚠️ Risk category implied by score ({expected_category_from_score})")
    elif agent_category:
        feedback_parts.append(f"❌ Risk category incorrect: {agent_category} (expected: {gt_category})")
    else:
        feedback_parts.append(f"❌ No risk category provided (expected: {gt_category})")
    
    details['category_correct'] = category_correct
    
    # ============================================================
    # CRITERION 3: Per-Vessel Attribution (15 points)
    # ============================================================
    vessels_correct = 0
    vessels_checked = 0
    
    if agent_vessel_scores and gt_vessel_scores:
        for vessel in ['LM', 'LAD', 'LCx', 'RCA']:
            gt_v = gt_vessel_scores.get(vessel, 0)
            agent_v = agent_vessel_scores.get(vessel, agent_vessel_scores.get(vessel.lower(), 0))
            
            if gt_v > 0:
                vessels_checked += 1
                allowed_v_error = max(gt_v * 0.25, 5)  # 25% or 5 points
                if abs(agent_v - gt_v) <= allowed_v_error:
                    vessels_correct += 1
            elif agent_v == 0:
                # Both zero - correct
                vessels_correct += 1
                vessels_checked += 1
        
        if vessels_checked > 0:
            vessel_ratio = vessels_correct / vessels_checked
            vessel_points = int(w_vessel * vessel_ratio)
            score += vessel_points
            
            if vessels_correct >= 3:
                feedback_parts.append(f"✅ Per-vessel attribution good ({vessels_correct}/{vessels_checked} vessels)")
            else:
                feedback_parts.append(f"⚠️ Per-vessel attribution partial ({vessels_correct}/{vessels_checked} vessels)")
    else:
        feedback_parts.append("⚠️ Per-vessel scores not provided")
    
    details['vessels_correct'] = vessels_correct
    details['vessels_checked'] = vessels_checked
    
    # ============================================================
    # CRITERION 4: Lesion Detection (10 points)
    # ============================================================
    if gt_lesion_count > 0 and agent_lesion_count > 0:
        lesion_ratio = min(agent_lesion_count / gt_lesion_count, 1.5)  # Cap at 150%
        if 0.75 <= lesion_ratio <= 1.25:
            score += w_lesion
            feedback_parts.append(f"✅ Lesion count accurate ({agent_lesion_count} vs {gt_lesion_count})")
        elif 0.5 <= lesion_ratio <= 1.5:
            partial = int(w_lesion * 0.6)
            score += partial
            feedback_parts.append(f"⚠️ Lesion count partially accurate ({agent_lesion_count} vs {gt_lesion_count})")
        else:
            feedback_parts.append(f"❌ Lesion count inaccurate ({agent_lesion_count} vs {gt_lesion_count})")
    elif agent_lesion_count > 0:
        partial = int(w_lesion * 0.3)
        score += partial
        feedback_parts.append(f"⚠️ Lesions counted but cannot verify ({agent_lesion_count})")
    else:
        feedback_parts.append("⚠️ No lesion count provided")
    
    # ============================================================
    # CRITERION 5: Report Completeness (10 points)
    # ============================================================
    required_fields = ['score', 'category', 'vessel_scores', 'lesion_count']
    fields_present = len([f for f in required_fields if f in report_fields_present])
    report_completeness = fields_present / len(required_fields)
    
    report_points = int(w_report * report_completeness)
    score += report_points
    
    if fields_present == len(required_fields):
        feedback_parts.append("✅ Report complete with all required fields")
    elif fields_present > 0:
        feedback_parts.append(f"⚠️ Report partial ({fields_present}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("❌ Report missing or incomplete")
    
    # ============================================================
    # CRITERION 6: Segmentation Quality (10 points)
    # ============================================================
    seg_exists = result.get('segmentation_exists', False)
    seg_created = result.get('segmentation_created_during_task', False)
    seg_voxels = result.get('segmentation_voxels', 0)
    
    if seg_exists and seg_created:
        if seg_voxels > 10:  # At least some calcium segmented
            score += w_seg
            feedback_parts.append(f"✅ Segmentation created ({seg_voxels} voxels)")
        else:
            partial = int(w_seg * 0.5)
            score += partial
            feedback_parts.append("⚠️ Segmentation exists but appears empty")
    elif seg_exists:
        partial = int(w_seg * 0.3)
        score += partial
        feedback_parts.append("⚠️ Segmentation file exists but may not be from this task")
    else:
        feedback_parts.append("❌ No segmentation file created")
    
    # ============================================================
    # ANTI-GAMING: Check timestamps
    # ============================================================
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    if task_end > task_start and (task_end - task_start) < 30:
        # Suspiciously fast - might be gaming
        score = int(score * 0.5)
        feedback_parts.append("⚠️ Task completed suspiciously fast - possible gaming")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Pass requires: score >= 60 AND risk category correct (or implied correct)
    passed = score >= 60 and category_correct
    
    # Convert all numpy types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": min(100, score),  # Cap at 100
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "score_accuracy": score_accurate,
            "category_correct": category_correct,
            "vessels_attributed": vessels_correct,
            "report_complete": fields_present == len(required_fields),
            "segmentation_created": seg_exists and seg_created
        }
    }