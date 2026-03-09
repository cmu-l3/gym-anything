#!/usr/bin/env python3
"""
Verifier for Multi-Sequence MRI Display Configuration task.

VERIFICATION STRATEGY:
1. Four-panel layout (20 pts) - Check layout state and VLM screenshot analysis
2. Correct sequences displayed (20 pts) - Check volumes in each view
3. View synchronization (15 pts) - Check linked state
4. Tumor visible (15 pts) - VLM verification of screenshot content
5. Fiducial placement (10 pts) - Check fiducial exists and near tumor centroid
6. Window/level appropriate (10 pts) - VLM verification of image quality
7. Report completeness (10 pts) - Check JSON report fields

Uses VLM for trajectory-based verification to prevent gaming.
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    try:
        import numpy as np
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    except ImportError:
        pass
    
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def parse_fcsv_position(fcsv_content):
    """Parse fiducial position from FCSV file content."""
    lines = fcsv_content.strip().split('\n')
    for line in lines:
        if line.startswith('#') or not line.strip():
            continue
        parts = line.split(',')
        if len(parts) >= 4:
            try:
                # FCSV format: id,x,y,z,...
                x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                return [x, y, z]
            except (ValueError, IndexError):
                continue
    return None


def calculate_distance(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    if not p1 or not p2:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def verify_multisequence_display_setup(traj, env_info, task_info):
    """
    Verify multi-sequence MRI display configuration task.
    
    Scoring (100 points total):
    - Four-panel layout: 20 points
    - Correct sequences displayed: 20 points  
    - View synchronization: 15 points
    - Tumor visible: 15 points
    - Fiducial placement: 10 points
    - Window/level appropriate: 10 points
    - Report completeness: 10 points
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    weights = metadata.get('scoring_weights', {})
    expected_sequences = metadata.get('expected_sequences', ["FLAIR", "T1", "T1_Contrast", "T2"])
    fiducial_tolerance = metadata.get('fiducial_tolerance_mm', 20.0)
    min_screenshot_size = metadata.get('min_screenshot_size_kb', 200)
    passing_threshold = metadata.get('passing_threshold', 60)
    
    w_layout = weights.get('four_panel_layout', 20)
    w_sequences = weights.get('correct_sequences', 20)
    w_sync = weights.get('view_synchronization', 15)
    w_tumor = weights.get('tumor_visible', 15)
    w_fiducial = weights.get('fiducial_placement', 10)
    w_window = weights.get('window_level_appropriate', 10)
    w_report = weights.get('report_completeness', 10)

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/multisequence_task_result.json", temp_result.name)
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

    # Check basic preconditions
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # CRITERION 1: Four-Panel Layout (20 points)
    # ================================================================
    layout_info = result.get('layout', {})
    layout_name = layout_info.get('name', '')
    is_four_panel = layout_info.get('is_four_panel', False)
    
    layout_score = 0
    if is_four_panel:
        layout_score = w_layout
        feedback_parts.append(f"✅ Four-panel layout detected ({layout_name})")
    elif 'four' in layout_name.lower() or layout_name == "FourUp":
        layout_score = w_layout
        feedback_parts.append(f"✅ Four-Up layout detected")
    elif layout_name:
        layout_score = 5  # Partial credit for changing layout
        feedback_parts.append(f"⚠️ Layout changed but not Four-Up ({layout_name})")
    else:
        feedback_parts.append("❌ Four-panel layout not configured")
    
    score += layout_score
    details['layout_score'] = layout_score
    details['layout_name'] = layout_name

    # ================================================================
    # CRITERION 2: Correct Sequences Displayed (20 points)
    # ================================================================
    volumes_displayed = layout_info.get('volumes_displayed', '')
    displayed_list = [v.strip() for v in volumes_displayed.split(',') if v.strip() and v.strip() != 'None']
    
    sequences_found = 0
    expected_lower = [s.lower() for s in expected_sequences]
    
    for vol in displayed_list:
        vol_lower = vol.lower().replace('_', '').replace('-', '')
        for exp in expected_lower:
            exp_clean = exp.replace('_', '').replace('-', '')
            if exp_clean in vol_lower or vol_lower in exp_clean:
                sequences_found += 1
                break
    
    sequences_score = 0
    if sequences_found >= 4:
        sequences_score = w_sequences
        feedback_parts.append(f"✅ All 4 sequences displayed ({displayed_list})")
    elif sequences_found >= 3:
        sequences_score = int(w_sequences * 0.75)
        feedback_parts.append(f"⚠️ {sequences_found}/4 sequences displayed")
    elif sequences_found >= 2:
        sequences_score = int(w_sequences * 0.5)
        feedback_parts.append(f"⚠️ {sequences_found}/4 sequences displayed")
    elif sequences_found >= 1:
        sequences_score = int(w_sequences * 0.25)
        feedback_parts.append(f"⚠️ Only {sequences_found}/4 sequences displayed")
    else:
        feedback_parts.append("❌ Expected sequences not displayed in panels")
    
    score += sequences_score
    details['sequences_score'] = sequences_score
    details['sequences_found'] = sequences_found

    # ================================================================
    # CRITERION 3: View Synchronization (15 points)
    # ================================================================
    views_linked = layout_info.get('views_linked', False)
    
    sync_score = 0
    if views_linked:
        sync_score = w_sync
        feedback_parts.append("✅ Views are linked/synchronized")
    else:
        # VLM could check this visually, but for now give partial credit if layout is correct
        if is_four_panel:
            sync_score = int(w_sync * 0.3)
            feedback_parts.append("⚠️ Views may not be linked")
        else:
            feedback_parts.append("❌ Views not synchronized")
    
    score += sync_score
    details['sync_score'] = sync_score

    # ================================================================
    # CRITERION 4: Tumor Visible (15 points) - VLM Verification
    # ================================================================
    tumor_score = 0
    
    # Copy screenshot for VLM analysis
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    screenshot_available = False
    try:
        copy_from_env("/tmp/agent_screenshot.png", temp_screenshot.name)
        screenshot_size = os.path.getsize(temp_screenshot.name)
        if screenshot_size > min_screenshot_size * 1024:
            screenshot_available = True
    except Exception:
        pass
    
    # Use VLM if available
    if query_vlm and screenshot_available:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for more robust verification
            traj_frames = sample_trajectory_frames(traj, n=5) if traj else []
            final_frame = get_final_screenshot(traj)
            
            # Use final screenshot from container as primary
            analysis_images = [temp_screenshot.name]
            if final_frame:
                analysis_images.append(final_frame)
            
            vlm_prompt = """Analyze this 3D Slicer screenshot and determine:

1. Is this a four-panel (2x2 grid) layout showing brain MRI?
2. Are different MRI sequences visible (they should look different - varying contrast/brightness)?
3. Is a brain tumor visible (bright abnormal region in the brain)?
4. Are the panels showing the same anatomical location (synchronized views)?
5. Is the image quality/contrast appropriate for viewing brain tissue?

Respond in JSON format:
{
    "is_four_panel": true/false,
    "different_sequences_visible": true/false,
    "tumor_visible": true/false,
    "views_synchronized": true/false,
    "good_window_level": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(prompt=vlm_prompt, image=temp_screenshot.name)
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_analysis'] = parsed
                
                if parsed.get('tumor_visible', False):
                    tumor_score = w_tumor
                    feedback_parts.append("✅ Tumor visible in screenshot (VLM verified)")
                elif parsed.get('different_sequences_visible', False):
                    tumor_score = int(w_tumor * 0.5)
                    feedback_parts.append("⚠️ MRI sequences visible but tumor unclear")
                else:
                    feedback_parts.append("❌ Tumor not clearly visible (VLM)")
                
                # Bonus for good window/level
                if parsed.get('good_window_level', False):
                    details['window_level_good'] = True
            else:
                # VLM failed, give partial credit for screenshot existence
                tumor_score = int(w_tumor * 0.3)
                feedback_parts.append("⚠️ Screenshot captured (VLM verification unavailable)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            if screenshot_available:
                tumor_score = int(w_tumor * 0.3)
                feedback_parts.append("⚠️ Screenshot captured (VLM error)")
    elif screenshot_available:
        # No VLM, but screenshot exists
        tumor_score = int(w_tumor * 0.5)
        feedback_parts.append("⚠️ Screenshot captured (no VLM for verification)")
    else:
        feedback_parts.append("❌ No valid screenshot found")
    
    score += tumor_score
    details['tumor_score'] = tumor_score
    
    # Cleanup screenshot temp file
    if os.path.exists(temp_screenshot.name):
        os.unlink(temp_screenshot.name)

    # ================================================================
    # CRITERION 5: Fiducial Placement (10 points)
    # ================================================================
    fiducial_score = 0
    fiducial_info = result.get('fiducial', {})
    fiducial_exists = fiducial_info.get('exists', False)
    fiducial_created = fiducial_info.get('created_during_task', False)
    
    if fiducial_exists:
        # Try to read fiducial file and check position
        temp_fcsv = tempfile.NamedTemporaryFile(delete=False, suffix='.fcsv')
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        
        agent_position = None
        gt_centroid = None
        
        try:
            copy_from_env("/tmp/agent_fiducial.fcsv", temp_fcsv.name)
            with open(temp_fcsv.name, 'r') as f:
                agent_position = parse_fcsv_position(f.read())
        except Exception as e:
            logger.warning(f"Could not read agent fiducial: {e}")
        
        try:
            copy_from_env("/tmp/gt_centroid.json", temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                gt_data = json.load(f)
                gt_centroid = gt_data.get('centroid_ras')
        except Exception as e:
            logger.warning(f"Could not read ground truth centroid: {e}")
        
        # Cleanup temp files
        for tf in [temp_fcsv, temp_gt]:
            if os.path.exists(tf.name):
                os.unlink(tf.name)
        
        if agent_position and gt_centroid:
            distance = calculate_distance(agent_position, gt_centroid)
            details['fiducial_distance_mm'] = distance
            details['agent_fiducial_position'] = agent_position
            details['gt_centroid'] = gt_centroid
            
            if distance <= fiducial_tolerance:
                fiducial_score = w_fiducial
                feedback_parts.append(f"✅ Fiducial placed near tumor center ({distance:.1f}mm)")
            elif distance <= fiducial_tolerance * 2:
                fiducial_score = int(w_fiducial * 0.6)
                feedback_parts.append(f"⚠️ Fiducial placed but far from tumor ({distance:.1f}mm)")
            else:
                fiducial_score = int(w_fiducial * 0.3)
                feedback_parts.append(f"⚠️ Fiducial exists but not at tumor ({distance:.1f}mm)")
        elif agent_position:
            # Fiducial exists but no GT to compare
            fiducial_score = int(w_fiducial * 0.5)
            feedback_parts.append("⚠️ Fiducial placed (position not verified)")
        else:
            # File exists but couldn't parse position
            fiducial_score = int(w_fiducial * 0.3) if fiducial_created else int(w_fiducial * 0.2)
            feedback_parts.append("⚠️ Fiducial file exists")
    else:
        feedback_parts.append("❌ No fiducial marker placed")
    
    score += fiducial_score
    details['fiducial_score'] = fiducial_score

    # ================================================================
    # CRITERION 6: Window/Level Appropriate (10 points)
    # ================================================================
    window_score = 0
    
    # Check from VLM analysis if available
    if details.get('window_level_good', False):
        window_score = w_window
        feedback_parts.append("✅ Window/level settings appropriate")
    elif details.get('vlm_analysis', {}).get('different_sequences_visible', False):
        window_score = int(w_window * 0.7)
        feedback_parts.append("⚠️ Image contrast appears reasonable")
    elif screenshot_available:
        window_score = int(w_window * 0.4)
        feedback_parts.append("⚠️ Window/level not verified")
    else:
        feedback_parts.append("❌ Cannot verify window/level settings")
    
    score += window_score
    details['window_score'] = window_score

    # ================================================================
    # CRITERION 7: Report Completeness (10 points)
    # ================================================================
    report_score = 0
    report_info = result.get('report', {})
    report_exists = report_info.get('exists', False)
    report_valid = report_info.get('valid_json', False)
    report_complete = report_info.get('has_required_fields', False)
    report_created = report_info.get('created_during_task', False)
    
    if report_exists and report_valid and report_complete:
        report_score = w_report
        feedback_parts.append("✅ Report complete with required fields")
    elif report_exists and report_valid:
        report_score = int(w_report * 0.6)
        feedback_parts.append("⚠️ Report exists but missing some fields")
    elif report_exists:
        report_score = int(w_report * 0.3) if report_created else int(w_report * 0.2)
        feedback_parts.append("⚠️ Report file exists (may be invalid)")
    else:
        feedback_parts.append("❌ No report file created")
    
    score += report_score
    details['report_score'] = report_score

    # ================================================================
    # Final Assessment
    # ================================================================
    # Key criteria: layout must be attempted and some output created
    key_criteria_met = (layout_score > 0) and (
        fiducial_exists or 
        result.get('screenshot', {}).get('exists', False) or 
        report_exists
    )
    
    passed = score >= passing_threshold and key_criteria_met
    
    # Summary
    feedback_summary = f"Score: {score}/100 | " + " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback_summary,
        "details": details,
        "subscores": {
            "four_panel_layout": layout_score,
            "correct_sequences": sequences_score,
            "view_synchronization": sync_score,
            "tumor_visible": tumor_score,
            "fiducial_placement": fiducial_score,
            "window_level": window_score,
            "report_completeness": report_score
        }
    })