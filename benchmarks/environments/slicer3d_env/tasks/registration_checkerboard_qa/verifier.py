#!/usr/bin/env python3
"""
Verifier for Registration Checkerboard QA task.

VERIFICATION STRATEGY:
1. Screenshot file exists (15 points)
2. Screenshot shows checkerboard pattern - VLM check (25 points)
3. Brain anatomy visible - VLM check (15 points)
4. Report file exists (15 points)
5. Valid report structure (10 points)
6. Misalignment correctly detected (20 points)

Pass threshold: 55 points with Screenshot Shows Checkerboard achieved
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_registration_checkerboard_qa(traj, env_info, task_info):
    """
    Verify that checkerboard visualization was created and alignment assessed.
    
    Uses multi-signal verification:
    1. Programmatic checks on files and report content
    2. VLM verification of trajectory frames for checkerboard pattern
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
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 50)
    known_shift_mm = metadata.get('known_shift_mm', 4.0)
    
    weights = metadata.get('scoring_weights', {})
    w_screenshot_exists = weights.get('screenshot_exists', 15)
    w_screenshot_checkerboard = weights.get('screenshot_shows_checkerboard', 25)
    w_brain_visible = weights.get('brain_anatomy_visible', 15)
    w_report_exists = weights.get('report_file_exists', 15)
    w_valid_structure = weights.get('valid_report_structure', 10)
    w_misalignment_detected = weights.get('misalignment_correctly_detected', 20)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    key_criteria_met = False
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/checkerboard_task_result.json", temp_result.name)
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
    
    details['export_result'] = result
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer was not running")
        # Don't return early - still check files
    
    # ================================================================
    # CRITERION 1: Screenshot file exists (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    screenshot_created_during_task = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_size_kb >= min_screenshot_size_kb:
        if screenshot_created_during_task:
            score += w_screenshot_exists
            feedback_parts.append(f"Screenshot saved ({screenshot_size_kb}KB)")
        else:
            score += w_screenshot_exists * 0.5
            feedback_parts.append(f"Screenshot exists but may be pre-existing ({screenshot_size_kb}KB)")
    elif screenshot_exists:
        score += w_screenshot_exists * 0.3
        feedback_parts.append(f"Screenshot too small ({screenshot_size_kb}KB)")
    else:
        feedback_parts.append("Screenshot not found")
    
    details['screenshot_exists'] = screenshot_exists
    details['screenshot_size_kb'] = screenshot_size_kb
    
    # ================================================================
    # CRITERION 2 & 3: VLM verification of screenshot content
    # Uses TRAJECTORY frames, not just final screenshot
    # ================================================================
    vlm_checkerboard_score = 0
    vlm_brain_score = 0
    
    # Try to get VLM functions from env_info
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import VLM helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames (shows progression of work)
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            # Combine for comprehensive analysis
            all_frames = []
            if trajectory_frames:
                all_frames.extend(trajectory_frames)
            if final_screenshot:
                all_frames.append(final_screenshot)
            
            if all_frames:
                # VLM prompt for checkerboard detection
                checkerboard_prompt = """Analyze these screenshots from 3D Slicer medical imaging software.

The user was tasked with creating a CHECKERBOARD visualization to compare two brain MRI volumes.

A checkerboard visualization shows:
- Alternating rectangular tiles from two different images
- Creates a "checkerboard" or "grid" pattern
- Used to assess registration/alignment between images
- At tile boundaries, you can see if structures line up or show "steps"

Look at these images and determine:

1. CHECKERBOARD_VISIBLE: Is there a checkerboard pattern visible in any slice view?
   - Look for alternating rectangular regions
   - The tiles alternate between slightly different brightness/contrast
   - NOT just a regular brain image, must show the tiled pattern

2. BRAIN_ANATOMY_VISIBLE: Can you see brain structures (ventricles, gray matter, white matter)?

3. MISALIGNMENT_VISIBLE: At tile boundaries, do edges appear continuous (aligned) or stepped (misaligned)?

Respond in JSON format:
{
    "checkerboard_visible": true/false,
    "brain_anatomy_visible": true/false,
    "misalignment_at_boundaries": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=checkerboard_prompt, images=all_frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    checkerboard_visible = parsed.get('checkerboard_visible', False)
                    brain_visible = parsed.get('brain_anatomy_visible', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score checkerboard visibility
                    if checkerboard_visible:
                        key_criteria_met = True
                        if confidence == 'high':
                            vlm_checkerboard_score = w_screenshot_checkerboard
                        elif confidence == 'medium':
                            vlm_checkerboard_score = w_screenshot_checkerboard * 0.8
                        else:
                            vlm_checkerboard_score = w_screenshot_checkerboard * 0.6
                        feedback_parts.append("VLM: Checkerboard pattern detected")
                    else:
                        feedback_parts.append("VLM: No checkerboard pattern detected")
                    
                    # Score brain visibility
                    if brain_visible:
                        vlm_brain_score = w_brain_visible
                        feedback_parts.append("VLM: Brain anatomy visible")
                    else:
                        vlm_brain_score = 0
                        feedback_parts.append("VLM: Brain anatomy not clearly visible")
                else:
                    logger.warning("VLM query failed or returned no result")
                    details['vlm_error'] = vlm_result.get('error', 'Unknown error') if vlm_result else 'No result'
        except ImportError:
            logger.warning("Could not import VLM helpers")
            details['vlm_error'] = 'VLM helpers not available'
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    else:
        # Fallback: use screenshot size as proxy for content
        if screenshot_exists and screenshot_size_kb > 100:
            vlm_checkerboard_score = w_screenshot_checkerboard * 0.3
            vlm_brain_score = w_brain_visible * 0.3
            feedback_parts.append("Large screenshot (VLM unavailable)")
            details['vlm_error'] = 'VLM not available, using size heuristic'
    
    score += vlm_checkerboard_score
    score += vlm_brain_score
    
    # ================================================================
    # CRITERION 4: Report file exists (15 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        score += w_report_exists
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file not found")
    
    details['report_exists'] = report_exists
    
    # ================================================================
    # CRITERION 5: Valid report structure (10 points)
    # ================================================================
    report_valid = result.get('report_valid_json', False)
    report_has_fields = result.get('report_has_required_fields', False)
    
    if report_valid and report_has_fields:
        score += w_valid_structure
        feedback_parts.append("Report has valid structure")
    elif report_valid:
        score += w_valid_structure * 0.5
        feedback_parts.append("Report valid JSON but missing fields")
    else:
        feedback_parts.append("Report invalid or missing fields")
    
    # ================================================================
    # CRITERION 6: Misalignment correctly detected (20 points)
    # ================================================================
    reported_misalignment = result.get('reported_misalignment_detected', None)
    reported_shift = result.get('reported_shift_mm', 0)
    gt_expected_detection = result.get('ground_truth_expected_detection', True)
    gt_shift_mm = result.get('ground_truth_shift_mm', known_shift_mm)
    
    details['reported_misalignment'] = reported_misalignment
    details['reported_shift_mm'] = reported_shift
    details['expected_shift_mm'] = gt_shift_mm
    
    if reported_misalignment is True and gt_expected_detection:
        # Agent correctly detected misalignment
        score += w_misalignment_detected * 0.7
        feedback_parts.append("Correctly detected misalignment")
        
        # Bonus for accurate shift estimate
        if reported_shift and isinstance(reported_shift, (int, float)):
            shift_error = abs(float(reported_shift) - gt_shift_mm)
            if shift_error <= 2.0:  # Within 2mm
                score += w_misalignment_detected * 0.3
                feedback_parts.append(f"Shift estimate close ({reported_shift}mm vs {gt_shift_mm}mm)")
            elif shift_error <= 5.0:  # Within 5mm
                score += w_misalignment_detected * 0.15
                feedback_parts.append(f"Shift estimate approximate ({reported_shift}mm)")
    elif reported_misalignment is False and gt_expected_detection:
        # Agent failed to detect misalignment
        feedback_parts.append("Failed to detect misalignment")
    elif reported_misalignment is None:
        feedback_parts.append("Misalignment detection not reported")
    
    # Check alignment quality assessment
    reported_quality = result.get('reported_alignment_quality', 'unknown')
    details['reported_quality'] = reported_quality
    
    # ================================================================
    # Calculate final result
    # ================================================================
    
    # Pass threshold: 55 points AND key criteria (checkerboard visible)
    passed = score >= 55 and key_criteria_met
    
    # Alternative pass: if VLM unavailable but all other checks pass
    if not passed and score >= 60 and screenshot_exists and report_exists and reported_misalignment is True:
        passed = True
        feedback_parts.append("Passed via alternative criteria")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }