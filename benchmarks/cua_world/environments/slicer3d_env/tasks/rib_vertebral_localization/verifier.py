#!/usr/bin/env python3
"""
Verifier for rib counting and vertebral level localization task.

VERIFICATION STRATEGY:
1. Nodule Level Accuracy - compare agent's vertebral level to ground truth
2. Rib Count Verification - check total rib pairs reported
3. Landmark Placement - verify T1, T6, T12 fiducials placed
4. Fiducial Consistency - T1-T12 distance in normal range (200-320mm)
5. Variant Detection - check if variants correctly identified
6. Report Completeness - all required fields present
7. VLM Trajectory Verification - confirm actual navigation and counting work

Scoring (100 points total):
- Nodule level exact: 35 points
- Nodule level ±1: 20 points (alternative to exact)
- Rib count correct: 15 points
- T1 landmark placed: 10 points
- T12 landmark placed: 10 points
- Variant detection: 10 points
- Report completeness: 10 points
- Fiducial consistency: 10 points
"""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vertebral_level(level_str: str) -> tuple:
    """
    Parse a vertebral level string into (region, number).
    
    Examples:
        "T5" -> ("T", 5)
        "L2" -> ("L", 2)
        "C7" -> ("C", 7)
    
    Returns:
        Tuple of (region_letter, level_number) or (None, None) if invalid
    """
    if not level_str:
        return None, None
    
    level_str = level_str.strip().upper()
    match = re.match(r'([TCLS])(\d+)', level_str)
    if match:
        return match.group(1), int(match.group(2))
    return None, None


def vertebral_level_distance(level1: str, level2: str) -> int:
    """
    Calculate the distance between two vertebral levels.
    
    Same region: absolute difference of numbers
    Adjacent regions: account for transition (C7->T1, T12->L1)
    
    Returns:
        Integer distance (0 = same level, 1 = adjacent, etc.)
        Returns 999 if incomparable
    """
    r1, n1 = parse_vertebral_level(level1)
    r2, n2 = parse_vertebral_level(level2)
    
    if r1 is None or r2 is None:
        return 999
    
    if r1 == r2:
        return abs(n1 - n2)
    
    # Handle region transitions
    # Spine order: C1-C7, T1-T12, L1-L5, S1-S5
    region_order = {'C': 0, 'T': 1, 'L': 2, 'S': 3}
    region_max = {'C': 7, 'T': 12, 'L': 5, 'S': 5}
    
    if r1 not in region_order or r2 not in region_order:
        return 999
    
    # Convert to absolute spine position
    def to_absolute(region, num):
        pos = 0
        for r in ['C', 'T', 'L', 'S']:
            if r == region:
                return pos + num
            pos += region_max[r]
        return pos + num
    
    abs1 = to_absolute(r1, n1)
    abs2 = to_absolute(r2, n2)
    
    return abs(abs1 - abs2)


def verify_rib_vertebral_localization(traj, env_info, task_info):
    """
    Verify rib counting and vertebral level localization task.
    
    Uses copy_from_env to read exported result data.
    Compares agent's findings against ground truth.
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
    
    w_nodule_exact = weights.get('nodule_level_exact', 35)
    w_nodule_within1 = weights.get('nodule_level_within_1', 20)
    w_rib_count = weights.get('rib_count_correct', 15)
    w_t1 = weights.get('t1_landmark_placed', 10)
    w_t12 = weights.get('t12_landmark_placed', 10)
    w_variants = weights.get('variant_detection', 10)
    w_report = weights.get('report_complete', 10)
    w_consistency = weights.get('fiducial_consistency', 10)
    
    expected_rib_pairs = metadata.get('expected_rib_pairs', 12)
    t1_t12_min = metadata.get('t1_t12_distance_min_mm', 200)
    t1_t12_max = metadata.get('t1_t12_distance_max_mm', 320)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/rib_task_result.json", temp_result.name)
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
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/ground_truth_vertebral.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # CRITERION 1: Nodule Vertebral Level (35 or 20 points)
    # ============================================================
    gt_nodule_level = gt_data.get('nodule_vertebral_level', 'T5')
    reported_level = result.get('reported_nodule_level', '')
    
    details['gt_nodule_level'] = gt_nodule_level
    details['reported_nodule_level'] = reported_level
    
    level_distance = vertebral_level_distance(reported_level, gt_nodule_level)
    details['level_distance'] = level_distance
    
    nodule_level_scored = False
    if level_distance == 0:
        score += w_nodule_exact
        feedback_parts.append(f"✓ Nodule level EXACT match ({reported_level})")
        nodule_level_scored = True
        details['nodule_level_exact'] = True
    elif level_distance == 1:
        score += w_nodule_within1
        feedback_parts.append(f"~ Nodule level within 1 ({reported_level} vs GT {gt_nodule_level})")
        nodule_level_scored = True
        details['nodule_level_exact'] = False
        details['nodule_level_within_1'] = True
    elif reported_level:
        feedback_parts.append(f"✗ Nodule level incorrect ({reported_level} vs GT {gt_nodule_level})")
        details['nodule_level_exact'] = False
        details['nodule_level_within_1'] = False
    else:
        feedback_parts.append("✗ Nodule level not reported")
        details['nodule_level_exact'] = False
        details['nodule_level_within_1'] = False
    
    # ============================================================
    # CRITERION 2: Rib Count (15 points)
    # ============================================================
    gt_rib_pairs = gt_data.get('total_rib_pairs', expected_rib_pairs)
    reported_rib_count = result.get('reported_rib_count', '')
    
    details['gt_rib_pairs'] = gt_rib_pairs
    details['reported_rib_count'] = reported_rib_count
    
    rib_count_correct = False
    if reported_rib_count:
        try:
            reported_count = int(reported_rib_count)
            # Allow ±1 for variant anatomy
            if abs(reported_count - gt_rib_pairs) <= 1:
                score += w_rib_count
                rib_count_correct = True
                feedback_parts.append(f"✓ Rib count correct ({reported_count})")
            else:
                feedback_parts.append(f"✗ Rib count incorrect ({reported_count} vs GT {gt_rib_pairs})")
        except ValueError:
            feedback_parts.append(f"✗ Invalid rib count format: {reported_rib_count}")
    else:
        feedback_parts.append("✗ Rib count not reported")
    
    details['rib_count_correct'] = rib_count_correct
    
    # ============================================================
    # CRITERION 3: T1 Landmark Placed (10 points)
    # ============================================================
    t1_placed = result.get('t1_placed', False)
    if t1_placed:
        score += w_t1
        feedback_parts.append("✓ T1 landmark placed")
    else:
        feedback_parts.append("✗ T1 landmark not found")
    details['t1_placed'] = t1_placed
    
    # ============================================================
    # CRITERION 4: T12 Landmark Placed (10 points)
    # ============================================================
    t12_placed = result.get('t12_placed', False)
    if t12_placed:
        score += w_t12
        feedback_parts.append("✓ T12 landmark placed")
    else:
        feedback_parts.append("✗ T12 landmark not found")
    details['t12_placed'] = t12_placed
    
    # ============================================================
    # CRITERION 5: Anatomical Variant Detection (10 points)
    # ============================================================
    gt_variants = gt_data.get('anatomical_variants', {})
    reported_variants = result.get('reported_variants', {})
    
    # Parse reported variants if it's a string
    if isinstance(reported_variants, str):
        try:
            reported_variants = json.loads(reported_variants)
        except:
            reported_variants = {}
    
    details['gt_variants'] = gt_variants
    details['reported_variants'] = reported_variants
    
    # Check each variant type
    variant_checks = ['cervical_rib', 'lumbar_rib', 'bifid_rib']
    variant_correct = 0
    
    for variant in variant_checks:
        gt_val = gt_variants.get(variant, False)
        reported_val = reported_variants.get(variant, False)
        if gt_val == reported_val:
            variant_correct += 1
    
    if variant_correct == len(variant_checks):
        score += w_variants
        feedback_parts.append("✓ Variant detection correct")
    elif variant_correct >= 2:
        score += int(w_variants * 0.6)
        feedback_parts.append(f"~ Variant detection partial ({variant_correct}/{len(variant_checks)})")
    else:
        feedback_parts.append(f"✗ Variant detection incorrect ({variant_correct}/{len(variant_checks)})")
    
    details['variant_correct_count'] = variant_correct
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    required_fields = [
        'reported_nodule_level',
        'reported_rib_count'
    ]
    
    fields_present = sum(1 for f in required_fields if result.get(f))
    
    details['report_exists'] = report_exists
    details['report_created_during_task'] = report_created_during_task
    details['fields_present'] = fields_present
    
    if report_exists and report_created_during_task and fields_present == len(required_fields):
        score += w_report
        feedback_parts.append("✓ Report complete and created during task")
    elif report_exists and fields_present >= 1:
        score += int(w_report * 0.5)
        feedback_parts.append(f"~ Report partial ({fields_present}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("✗ Report missing or incomplete")
    
    # ============================================================
    # CRITERION 7: Fiducial Consistency (10 points)
    # ============================================================
    t1_t12_distance_str = result.get('t1_t12_distance_mm', '')
    
    details['t1_t12_distance_mm'] = t1_t12_distance_str
    details['t1_t12_expected_range'] = f"{t1_t12_min}-{t1_t12_max}mm"
    
    if t1_t12_distance_str:
        try:
            t1_t12_distance = float(t1_t12_distance_str)
            if t1_t12_min <= t1_t12_distance <= t1_t12_max:
                score += w_consistency
                feedback_parts.append(f"✓ T1-T12 distance valid ({t1_t12_distance:.0f}mm)")
                details['t1_t12_valid'] = True
            else:
                feedback_parts.append(f"✗ T1-T12 distance out of range ({t1_t12_distance:.0f}mm, expected {t1_t12_min}-{t1_t12_max}mm)")
                details['t1_t12_valid'] = False
        except ValueError:
            feedback_parts.append("✗ Invalid T1-T12 distance")
            details['t1_t12_valid'] = False
    elif t1_placed and t12_placed:
        # Both landmarks placed but distance not calculated
        score += int(w_consistency * 0.5)
        feedback_parts.append("~ T1 and T12 placed but distance not measured")
        details['t1_t12_valid'] = None
    else:
        feedback_parts.append("✗ Cannot verify T1-T12 consistency (landmarks missing)")
        details['t1_t12_valid'] = False
    
    # ============================================================
    # VLM TRAJECTORY VERIFICATION (bonus/supplementary)
    # ============================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score_bonus = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if frames or final_screenshot:
                all_images = frames + ([final_screenshot] if final_screenshot else [])
                
                vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to:
1. Count ribs on a chest CT scan
2. Identify vertebral levels
3. Place fiducial markers at vertebral body centers

Look at the trajectory and determine:
1. Was the user navigating through different views (axial, coronal, sagittal)?
2. Were fiducial/markup tools used (you'd see marker icons or the Markups module)?
3. Does the final screenshot show reference markers placed on the spine?
4. Was there evidence of systematic rib counting (scrolling through slices)?

Respond in JSON format:
{
    "navigation_observed": true/false,
    "markup_tools_used": true/false,
    "markers_visible": true/false,
    "systematic_work": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}"""
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_images
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Check VLM assessment
                    navigation = parsed.get('navigation_observed', False)
                    markup_used = parsed.get('markup_tools_used', False)
                    markers_visible = parsed.get('markers_visible', False)
                    systematic = parsed.get('systematic_work', False)
                    
                    vlm_checks_passed = sum([navigation, markup_used, markers_visible, systematic])
                    
                    if vlm_checks_passed >= 3:
                        feedback_parts.append(f"✓ VLM confirms work done ({vlm_checks_passed}/4 checks)")
                    elif vlm_checks_passed >= 2:
                        feedback_parts.append(f"~ VLM partial confirmation ({vlm_checks_passed}/4 checks)")
                    else:
                        feedback_parts.append(f"? VLM inconclusive ({vlm_checks_passed}/4 checks)")
                    
                    details['vlm_checks_passed'] = vlm_checks_passed
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria for passing: nodule level must be scored AND report exists
    key_criteria_met = nodule_level_scored and result.get('report_exists', False)
    
    # Pass threshold: 55 points with key criteria
    passed = score >= 55 and key_criteria_met
    
    # Construct final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }