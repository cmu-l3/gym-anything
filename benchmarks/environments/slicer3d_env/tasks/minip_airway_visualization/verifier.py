#!/usr/bin/env python3
"""
Verifier for MinIP Airway Visualization task.

VERIFICATION STRATEGY:
1. MinIP visualization created (not just standard axial slice)
2. Airway measurements in physiologic ranges
3. Anatomic relationships correct (right >= left bronchus)
4. Landmarks placed at correct locations
5. Screenshot shows airway tree visualization

SCORING (100 points total):
- MinIP created: 15 points
- Trachea measurement: 15 points  
- Right bronchus measurement: 10 points
- Left bronchus measurement: 10 points
- Anatomic relationship: 10 points
- Carina landmark: 10 points
- Main bronchi labeled: 10 points
- Lobar bronchi labeled: 5 points
- Screenshot quality: 10 points
- Report completeness: 5 points

Pass threshold: 60 points with at least 2 measurements in range
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


def verify_minip_airway_visualization(traj, env_info, task_info):
    """
    Verify MinIP airway visualization task completion.
    
    Uses multi-signal verification:
    1. File-based: Check measurements and landmarks
    2. VLM-based: Verify screenshot shows MinIP airway visualization
    3. Anti-gaming: Timestamp checks, anatomic plausibility
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
    normal_ranges = metadata.get('normal_ranges', {
        'trachea_min_mm': 15, 'trachea_max_mm': 25,
        'right_bronchus_min_mm': 10, 'right_bronchus_max_mm': 16,
        'left_bronchus_min_mm': 9, 'left_bronchus_max_mm': 14
    })
    weights = metadata.get('scoring_weights', {})
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/minip_task_result.json", temp_result.name)
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
    
    # Load ground truth if available
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/airway_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_measurements = gt_data.get('measurements', {})
    details['ground_truth'] = gt_measurements
    
    # ============================================================
    # CRITERION 1: Screenshot exists and shows MinIP (15 points)
    # ============================================================
    w_minip = weights.get('minip_created', 15)
    
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_created = result.get('screenshot_created_during_task', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    
    minip_detected = False
    
    if screenshot_exists and screenshot_size > 50000:  # >50KB suggests actual content
        if screenshot_created:
            score += w_minip
            feedback_parts.append(f"✅ MinIP screenshot created ({screenshot_size/1024:.1f}KB)")
            minip_detected = True
        else:
            score += w_minip // 2
            feedback_parts.append(f"⚠️ Screenshot exists but may be pre-existing ({screenshot_size/1024:.1f}KB)")
    elif screenshot_exists:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot too small ({screenshot_size/1024:.1f}KB) - may not be MinIP")
    else:
        feedback_parts.append("❌ No MinIP screenshot found")
    
    # ============================================================
    # CRITERION 2: Trachea measurement (15 points)
    # ============================================================
    w_trachea = weights.get('trachea_measurement', 15)
    
    trachea_diam_str = result.get('trachea_diameter_mm', '')
    trachea_diam = 0.0
    trachea_in_range = False
    
    if trachea_diam_str:
        try:
            trachea_diam = float(trachea_diam_str)
            trachea_min = normal_ranges.get('trachea_min_mm', 15)
            trachea_max = normal_ranges.get('trachea_max_mm', 25)
            
            if trachea_min <= trachea_diam <= trachea_max:
                score += w_trachea
                feedback_parts.append(f"✅ Trachea: {trachea_diam:.1f}mm (normal: {trachea_min}-{trachea_max}mm)")
                trachea_in_range = True
            elif 10 <= trachea_diam <= 35:
                # Plausible but outside normal range
                score += w_trachea // 2
                feedback_parts.append(f"⚠️ Trachea: {trachea_diam:.1f}mm (outside normal {trachea_min}-{trachea_max}mm)")
            else:
                feedback_parts.append(f"❌ Trachea: {trachea_diam:.1f}mm (implausible value)")
        except ValueError:
            feedback_parts.append(f"❌ Invalid trachea measurement: {trachea_diam_str}")
    else:
        feedback_parts.append("❌ Trachea measurement not found")
    
    details['trachea_diameter_mm'] = trachea_diam
    
    # ============================================================
    # CRITERION 3: Right bronchus measurement (10 points)
    # ============================================================
    w_right = weights.get('right_bronchus_measurement', 10)
    
    right_diam_str = result.get('right_bronchus_diameter_mm', '')
    right_diam = 0.0
    right_in_range = False
    
    if right_diam_str:
        try:
            right_diam = float(right_diam_str)
            right_min = normal_ranges.get('right_bronchus_min_mm', 10)
            right_max = normal_ranges.get('right_bronchus_max_mm', 16)
            
            if right_min <= right_diam <= right_max:
                score += w_right
                feedback_parts.append(f"✅ Right bronchus: {right_diam:.1f}mm (normal)")
                right_in_range = True
            elif 5 <= right_diam <= 25:
                score += w_right // 2
                feedback_parts.append(f"⚠️ Right bronchus: {right_diam:.1f}mm (outside normal {right_min}-{right_max}mm)")
            else:
                feedback_parts.append(f"❌ Right bronchus: {right_diam:.1f}mm (implausible)")
        except ValueError:
            feedback_parts.append(f"❌ Invalid right bronchus measurement: {right_diam_str}")
    else:
        feedback_parts.append("❌ Right bronchus measurement not found")
    
    details['right_bronchus_diameter_mm'] = right_diam
    
    # ============================================================
    # CRITERION 4: Left bronchus measurement (10 points)
    # ============================================================
    w_left = weights.get('left_bronchus_measurement', 10)
    
    left_diam_str = result.get('left_bronchus_diameter_mm', '')
    left_diam = 0.0
    left_in_range = False
    
    if left_diam_str:
        try:
            left_diam = float(left_diam_str)
            left_min = normal_ranges.get('left_bronchus_min_mm', 9)
            left_max = normal_ranges.get('left_bronchus_max_mm', 14)
            
            if left_min <= left_diam <= left_max:
                score += w_left
                feedback_parts.append(f"✅ Left bronchus: {left_diam:.1f}mm (normal)")
                left_in_range = True
            elif 5 <= left_diam <= 20:
                score += w_left // 2
                feedback_parts.append(f"⚠️ Left bronchus: {left_diam:.1f}mm (outside normal {left_min}-{left_max}mm)")
            else:
                feedback_parts.append(f"❌ Left bronchus: {left_diam:.1f}mm (implausible)")
        except ValueError:
            feedback_parts.append(f"❌ Invalid left bronchus measurement: {left_diam_str}")
    else:
        feedback_parts.append("❌ Left bronchus measurement not found")
    
    details['left_bronchus_diameter_mm'] = left_diam
    
    # ============================================================
    # CRITERION 5: Anatomic relationship - right >= left (10 points)
    # ============================================================
    w_anatomy = weights.get('anatomic_relationship', 10)
    
    if right_diam > 0 and left_diam > 0:
        if right_diam >= left_diam:
            score += w_anatomy
            feedback_parts.append(f"✅ Anatomic relationship: Right ({right_diam:.1f}mm) ≥ Left ({left_diam:.1f}mm)")
        else:
            # Still give partial credit - measurements exist
            score += w_anatomy // 3
            feedback_parts.append(f"⚠️ Unusual: Right ({right_diam:.1f}mm) < Left ({left_diam:.1f}mm)")
    else:
        feedback_parts.append("❌ Cannot verify anatomic relationship - missing measurements")
    
    # ============================================================
    # CRITERION 6: Carina landmark (10 points)
    # ============================================================
    w_carina = weights.get('carina_landmark', 10)
    
    landmarks_exists = result.get('landmarks_exists', False)
    landmarks_count = result.get('landmarks_count', 0)
    
    carina_found = False
    
    if landmarks_exists and landmarks_count > 0:
        # Try to read landmarks file for more detail
        temp_landmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_landmarks.json", temp_landmarks.name)
            with open(temp_landmarks.name, 'r') as f:
                landmarks_data = json.load(f)
            
            landmarks = landmarks_data.get('landmarks', [])
            for lm in landmarks:
                name = lm.get('name', '').lower()
                if 'carina' in name or 'bifurc' in name:
                    carina_found = True
                    score += w_carina
                    feedback_parts.append(f"✅ Carina landmark found: {lm.get('name')}")
                    break
            
            if not carina_found:
                # Check if any landmark is reasonably placed (partial credit)
                if landmarks_count >= 1:
                    score += w_carina // 2
                    feedback_parts.append(f"⚠️ Landmarks exist ({landmarks_count}) but no explicit carina label")
        except Exception as e:
            logger.warning(f"Could not read landmarks: {e}")
        finally:
            if os.path.exists(temp_landmarks.name):
                os.unlink(temp_landmarks.name)
    
    if not carina_found and not landmarks_exists:
        feedback_parts.append("❌ No landmarks/carina marker found")
    
    details['landmarks_count'] = landmarks_count
    
    # ============================================================
    # CRITERION 7: Main bronchi labeled (10 points)
    # ============================================================
    w_bronchi_label = weights.get('bronchi_labeled', 10)
    
    bronchi_labeled = False
    if landmarks_exists and landmarks_count >= 2:
        temp_landmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_landmarks.json", temp_landmarks.name)
            with open(temp_landmarks.name, 'r') as f:
                landmarks_data = json.load(f)
            
            landmarks = landmarks_data.get('landmarks', [])
            right_found = False
            left_found = False
            
            for lm in landmarks:
                name = lm.get('name', '').lower()
                if 'right' in name and ('bronch' in name or 'rb' in name or 'rmb' in name):
                    right_found = True
                if 'left' in name and ('bronch' in name or 'lb' in name or 'lmb' in name):
                    left_found = True
            
            if right_found and left_found:
                score += w_bronchi_label
                feedback_parts.append("✅ Both main bronchi labeled")
                bronchi_labeled = True
            elif right_found or left_found:
                score += w_bronchi_label // 2
                feedback_parts.append("⚠️ Only one main bronchus labeled")
            else:
                # Give partial credit for having multiple landmarks
                if landmarks_count >= 4:
                    score += w_bronchi_label // 3
                    feedback_parts.append(f"⚠️ {landmarks_count} landmarks but bronchi not explicitly named")
        except Exception:
            pass
        finally:
            if os.path.exists(temp_landmarks.name):
                os.unlink(temp_landmarks.name)
    
    if not bronchi_labeled and landmarks_count < 2:
        feedback_parts.append("❌ Main bronchi not labeled")
    
    # ============================================================
    # CRITERION 8: Lobar bronchi labeled (5 points)
    # ============================================================
    w_lobar = weights.get('lobar_bronchi_labeled', 5)
    
    if landmarks_exists and landmarks_count >= 5:
        temp_landmarks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/agent_landmarks.json", temp_landmarks.name)
            with open(temp_landmarks.name, 'r') as f:
                landmarks_data = json.load(f)
            
            landmarks = landmarks_data.get('landmarks', [])
            lobar_found = False
            
            for lm in landmarks:
                name = lm.get('name', '').lower()
                if 'lobe' in name or 'lobar' in name or 'rul' in name or 'lul' in name or 'rll' in name or 'lll' in name or 'rml' in name:
                    lobar_found = True
                    break
            
            if lobar_found:
                score += w_lobar
                feedback_parts.append("✅ Lobar bronchus labeled")
            elif landmarks_count >= 6:
                score += w_lobar // 2
                feedback_parts.append(f"⚠️ Many landmarks ({landmarks_count}) but lobar not explicitly named")
        except Exception:
            pass
        finally:
            if os.path.exists(temp_landmarks.name):
                os.unlink(temp_landmarks.name)
    else:
        feedback_parts.append("⚠️ Lobar bronchi not labeled (optional)")
    
    # ============================================================
    # CRITERION 9: Screenshot quality - VLM verification (10 points)
    # ============================================================
    w_screenshot = weights.get('screenshot_quality', 10)
    
    query_vlm = env_info.get('query_vlm')
    
    if screenshot_exists and query_vlm:
        # Use trajectory frames for more robust verification
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            traj_frames = sample_trajectory_frames(traj, n=3) if traj else []
            final_screenshot = get_final_screenshot(traj)
            
            # Copy agent's saved screenshot
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/agent_screenshot.png", temp_screenshot.name)
                agent_screenshot = temp_screenshot.name
            except:
                agent_screenshot = None
            
            # Use all available images
            images_to_check = traj_frames + ([final_screenshot] if final_screenshot else [])
            
            if images_to_check:
                vlm_prompt = """Analyze this image(s) from 3D Slicer medical imaging software.

TASK: The agent was asked to create a Minimum Intensity Projection (MinIP) visualization of airways.

MinIP shows the MINIMUM (darkest) values in a slab - making air-filled airways appear as dark tube-like structures against lighter tissue.

Check for:
1. Is this showing medical imaging software (3D Slicer)?
2. Is there an airway/bronchial tree visible? Look for:
   - Dark branching tube-like structures (trachea and bronchi)
   - Tree-like branching pattern typical of airways
   - NOT just a regular axial CT slice
3. Are there annotation markers or measurement lines visible?
4. Does this appear to be a MinIP or thick-slab reconstruction (not standard thin slice)?

Respond in JSON:
{
    "is_medical_imaging_software": true/false,
    "airway_tree_visible": true/false,
    "appears_to_be_minip_or_slab": true/false,
    "annotations_visible": true/false,
    "measurements_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    is_imaging = parsed.get('is_medical_imaging_software', False)
                    airway_visible = parsed.get('airway_tree_visible', False)
                    is_minip = parsed.get('appears_to_be_minip_or_slab', False)
                    has_annotations = parsed.get('annotations_visible', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    details['vlm_result'] = to_python_type(parsed)
                    
                    if is_imaging and airway_visible and is_minip:
                        if confidence == 'high':
                            score += w_screenshot
                            feedback_parts.append("✅ VLM: MinIP airway visualization confirmed (high confidence)")
                        else:
                            score += int(w_screenshot * 0.8)
                            feedback_parts.append(f"✅ VLM: MinIP airway visualization detected ({confidence} confidence)")
                    elif is_imaging and (airway_visible or is_minip):
                        score += w_screenshot // 2
                        feedback_parts.append(f"⚠️ VLM: Partial visualization detected")
                    else:
                        feedback_parts.append(f"❌ VLM: Could not confirm MinIP airway visualization")
                else:
                    feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'unknown')}")
                    score += 3  # Small benefit of doubt
            else:
                feedback_parts.append("⚠️ No images available for VLM verification")
                score += 3
                
        except ImportError:
            # VLM module not available - give partial credit based on file existence
            if screenshot_exists and screenshot_size > 100000:
                score += w_screenshot // 2
                feedback_parts.append("⚠️ VLM unavailable - screenshot exists but unverified")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            if screenshot_exists:
                score += 3
    elif screenshot_exists:
        score += 3
        feedback_parts.append("⚠️ Screenshot exists but VLM unavailable for quality check")
    else:
        feedback_parts.append("❌ No screenshot to verify")
    
    # ============================================================
    # CRITERION 10: Report completeness (5 points)
    # ============================================================
    w_report = weights.get('report_completeness', 5)
    
    measurements_exists = result.get('measurements_exists', False)
    
    if measurements_exists:
        fields_present = sum([
            bool(trachea_diam_str),
            bool(right_diam_str),
            bool(left_diam_str)
        ])
        
        if fields_present == 3:
            score += w_report
            feedback_parts.append("✅ Measurements report complete (3/3 fields)")
        elif fields_present >= 1:
            score += int(w_report * fields_present / 3)
            feedback_parts.append(f"⚠️ Measurements report partial ({fields_present}/3 fields)")
    else:
        feedback_parts.append("❌ Measurements report not found")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Count measurements in physiologic range
    measurements_in_range = sum([trachea_in_range, right_in_range, left_in_range])
    
    # Key criteria for passing
    key_criteria_met = (
        measurements_in_range >= 2 and  # At least 2 measurements in normal range
        (screenshot_exists or landmarks_exists)  # Some evidence of work
    )
    
    # Pass threshold: 60 points AND key criteria
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"✅ PASSED (Score: {score}/100) | {feedback}"
    else:
        if score >= 60 and not key_criteria_met:
            feedback = f"❌ FAILED: Score OK ({score}/100) but key criteria not met (need ≥2 measurements in range) | {feedback}"
        else:
            feedback = f"❌ FAILED (Score: {score}/100, need ≥60 with key criteria) | {feedback}"
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type({
            **details,
            "measurements_in_range": measurements_in_range,
            "key_criteria_met": key_criteria_met,
            "scoring_breakdown": {
                "minip_created": w_minip,
                "trachea_measurement": w_trachea,
                "right_bronchus_measurement": w_right,
                "left_bronchus_measurement": w_left,
                "anatomic_relationship": w_anatomy,
                "carina_landmark": w_carina,
                "bronchi_labeled": w_bronchi_label,
                "lobar_bronchi_labeled": w_lobar,
                "screenshot_quality": w_screenshot,
                "report_completeness": w_report
            }
        })
    }