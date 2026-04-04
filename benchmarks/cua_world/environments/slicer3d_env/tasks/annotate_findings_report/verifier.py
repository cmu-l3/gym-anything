#!/usr/bin/env python3
"""
Verifier for annotate_findings_report task.

VERIFICATION CRITERIA:
1. Ruler markup created (20 points) - A line/ruler markup exists
2. Ruler has valid length (15 points) - Measurement is 50-100mm (anatomically plausible)
3. Text annotation created (20 points) - A text annotation node exists
4. Text contains content (10 points) - Annotation text is non-empty and descriptive
5. Screenshot exists (15 points) - File saved to correct location
6. Screenshot has content (10 points) - File size > 50KB
7. Correct view orientation (10 points) - VLM confirms sagittal view/annotations visible

Pass threshold: 70 points with ruler AND text annotation created
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_annotate_findings_report(traj, env_info, task_info):
    """
    Verify that clinical annotations were created and screenshot captured.
    
    Uses multi-criteria scoring with programmatic checks and VLM trajectory verification.
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
    ruler_range = metadata.get('expected_ruler_length_mm', {"min": 50, "max": 100})
    min_screenshot_kb = metadata.get('min_screenshot_size_kb', 50)
    expected_text = metadata.get('expected_text_content', 'Corpus Callosum')
    
    weights = metadata.get('scoring_weights', {})
    w_ruler_created = weights.get('ruler_created', 20)
    w_ruler_valid = weights.get('ruler_valid_length', 15)
    w_text_created = weights.get('text_created', 20)
    w_text_content = weights.get('text_has_content', 10)
    w_screenshot_exists = weights.get('screenshot_exists', 15)
    w_screenshot_content = weights.get('screenshot_has_content', 10)
    w_correct_view = weights.get('correct_view', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/annotation_task_result.json", temp_result.name)
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

    # ================================================================
    # CRITERION 1: Ruler Markup Created (20 points)
    # ================================================================
    ruler_exists = result.get('ruler_exists', False)
    ruler_length = float(result.get('ruler_length_mm', 0))
    
    if ruler_exists:
        score += w_ruler_created
        feedback_parts.append(f"Ruler created ({ruler_length:.1f}mm)")
        details['ruler_created'] = True
        details['ruler_length_mm'] = ruler_length
    else:
        feedback_parts.append("No ruler markup found")
        details['ruler_created'] = False

    # ================================================================
    # CRITERION 2: Ruler Has Valid Length (15 points)
    # ================================================================
    ruler_min = ruler_range.get('min', 50)
    ruler_max = ruler_range.get('max', 100)
    
    if ruler_exists and ruler_min <= ruler_length <= ruler_max:
        score += w_ruler_valid
        feedback_parts.append("Ruler length valid")
        details['ruler_length_valid'] = True
    elif ruler_exists and ruler_length > 0:
        # Partial credit for having a measurement, even if outside expected range
        # Could be legitimate anatomical variation
        if 30 <= ruler_length <= 150:
            score += int(w_ruler_valid * 0.5)
            feedback_parts.append(f"Ruler length outside expected range ({ruler_min}-{ruler_max}mm)")
            details['ruler_length_valid'] = False
            details['ruler_length_note'] = 'Outside expected but plausible'
        else:
            feedback_parts.append(f"Ruler length implausible ({ruler_length:.1f}mm)")
            details['ruler_length_valid'] = False
    else:
        details['ruler_length_valid'] = False

    # ================================================================
    # CRITERION 3: Text Annotation Created (20 points)
    # ================================================================
    text_exists = result.get('text_exists', False)
    text_content = result.get('text_content', '')
    
    if text_exists:
        score += w_text_created
        feedback_parts.append("Text annotation created")
        details['text_created'] = True
        details['text_content'] = text_content
    else:
        # Check fiducial count as potential alternative
        fiducial_count = result.get('fiducial_count', 0)
        if fiducial_count > 0:
            # Partial credit if fiducials exist (might be used for annotation)
            score += int(w_text_created * 0.3)
            feedback_parts.append(f"No text annotation, but {fiducial_count} fiducial(s) found")
            details['text_created'] = False
            details['fiducials_found'] = fiducial_count
        else:
            feedback_parts.append("No text annotation found")
            details['text_created'] = False

    # ================================================================
    # CRITERION 4: Text Contains Content (10 points)
    # ================================================================
    if text_exists and text_content:
        text_lower = text_content.lower()
        # Check for relevant clinical content
        has_relevant_content = any(term in text_lower for term in 
                                   ['corpus', 'callosum', 'normal', 'cc', 'brain'])
        if has_relevant_content:
            score += w_text_content
            feedback_parts.append(f"Text content relevant: '{text_content[:30]}..'" if len(text_content) > 30 else f"Text: '{text_content}'")
            details['text_content_valid'] = True
        elif len(text_content) > 0:
            score += int(w_text_content * 0.5)
            feedback_parts.append(f"Text content generic: '{text_content[:20]}'")
            details['text_content_valid'] = False
            details['text_content_note'] = 'Content present but not clinically specific'
    else:
        details['text_content_valid'] = False

    # ================================================================
    # CRITERION 5: Screenshot Exists (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_created_during_task = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists:
        if screenshot_created_during_task:
            score += w_screenshot_exists
            feedback_parts.append("Screenshot saved during task")
            details['screenshot_created'] = True
        else:
            # Screenshot exists but wasn't created during task - might be pre-existing
            score += int(w_screenshot_exists * 0.5)
            feedback_parts.append("Screenshot exists (may be pre-existing)")
            details['screenshot_created'] = 'uncertain'
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_created'] = False

    # ================================================================
    # CRITERION 6: Screenshot Has Content (10 points)
    # ================================================================
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    
    if screenshot_exists and screenshot_size_kb >= min_screenshot_kb:
        score += w_screenshot_content
        feedback_parts.append(f"Screenshot has content ({screenshot_size_kb}KB)")
        details['screenshot_has_content'] = True
    elif screenshot_exists and screenshot_size_kb > 10:
        score += int(w_screenshot_content * 0.5)
        feedback_parts.append(f"Screenshot small ({screenshot_size_kb}KB)")
        details['screenshot_has_content'] = 'partial'
    else:
        details['screenshot_has_content'] = False

    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # Uses trajectory frames to verify work was actually done
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Try to import VLM utilities from gym_anything
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        trajectory_frames = sample_trajectory_frames(traj, n=4)
        final_screenshot = get_final_screenshot(traj)
        
        if trajectory_frames or final_screenshot:
            # Prepare images for VLM
            images_for_vlm = []
            if trajectory_frames:
                images_for_vlm.extend(trajectory_frames)
            if final_screenshot:
                images_for_vlm.append(final_screenshot)
            
            # VLM prompt for annotation verification
            vlm_prompt = """You are verifying a medical image annotation task in 3D Slicer.

The agent was asked to:
1. Load a brain MRI and navigate to sagittal view
2. Create a ruler/line measurement across the corpus callosum
3. Add a text annotation label
4. Save a screenshot

Analyze these screenshots (chronological from agent's work) and assess:

1. SAGITTAL_VIEW: Is a sagittal brain MRI slice visible (showing brain in profile view)?
2. RULER_VISIBLE: Is there a measurement line/ruler visible on the image?
3. TEXT_VISIBLE: Is there any text annotation visible in the viewer?
4. CORPUS_CALLOSUM: Does the measurement appear to be across the corpus callosum (the white curved structure connecting brain hemispheres)?
5. ANNOTATION_WORKFLOW: Does the sequence show the agent performing annotation work?

Respond in JSON format:
{
    "sagittal_view_visible": true/false,
    "ruler_visible": true/false,
    "text_annotation_visible": true/false,
    "corpus_callosum_measured": true/false,
    "annotation_workflow_evident": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(images=images_for_vlm, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                # Award points based on VLM findings
                vlm_checks = 0
                if parsed.get('sagittal_view_visible'):
                    vlm_checks += 1
                if parsed.get('ruler_visible'):
                    vlm_checks += 1
                if parsed.get('text_annotation_visible'):
                    vlm_checks += 1
                if parsed.get('annotation_workflow_evident'):
                    vlm_checks += 1
                
                # Scale VLM score based on findings
                vlm_score = int((vlm_checks / 4) * w_correct_view)
                vlm_feedback = f"VLM: {vlm_checks}/4 checks passed"
                
                confidence = parsed.get('confidence', 'low')
                if confidence == 'high':
                    vlm_score = min(vlm_score + 2, w_correct_view)
                
            else:
                vlm_feedback = "VLM query failed"
                details['vlm_error'] = vlm_result.get('error', 'Unknown') if vlm_result else 'No response'
                
    except ImportError:
        vlm_feedback = "VLM not available"
        details['vlm_available'] = False
        # Award partial points if other evidence is strong
        if ruler_exists and text_exists and screenshot_exists:
            vlm_score = int(w_correct_view * 0.5)
            vlm_feedback = "VLM unavailable, partial credit from evidence"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)
        # Award partial points if other evidence is strong
        if ruler_exists and text_exists:
            vlm_score = int(w_correct_view * 0.3)
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    max_score = 100
    
    # Key criteria for passing
    key_criteria_met = ruler_exists and text_exists
    
    # Pass threshold: 70 points with key criteria
    passed = (score >= 70) and key_criteria_met
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        if not key_criteria_met:
            if not ruler_exists:
                feedback = f"FAILED ({score}/100) - Missing ruler: " + feedback
            elif not text_exists:
                feedback = f"FAILED ({score}/100) - Missing text annotation: " + feedback
        else:
            feedback = f"FAILED ({score}/100) - Below threshold: " + feedback

    details['raw_result'] = result
    details['final_score'] = score
    details['key_criteria_met'] = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }