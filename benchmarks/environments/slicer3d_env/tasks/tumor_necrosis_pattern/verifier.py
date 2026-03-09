#!/usr/bin/env python3
"""
Verifier for Tumor Necrosis and Enhancement Pattern Analysis task.

VERIFICATION STRATEGY:
1. Enhancing volume accuracy - compare to ground truth BraTS label 4
2. Necrotic volume accuracy - compare to ground truth BraTS label 1
3. Necrosis ratio accuracy - compare calculated ratios
4. Pattern classification - verify correct pattern identification
5. Report completeness - JSON has all required fields
6. Segmentation quality - segments overlap with actual tumor region

Anti-gaming checks:
- Segmentation file must be created after task start time
- Segmentation must have at least 2 distinct labels
- Segments must spatially overlap with ground truth tumor region

BraTS Labels:
- 1: Necrotic/Non-enhancing tumor core
- 2: Peritumoral edema  
- 4: GD-enhancing tumor
"""

import json
import os
import sys
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Will be imported after ensuring dependencies
np = None
nib = None


def ensure_dependencies():
    """Ensure required packages are available."""
    global np, nib
    try:
        import numpy
        np = numpy
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy"])
        import numpy
        np = numpy
    
    try:
        import nibabel
        nib = nibabel
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
        import nibabel
        nib = nibabel
    
    return True


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if np is None:
        return val
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


def verify_tumor_necrosis_pattern(traj, env_info, task_info):
    """
    Verify tumor necrosis pattern analysis task completion.
    
    Scoring (100 points total):
    - Enhancing volume accuracy: 25 points (within 40% of ground truth)
    - Necrotic volume accuracy: 25 points (within 40% of ground truth)
    - Necrosis ratio accuracy: 15 points (within 0.15 of ground truth)
    - Pattern classification: 20 points (correct category)
    - Report completeness: 10 points (all required fields)
    - Segmentation quality: 5 points (overlaps with tumor)
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Ensure dependencies
    if not ensure_dependencies():
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to load required dependencies (numpy, nibabel)"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    enhancing_err_max = thresholds.get('enhancing_volume_error_max_pct', 40) / 100.0
    necrotic_err_max = thresholds.get('necrotic_volume_error_max_pct', 40) / 100.0
    ratio_err_max = thresholds.get('ratio_error_max', 0.15)
    
    w_enhancing = weights.get('enhancing_volume_accuracy', 25)
    w_necrotic = weights.get('necrotic_volume_accuracy', 25)
    w_ratio = weights.get('necrosis_ratio_accuracy', 15)
    w_pattern = weights.get('pattern_classification', 20)
    w_report = weights.get('report_completeness', 10)
    w_quality = weights.get('segmentation_quality', 5)
    
    # Create temp directory for file operations
    temp_dir = tempfile.mkdtemp()
    
    try:
        # ================================================================
        # LOAD TASK RESULT
        # ================================================================
        result_file = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/necrosis_task_result.json", result_file)
            with open(result_file, 'r') as f:
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
        
        # Initialize scoring
        score = 0
        feedback_parts = []
        details = {}
        
        # ================================================================
        # BASIC CHECKS
        # ================================================================
        if not result.get('slicer_was_running', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Slicer was not running - cannot verify task completion"
            }
        
        seg_info = result.get('segmentation', {})
        report_info = result.get('report', {})
        
        # Check if segmentation exists
        if not seg_info.get('exists', False):
            feedback_parts.append("Segmentation file NOT created")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts) if feedback_parts else "No segmentation created",
                "details": to_python_type(details)
            }
        
        # Anti-gaming: Check timestamp
        if not seg_info.get('created_during_task', False):
            feedback_parts.append("Segmentation predates task start (possible gaming)")
            return {
                "passed": False,
                "score": 5,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }
        
        # Anti-gaming: Check label count
        label_count = seg_info.get('label_count', 0)
        if label_count < 2:
            feedback_parts.append(f"Segmentation has {label_count} labels, need 2 (enhancing + necrotic)")
            return {
                "passed": False,
                "score": 10,
                "feedback": " | ".join(feedback_parts),
                "details": to_python_type(details)
            }
        
        details['segmentation_label_count'] = label_count
        feedback_parts.append(f"Segmentation has {label_count} labels")
        
        # ================================================================
        # LOAD GROUND TRUTH
        # ================================================================
        gt_stats_file = os.path.join(temp_dir, "gt_stats.json")
        gt_stats = {}
        try:
            copy_from_env("/tmp/ground_truth_necrosis_stats.json", gt_stats_file)
            with open(gt_stats_file, 'r') as f:
                gt_stats = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load ground truth stats: {e}")
            return {
                "passed": False,
                "score": 10,
                "feedback": f"Could not load ground truth stats: {e}"
            }
        
        gt_enhancing_ml = gt_stats.get('enhancing_volume_ml', 0)
        gt_necrotic_ml = gt_stats.get('necrotic_volume_ml', 0)
        gt_ratio = gt_stats.get('necrosis_ratio', 0)
        gt_pattern = gt_stats.get('enhancement_pattern', '')
        
        details['ground_truth'] = {
            'enhancing_ml': gt_enhancing_ml,
            'necrotic_ml': gt_necrotic_ml,
            'ratio': gt_ratio,
            'pattern': gt_pattern
        }
        
        # ================================================================
        # LOAD AND ANALYZE AGENT SEGMENTATION
        # ================================================================
        agent_seg_file = os.path.join(temp_dir, "agent_seg.nii.gz")
        gt_seg_file = os.path.join(temp_dir, "gt_seg.nii.gz")
        
        try:
            copy_from_env("/tmp/agent_segmentation.nii.gz", agent_seg_file)
            copy_from_env("/tmp/ground_truth_seg.nii.gz", gt_seg_file)
        except Exception as e:
            logger.warning(f"Failed to copy segmentation files: {e}")
            return {
                "passed": False,
                "score": 15,
                "feedback": f"Could not load segmentation files: {e}"
            }
        
        # Load and analyze segmentations
        try:
            agent_seg = nib.load(agent_seg_file)
            agent_data = agent_seg.get_fdata()
            voxel_vol = float(np.prod(agent_seg.header.get_zooms()[:3]))
            
            gt_seg = nib.load(gt_seg_file)
            gt_data = gt_seg.get_fdata().astype(np.int32)
        except Exception as e:
            return {
                "passed": False,
                "score": 15,
                "feedback": f"Failed to load NIfTI files: {e}"
            }
        
        # Get agent's labels
        agent_labels = np.unique(agent_data[agent_data > 0])
        details['agent_labels'] = to_python_type(agent_labels)
        
        if len(agent_labels) < 2:
            return {
                "passed": False,
                "score": 15,
                "feedback": f"Segmentation must have 2 distinct labels, found {len(agent_labels)}"
            }
        
        # Map agent labels to enhancing/necrotic by overlap with ground truth
        gt_enhancing_mask = (gt_data == 4)
        gt_necrotic_mask = (gt_data == 1)
        
        best_enhancing_label = None
        best_necrotic_label = None
        best_enhancing_overlap = 0
        best_necrotic_overlap = 0
        
        for label in agent_labels:
            agent_mask = (agent_data == label)
            
            # Calculate overlap ratios
            enhancing_overlap = np.sum(agent_mask & gt_enhancing_mask) / (np.sum(gt_enhancing_mask) + 1e-6)
            necrotic_overlap = np.sum(agent_mask & gt_necrotic_mask) / (np.sum(gt_necrotic_mask) + 1e-6)
            
            if enhancing_overlap > best_enhancing_overlap:
                best_enhancing_overlap = enhancing_overlap
                best_enhancing_label = label
            
            if necrotic_overlap > best_necrotic_overlap:
                best_necrotic_overlap = necrotic_overlap
                best_necrotic_label = label
        
        # If same label maps to both, use volume heuristic
        if best_enhancing_label == best_necrotic_label and len(agent_labels) >= 2:
            # Use larger volume as enhancing (typical for ring-enhancing tumors)
            label_volumes = {}
            for label in agent_labels:
                label_volumes[label] = np.sum(agent_data == label) * voxel_vol / 1000.0
            sorted_labels = sorted(label_volumes.keys(), key=lambda x: label_volumes[x], reverse=True)
            best_enhancing_label = sorted_labels[0]
            best_necrotic_label = sorted_labels[1] if len(sorted_labels) > 1 else None
        
        # Calculate agent volumes
        if best_enhancing_label is not None:
            agent_enhancing_ml = float(np.sum(agent_data == best_enhancing_label) * voxel_vol / 1000.0)
        else:
            agent_enhancing_ml = 0.0
        
        if best_necrotic_label is not None:
            agent_necrotic_ml = float(np.sum(agent_data == best_necrotic_label) * voxel_vol / 1000.0)
        else:
            agent_necrotic_ml = 0.0
        
        agent_total_core = agent_enhancing_ml + agent_necrotic_ml
        agent_ratio = agent_necrotic_ml / agent_total_core if agent_total_core > 0 else 0
        
        details['agent_measurements'] = {
            'enhancing_volume_ml': round(agent_enhancing_ml, 2),
            'necrotic_volume_ml': round(agent_necrotic_ml, 2),
            'total_core_volume_ml': round(agent_total_core, 2),
            'necrosis_ratio': round(agent_ratio, 3),
            'enhancing_label': to_python_type(best_enhancing_label),
            'necrotic_label': to_python_type(best_necrotic_label)
        }
        
        # ================================================================
        # SCORE: ENHANCING VOLUME ACCURACY (25 points)
        # ================================================================
        if gt_enhancing_ml > 0:
            enhancing_error = abs(agent_enhancing_ml - gt_enhancing_ml) / gt_enhancing_ml
            details['enhancing_error_pct'] = round(enhancing_error * 100, 1)
            
            if enhancing_error <= 0.20:
                score += w_enhancing
                feedback_parts.append(f"Enhancing volume EXCELLENT ({enhancing_error*100:.0f}% error)")
                details['enhancing_accuracy'] = 'excellent'
            elif enhancing_error <= 0.40:
                score += int(w_enhancing * 0.75)
                feedback_parts.append(f"Enhancing volume GOOD ({enhancing_error*100:.0f}% error)")
                details['enhancing_accuracy'] = 'good'
            elif enhancing_error <= 0.60:
                score += int(w_enhancing * 0.5)
                feedback_parts.append(f"Enhancing volume PARTIAL ({enhancing_error*100:.0f}% error)")
                details['enhancing_accuracy'] = 'partial'
            else:
                feedback_parts.append(f"Enhancing volume POOR ({enhancing_error*100:.0f}% error)")
                details['enhancing_accuracy'] = 'poor'
        elif agent_enhancing_ml < 1.0:
            score += w_enhancing
            feedback_parts.append("Both correctly identified minimal enhancing")
            details['enhancing_accuracy'] = 'correct_minimal'
        
        # ================================================================
        # SCORE: NECROTIC VOLUME ACCURACY (25 points)
        # ================================================================
        if gt_necrotic_ml > 0:
            necrotic_error = abs(agent_necrotic_ml - gt_necrotic_ml) / gt_necrotic_ml
            details['necrotic_error_pct'] = round(necrotic_error * 100, 1)
            
            if necrotic_error <= 0.20:
                score += w_necrotic
                feedback_parts.append(f"Necrotic volume EXCELLENT ({necrotic_error*100:.0f}% error)")
                details['necrotic_accuracy'] = 'excellent'
            elif necrotic_error <= 0.40:
                score += int(w_necrotic * 0.75)
                feedback_parts.append(f"Necrotic volume GOOD ({necrotic_error*100:.0f}% error)")
                details['necrotic_accuracy'] = 'good'
            elif necrotic_error <= 0.60:
                score += int(w_necrotic * 0.5)
                feedback_parts.append(f"Necrotic volume PARTIAL ({necrotic_error*100:.0f}% error)")
                details['necrotic_accuracy'] = 'partial'
            else:
                feedback_parts.append(f"Necrotic volume POOR ({necrotic_error*100:.0f}% error)")
                details['necrotic_accuracy'] = 'poor'
        elif agent_necrotic_ml < 1.0:
            score += w_necrotic
            feedback_parts.append("Both correctly identified minimal necrosis")
            details['necrotic_accuracy'] = 'correct_minimal'
        
        # ================================================================
        # SCORE: NECROSIS RATIO ACCURACY (15 points)
        # ================================================================
        ratio_diff = abs(agent_ratio - gt_ratio)
        details['ratio_difference'] = round(ratio_diff, 3)
        
        if ratio_diff <= 0.10:
            score += w_ratio
            feedback_parts.append(f"Necrosis ratio EXCELLENT (diff={ratio_diff:.2f})")
            details['ratio_accuracy'] = 'excellent'
        elif ratio_diff <= 0.15:
            score += int(w_ratio * 0.66)
            feedback_parts.append(f"Necrosis ratio GOOD (diff={ratio_diff:.2f})")
            details['ratio_accuracy'] = 'good'
        elif ratio_diff <= 0.25:
            score += int(w_ratio * 0.33)
            feedback_parts.append(f"Necrosis ratio PARTIAL (diff={ratio_diff:.2f})")
            details['ratio_accuracy'] = 'partial'
        else:
            feedback_parts.append(f"Necrosis ratio POOR (diff={ratio_diff:.2f})")
            details['ratio_accuracy'] = 'poor'
        
        # ================================================================
        # SCORE: PATTERN CLASSIFICATION (20 points)
        # ================================================================
        # Get pattern from report
        agent_pattern = report_info.get('enhancement_pattern', '').strip()
        
        if agent_pattern:
            # Normalize for comparison
            agent_pattern_norm = agent_pattern.lower().replace("-", "").replace("_", "").replace(" ", "")
            gt_pattern_norm = gt_pattern.lower().replace("-", "").replace("_", "").replace(" ", "")
            
            details['agent_pattern'] = agent_pattern
            details['gt_pattern'] = gt_pattern
            
            if agent_pattern_norm == gt_pattern_norm:
                score += w_pattern
                feedback_parts.append(f"Pattern classification CORRECT: {gt_pattern}")
                details['pattern_match'] = 'exact'
            else:
                # Partial credit for adjacent patterns
                adjacent_patterns = {
                    "ringenhancing": ["heterogeneous"],
                    "heterogeneous": ["ringenhancing", "solid"],
                    "solid": ["heterogeneous"],
                    "nonenhancing": []
                }
                
                if agent_pattern_norm in adjacent_patterns.get(gt_pattern_norm, []):
                    score += int(w_pattern * 0.5)
                    feedback_parts.append(f"Pattern PARTIAL: expected {gt_pattern}, got {agent_pattern}")
                    details['pattern_match'] = 'partial'
                else:
                    feedback_parts.append(f"Pattern INCORRECT: expected {gt_pattern}, got {agent_pattern}")
                    details['pattern_match'] = 'incorrect'
        else:
            feedback_parts.append("Pattern classification NOT provided in report")
            details['pattern_match'] = 'missing'
        
        # ================================================================
        # SCORE: REPORT COMPLETENESS (10 points)
        # ================================================================
        if report_info.get('exists', False):
            if report_info.get('valid', False):
                fields_count = report_info.get('fields_count', 0)
                report_score = int(w_report * min(fields_count / 4.0, 1.0))
                score += report_score
                feedback_parts.append(f"Report has {fields_count}/4 required fields")
                details['report_fields'] = fields_count
            else:
                score += int(w_report * 0.25)
                feedback_parts.append("Report exists but invalid/incomplete")
                details['report_fields'] = 0
        else:
            feedback_parts.append("Report NOT created")
            details['report_fields'] = 0
        
        # ================================================================
        # SCORE: SEGMENTATION QUALITY (5 points)
        # ================================================================
        # Check that agent segments overlap with actual tumor region
        gt_whole_tumor = (gt_data > 0)
        agent_any = (agent_data > 0)
        
        if np.sum(agent_any) > 0:
            tumor_overlap = np.sum(agent_any & gt_whole_tumor) / np.sum(agent_any)
            details['tumor_overlap_pct'] = round(tumor_overlap * 100, 1)
            
            if tumor_overlap > 0.8:
                score += w_quality
                feedback_parts.append(f"Segmentation localization EXCELLENT ({tumor_overlap*100:.0f}% overlap)")
                details['tumor_localization'] = 'excellent'
            elif tumor_overlap > 0.5:
                score += int(w_quality * 0.6)
                feedback_parts.append(f"Segmentation localization GOOD ({tumor_overlap*100:.0f}% overlap)")
                details['tumor_localization'] = 'good'
            else:
                feedback_parts.append(f"Segmentation localization POOR ({tumor_overlap*100:.0f}% overlap)")
                details['tumor_localization'] = 'poor'
        else:
            feedback_parts.append("Segmentation is empty")
            details['tumor_localization'] = 'empty'
        
        # ================================================================
        # FINAL ASSESSMENT
        # ================================================================
        # Pass if score >= 60 AND at least one volume is reasonably accurate
        enhancing_ok = details.get('enhancing_accuracy') in ['excellent', 'good']
        necrotic_ok = details.get('necrotic_accuracy') in ['excellent', 'good', 'correct_minimal']
        
        passed = score >= 60 and (enhancing_ok or necrotic_ok)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
        
    except Exception as e:
        import traceback
        logger.error(f"Verification error: {e}")
        logger.error(traceback.format_exc())
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {"error": str(e), "traceback": traceback.format_exc()}
        }
    
    finally:
        # Clean up temp directory
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)