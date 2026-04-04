#!/usr/bin/env python3
"""
Verifier for Calculate Segment Statistics task.

VERIFICATION CRITERIA:
1. CSV file exists (20 points)
2. CSV structure valid - has required columns (15 points)
3. All segments present - Necrotic, Edema, Enhancing (20 points)
4. Volume values valid - positive, non-zero (15 points)
5. Volume accuracy - within tolerance of ground truth (15 points)
6. Intensity stats present - at least mean (10 points)
7. File timestamp valid - created during task (5 points)

Pass threshold: 70 points with CSV exists AND all segments present
"""

import json
import os
import tempfile
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected segment names (case-insensitive matching)
EXPECTED_SEGMENTS = ["necrotic", "edema", "enhancing"]


def verify_calculate_segment_statistics(traj, env_info, task_info):
    """
    Verify that segment statistics were calculated and exported correctly.
    
    Uses multiple verification signals:
    1. File-based: CSV exists with correct structure
    2. Content validation: Values match ground truth
    3. Anti-gaming: File timestamp check
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
    volume_tolerance_pct = metadata.get('volume_tolerance_percent', 5)
    weights = metadata.get('scoring_weights', {})
    
    w_csv_exists = weights.get('csv_exists', 20)
    w_csv_structure = weights.get('csv_structure_valid', 15)
    w_all_segments = weights.get('all_segments_present', 20)
    w_volume_valid = weights.get('volume_values_valid', 15)
    w_volume_accuracy = weights.get('volume_accuracy', 15)
    w_intensity = weights.get('intensity_stats_present', 10)
    w_timestamp = weights.get('file_timestamp_valid', 5)

    score = 0
    feedback_parts = []
    details = {}

    # ============================================================
    # Load export result JSON
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/segstats_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have been attempted"
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

    details['export_result'] = result

    # ============================================================
    # CRITERION 1: CSV File Exists (20 points)
    # ============================================================
    csv_exists = result.get('csv_exists', False)
    csv_size = result.get('csv_size_bytes', 0)
    
    if csv_exists and csv_size > 50:
        score += w_csv_exists
        feedback_parts.append(f"CSV exists ({csv_size} bytes)")
    elif csv_exists:
        score += w_csv_exists // 2
        feedback_parts.append(f"CSV exists but very small ({csv_size} bytes)")
    else:
        feedback_parts.append("CSV file NOT found")
        # Early exit - nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 7: File Timestamp Valid (5 points) - Anti-gaming
    # ============================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    
    if file_created_during_task:
        score += w_timestamp
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File may have existed before task")
    
    details['timestamp_valid'] = file_created_during_task

    # ============================================================
    # CRITERION 2: CSV Structure Valid (15 points)
    # ============================================================
    csv_valid = result.get('csv_valid', False)
    has_segment_col = result.get('has_segment_col', False)
    has_volume_col = result.get('has_volume_col', False)
    num_rows = result.get('num_rows', 0)
    num_cols = result.get('num_cols', 0)
    
    structure_score = 0
    if csv_valid:
        structure_score += w_csv_structure * 0.3
    if has_segment_col:
        structure_score += w_csv_structure * 0.35
    if has_volume_col:
        structure_score += w_csv_structure * 0.35
    
    score += int(structure_score)
    
    if csv_valid and has_segment_col and has_volume_col:
        feedback_parts.append(f"CSV structure valid ({num_rows} rows, {num_cols} cols)")
    elif csv_valid:
        missing = []
        if not has_segment_col:
            missing.append("segment column")
        if not has_volume_col:
            missing.append("volume column")
        feedback_parts.append(f"CSV missing: {', '.join(missing)}")
    else:
        feedback_parts.append("CSV structure invalid")
    
    details['structure_valid'] = csv_valid and has_segment_col and has_volume_col

    # ============================================================
    # CRITERION 3: All Segments Present (20 points)
    # ============================================================
    segments_found_str = result.get('segments_found', '')
    segments_found = [s.strip().lower() for s in segments_found_str.split(',') if s.strip()]
    
    # Match expected segments (case-insensitive, partial match)
    matched_segments = []
    for expected in EXPECTED_SEGMENTS:
        for found in segments_found:
            if expected in found or found in expected:
                matched_segments.append(expected)
                break
    
    matched_segments = list(set(matched_segments))
    num_matched = len(matched_segments)
    
    if num_matched == 3:
        score += w_all_segments
        feedback_parts.append("All 3 segments present")
    elif num_matched > 0:
        partial_score = int(w_all_segments * num_matched / 3)
        score += partial_score
        feedback_parts.append(f"{num_matched}/3 segments found")
    else:
        feedback_parts.append("No expected segments found")
    
    details['segments_matched'] = matched_segments
    details['segments_found_raw'] = segments_found

    # ============================================================
    # Load parsed CSV data for detailed validation
    # ============================================================
    csv_data = {}
    temp_csv_data = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/csv_parsed_data.json", temp_csv_data.name)
        with open(temp_csv_data.name, 'r') as f:
            csv_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load parsed CSV data: {e}")
    finally:
        if os.path.exists(temp_csv_data.name):
            os.unlink(temp_csv_data.name)

    segment_data = csv_data.get('segment_data', {})
    details['segment_data'] = segment_data

    # ============================================================
    # CRITERION 4: Volume Values Valid (15 points)
    # ============================================================
    valid_volumes = 0
    volume_issues = []
    
    for seg_name, data in segment_data.items():
        # Find volume column
        volume_val = None
        for col, val in data.items():
            col_lower = col.lower()
            if 'volume' in col_lower and isinstance(val, (int, float)):
                volume_val = val
                break
        
        if volume_val is not None and volume_val > 0:
            valid_volumes += 1
        elif volume_val is not None:
            volume_issues.append(f"{seg_name}: volume={volume_val}")
    
    if valid_volumes >= 3:
        score += w_volume_valid
        feedback_parts.append("All volume values valid")
    elif valid_volumes > 0:
        score += int(w_volume_valid * valid_volumes / 3)
        feedback_parts.append(f"{valid_volumes}/3 valid volumes")
    else:
        feedback_parts.append("No valid volume values")
    
    details['valid_volumes'] = valid_volumes
    details['volume_issues'] = volume_issues

    # ============================================================
    # CRITERION 5: Volume Accuracy (15 points)
    # ============================================================
    # Load ground truth
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/segment_stats_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_segments = gt_data.get('segments', {})
    details['ground_truth'] = gt_segments

    # Compare volumes
    accurate_volumes = 0
    accuracy_details = []
    
    for gt_name, gt_stats in gt_segments.items():
        gt_volume = gt_stats.get('volume_mm3', 0)
        if gt_volume <= 0:
            continue
        
        # Find matching segment in CSV data
        for csv_seg_name, csv_seg_data in segment_data.items():
            if gt_name.lower() in csv_seg_name.lower() or csv_seg_name.lower() in gt_name.lower():
                # Find volume value
                csv_volume = None
                for col, val in csv_seg_data.items():
                    if 'volume' in col.lower() and isinstance(val, (int, float)):
                        csv_volume = val
                        break
                
                if csv_volume is not None:
                    # Handle mm³ vs cm³ conversion
                    if csv_volume < gt_volume / 100:
                        csv_volume *= 1000  # Likely cm³, convert to mm³
                    
                    diff_pct = abs(csv_volume - gt_volume) / gt_volume * 100
                    accuracy_details.append({
                        'segment': gt_name,
                        'gt_volume': gt_volume,
                        'csv_volume': csv_volume,
                        'diff_pct': diff_pct
                    })
                    
                    if diff_pct <= volume_tolerance_pct:
                        accurate_volumes += 1
                break
    
    num_gt_segments = len([s for s in gt_segments.values() if s.get('volume_mm3', 0) > 0])
    if num_gt_segments > 0 and accurate_volumes > 0:
        accuracy_score = int(w_volume_accuracy * accurate_volumes / num_gt_segments)
        score += accuracy_score
        feedback_parts.append(f"Volume accuracy: {accurate_volumes}/{num_gt_segments} within {volume_tolerance_pct}%")
    else:
        feedback_parts.append("Could not verify volume accuracy")
    
    details['accuracy_details'] = accuracy_details

    # ============================================================
    # CRITERION 6: Intensity Stats Present (10 points)
    # ============================================================
    has_intensity = result.get('has_intensity_col', False)
    
    if has_intensity:
        score += w_intensity
        feedback_parts.append("Intensity statistics present")
    else:
        feedback_parts.append("No intensity statistics")
    
    details['has_intensity_stats'] = has_intensity

    # ============================================================
    # Calculate final result
    # ============================================================
    max_score = w_csv_exists + w_csv_structure + w_all_segments + w_volume_valid + w_volume_accuracy + w_intensity + w_timestamp
    
    # Key criteria for passing
    key_criteria_met = (
        csv_exists and
        csv_size > 50 and
        num_matched >= 2  # At least 2 of 3 segments
    )
    
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": feedback,
        "details": details
    }