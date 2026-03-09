#!/usr/bin/env python3
"""
Verifier for Document Tumor Measurement task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (45 points):
  1. Screenshot exists at expected path (15 pts)
  2. Screenshot file size adequate (5 pts)
  3. Measurement created during task (10 pts)
  4. Measurement accuracy vs ground truth (15 pts)

VLM checks using TRAJECTORY frames (55 points):
  5. Tumor visible in screenshot (20 pts) - uses multiple trajectory frames
  6. Measurement line/ruler present (20 pts) - visual confirmation
  7. Text annotation present (15 pts) - shows diameter value

Pass threshold: 70 points with screenshot_exists and (tumor_visible OR measurement_present)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_tumor_measurement(traj, env_info, task_info):
    """
    Verify that the agent created a properly annotated tumor measurement screenshot.
    
    Uses multi-criteria scoring combining file checks, measurement accuracy,
    and VLM verification on trajectory frames.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get VLM query function
    query_vlm = env_info.get('query_vlm')
    
    # Import trajectory frame helpers
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        has_vlm_utils = True
    except ImportError:
        has_vlm_utils = False
        logger.warning("VLM utilities not available")

    # Get task metadata
    metadata = task_info.get('metadata', {})
    output_screenshot_path = metadata.get('output_screenshot', 
        '/home/ga/Documents/SlicerData/Screenshots/tumor_measurement.png')
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 50)
    measurement_tolerance_pct = metadata.get('measurement_tolerance_percent', 15)
    diameter_range = metadata.get('expected_diameter_range_mm', {"min": 15, "max": 80})
    
    weights = metadata.get('scoring_weights', {})
    w_screenshot_exists = weights.get('screenshot_exists', 15)
    w_screenshot_size = weights.get('screenshot_size_adequate', 5)
    w_tumor_visible = weights.get('tumor_visible', 20)
    w_measurement_present = weights.get('measurement_line_present', 20)
    w_annotation_present = weights.get('text_annotation_present', 15)
    w_measurement_accuracy = weights.get('measurement_accuracy', 25)

    # Initialize
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # COPY RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tumor_measurement_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
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

    details['result'] = result

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer not running")
        # Don't return early - check what we can

    # ================================================================
    # CRITERION 1: Screenshot exists (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_created = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_created:
        score += w_screenshot_exists
        feedback_parts.append("Screenshot created")
        details['screenshot_created'] = True
    elif screenshot_exists:
        score += w_screenshot_exists * 0.5
        feedback_parts.append("Screenshot exists (pre-existing?)")
        details['screenshot_created'] = False
    else:
        feedback_parts.append("No screenshot at expected path")
        details['screenshot_created'] = False

    # ================================================================
    # CRITERION 2: Screenshot size adequate (5 points)
    # ================================================================
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    
    if screenshot_size_kb >= min_screenshot_size_kb:
        score += w_screenshot_size
        feedback_parts.append(f"Size OK ({screenshot_size_kb}KB)")
    elif screenshot_size_kb > 10:
        score += w_screenshot_size * 0.5
        feedback_parts.append(f"Size small ({screenshot_size_kb}KB)")
    else:
        feedback_parts.append(f"Size too small ({screenshot_size_kb}KB)")

    details['screenshot_size_kb'] = screenshot_size_kb

    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/diameter_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_diameter = gt_data.get('max_diameter_mm', 0)
    details['gt_diameter_mm'] = gt_diameter

    # ================================================================
    # CRITERION 3: Measurement accuracy (25 points)
    # ================================================================
    extracted_diameter_str = result.get('extracted_diameter_mm', '')
    extracted_diameter = 0.0
    
    if extracted_diameter_str:
        try:
            extracted_diameter = float(extracted_diameter_str)
        except ValueError:
            pass
    
    details['extracted_diameter_mm'] = extracted_diameter
    
    measurement_score = 0
    if extracted_diameter > 0:
        # Check if in plausible range
        if diameter_range['min'] <= extracted_diameter <= diameter_range['max']:
            measurement_score += 5
            
            # Check accuracy against ground truth
            if gt_diameter > 0:
                error_pct = abs(extracted_diameter - gt_diameter) / gt_diameter * 100
                details['measurement_error_pct'] = round(error_pct, 1)
                
                if error_pct <= measurement_tolerance_pct:
                    measurement_score += 20
                    feedback_parts.append(f"Diameter accurate ({extracted_diameter:.1f}mm, {error_pct:.1f}% error)")
                elif error_pct <= measurement_tolerance_pct * 2:
                    measurement_score += 10
                    feedback_parts.append(f"Diameter approximate ({extracted_diameter:.1f}mm, {error_pct:.1f}% error)")
                else:
                    feedback_parts.append(f"Diameter inaccurate ({extracted_diameter:.1f}mm vs {gt_diameter:.1f}mm GT)")
            else:
                # No ground truth - give partial credit for plausible measurement
                measurement_score += 10
                feedback_parts.append(f"Diameter measured ({extracted_diameter:.1f}mm)")
        else:
            feedback_parts.append(f"Diameter out of range ({extracted_diameter:.1f}mm)")
    else:
        # Check if line markup exists at all
        line_count = result.get('line_markup_count', 0)
        if line_count > 0:
            measurement_score += 5
            feedback_parts.append(f"Measurement created ({line_count} line(s))")
        else:
            feedback_parts.append("No measurement found")
    
    score += min(measurement_score, w_measurement_accuracy)
    details['measurement_score'] = measurement_score

    # ================================================================
    # VLM VERIFICATION ON TRAJECTORY FRAMES
    # ================================================================
    vlm_tumor_score = 0
    vlm_measurement_score = 0
    vlm_annotation_score = 0
    
    if query_vlm and has_vlm_utils:
        # Copy screenshots for VLM analysis
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        screenshot_available = False
        
        try:
            # Try to get the agent's screenshot
            if result.get('screenshot_exists', False):
                copy_from_env("/tmp/agent_screenshot.png", temp_screenshot.name)
                screenshot_available = True
        except Exception:
            pass
        
        if not screenshot_available:
            try:
                # Fall back to final screenshot
                copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                screenshot_available = True
            except Exception:
                pass

        if screenshot_available:
            # Get trajectory frames for process verification
            frames = []
            if has_vlm_utils:
                try:
                    frames = sample_trajectory_frames(traj, n=5)
                except Exception as e:
                    logger.warning(f"Could not get trajectory frames: {e}")
            
            # Add final screenshot
            final_image = temp_screenshot.name
            
            # ============================================================
            # VLM CHECK 1: Tumor Visible (20 points)
            # ============================================================
            tumor_prompt = """Analyze this medical imaging screenshot from 3D Slicer.

Is a brain tumor visible in the image? Look for:
- A bright/hyperintense region in the brain (FLAIR MRI)
- Irregular shaped mass different from normal brain tissue
- The tumor may appear white/bright against gray brain tissue

Respond in JSON format:
{
    "tumor_visible": true/false,
    "brain_visible": true/false,
    "is_medical_image": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see"
}
"""
            try:
                if frames:
                    # Use multiple frames for more reliable detection
                    vlm_result = query_vlm(prompt=tumor_prompt, images=frames[-3:] + [final_image])
                else:
                    vlm_result = query_vlm(prompt=tumor_prompt, image=final_image)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('tumor_visible', False):
                        vlm_tumor_score = w_tumor_visible
                        feedback_parts.append("VLM: Tumor visible")
                    elif parsed.get('brain_visible', False):
                        vlm_tumor_score = w_tumor_visible * 0.5
                        feedback_parts.append("VLM: Brain visible, tumor unclear")
                    details['vlm_tumor'] = parsed
            except Exception as e:
                logger.warning(f"VLM tumor check failed: {e}")

            # ============================================================
            # VLM CHECK 2: Measurement Line Present (20 points)
            # ============================================================
            measurement_prompt = """Analyze this medical imaging screenshot from 3D Slicer.

Is there a measurement ruler or line visible on the image? Look for:
- A straight line with endpoints across the tumor/lesion
- A ruler annotation showing distance in mm
- Markup indicators (dots at line endpoints)
- A measurement value displayed near the line

Respond in JSON format:
{
    "measurement_line_visible": true/false,
    "measurement_value_shown": true/false,
    "line_crosses_lesion": true/false,
    "confidence": "low"/"medium"/"high",
    "observed_value": "measurement value if visible, else null"
}
"""
            try:
                vlm_result = query_vlm(prompt=measurement_prompt, image=final_image)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('measurement_line_visible', False):
                        if parsed.get('line_crosses_lesion', False):
                            vlm_measurement_score = w_measurement_present
                            feedback_parts.append("VLM: Measurement on tumor")
                        else:
                            vlm_measurement_score = w_measurement_present * 0.7
                            feedback_parts.append("VLM: Measurement line visible")
                    details['vlm_measurement'] = parsed
                    
                    # Try to extract measurement from VLM
                    observed_val = parsed.get('observed_value')
                    if observed_val and extracted_diameter == 0:
                        try:
                            # Parse "XX.X mm" format
                            match = re.search(r'(\d+\.?\d*)\s*mm', str(observed_val))
                            if match:
                                vlm_diameter = float(match.group(1))
                                details['vlm_extracted_diameter_mm'] = vlm_diameter
                        except Exception:
                            pass
            except Exception as e:
                logger.warning(f"VLM measurement check failed: {e}")

            # ============================================================
            # VLM CHECK 3: Text Annotation Present (15 points)
            # ============================================================
            annotation_prompt = """Analyze this medical imaging screenshot from 3D Slicer.

Is there a text annotation showing a diameter measurement? Look for:
- Text label like "Max diameter: XX.X mm" or similar
- Any text showing a measurement value in millimeters
- Annotation near the tumor or measurement line

Respond in JSON format:
{
    "text_annotation_visible": true/false,
    "shows_diameter_value": true/false,
    "annotation_text": "the text if readable, else null",
    "confidence": "low"/"medium"/"high"
}
"""
            try:
                vlm_result = query_vlm(prompt=annotation_prompt, image=final_image)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('text_annotation_visible', False):
                        if parsed.get('shows_diameter_value', False):
                            vlm_annotation_score = w_annotation_present
                            feedback_parts.append("VLM: Diameter annotation present")
                        else:
                            vlm_annotation_score = w_annotation_present * 0.5
                            feedback_parts.append("VLM: Text annotation visible")
                    details['vlm_annotation'] = parsed
            except Exception as e:
                logger.warning(f"VLM annotation check failed: {e}")
        
        # Cleanup temp file
        try:
            os.unlink(temp_screenshot.name)
        except Exception:
            pass
    else:
        # No VLM available - give partial credit based on programmatic checks
        if result.get('line_markup_count', 0) > 0:
            vlm_measurement_score = w_measurement_present * 0.5
            feedback_parts.append("Measurement markup found (no VLM)")
        if result.get('has_annotation', False):
            vlm_annotation_score = w_annotation_present * 0.5
            feedback_parts.append("Annotation found (no VLM)")

    # Add VLM scores
    score += vlm_tumor_score + vlm_measurement_score + vlm_annotation_score
    
    details['vlm_scores'] = {
        'tumor': vlm_tumor_score,
        'measurement': vlm_measurement_score,
        'annotation': vlm_annotation_score
    }

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Determine pass criteria
    screenshot_created = result.get('screenshot_created_during_task', False)
    has_measurement = (
        result.get('line_markup_count', 0) > 0 or 
        vlm_measurement_score > 0 or 
        extracted_diameter > 0
    )
    tumor_detected = vlm_tumor_score > 0
    
    key_criteria_met = screenshot_exists and (tumor_detected or has_measurement)
    passed = score >= 70 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }