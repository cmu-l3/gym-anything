#!/usr/bin/env python3
"""
Verifier for Compare MRI Sequences task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON:
  1. T1 volume loaded (10 pts)
  2. T1ce volume loaded (10 pts)  
  3. T2 volume loaded (10 pts)
  4. FLAIR volume loaded (10 pts)
  5. Layout changed to multi-panel (20 pts)
  6. Screenshot saved and valid size (10 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  7. Multiple contrasts visible (15 pts): VLM confirms different MRI contrasts shown
  8. Multi-panel layout visible (10 pts): VLM confirms multiple viewing panels
  9. Consistent anatomical region (5 pts): VLM confirms brain anatomy visible

Pass threshold: 70 points with at least 3 volumes loaded
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_mri_sequences(traj, env_info, task_info):
    """
    Verify that multiple MRI sequences were loaded and displayed in comparison layout.
    
    Uses multi-criteria scoring with programmatic checks and VLM verification.
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
    expected_sequences = metadata.get('expected_sequences', ['t1', 't1ce', 't2', 'flair'])
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 50)
    weights = metadata.get('scoring_weights', {})
    
    w_t1 = weights.get('t1_loaded', 10)
    w_t1ce = weights.get('t1ce_loaded', 10)
    w_t2 = weights.get('t2_loaded', 10)
    w_flair = weights.get('flair_loaded', 10)
    w_layout = weights.get('layout_changed', 20)
    w_vlm_contrasts = weights.get('multiple_contrasts_visible', 15)
    w_screenshot = weights.get('screenshot_saved', 10)
    w_dimensions = weights.get('correct_dimensions', 10)
    w_consistent = weights.get('consistent_region', 5)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ============================================================
    # Load result JSON from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mri_compare_result.json", temp_result.name)
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

    details['raw_result'] = result

    # ============================================================
    # Check if Slicer was running
    # ============================================================
    if not result.get('slicer_running', False):
        feedback_parts.append("Slicer was not running")
        # Don't immediately fail - check what we can
    else:
        feedback_parts.append("Slicer running")

    # ============================================================
    # CRITERION 1-4: Individual sequence loading (10 pts each)
    # ============================================================
    sequences_loaded = 0
    
    # T1
    if result.get('t1_loaded', False):
        score += w_t1
        sequences_loaded += 1
        feedback_parts.append("T1 loaded")
    else:
        feedback_parts.append("T1 NOT loaded")
    
    # T1ce
    if result.get('t1ce_loaded', False):
        score += w_t1ce
        sequences_loaded += 1
        feedback_parts.append("T1ce loaded")
    else:
        feedback_parts.append("T1ce NOT loaded")
    
    # T2
    if result.get('t2_loaded', False):
        score += w_t2
        sequences_loaded += 1
        feedback_parts.append("T2 loaded")
    else:
        feedback_parts.append("T2 NOT loaded")
    
    # FLAIR
    if result.get('flair_loaded', False):
        score += w_flair
        sequences_loaded += 1
        feedback_parts.append("FLAIR loaded")
    else:
        feedback_parts.append("FLAIR NOT loaded")
    
    details['sequences_loaded'] = sequences_loaded
    details['volume_count'] = result.get('volume_count', 0)

    # ============================================================
    # CRITERION 5: Layout changed to multi-panel (20 pts)
    # ============================================================
    layout_is_multipanel = result.get('layout_is_multipanel', False)
    layout_id = result.get('layout_id', -1)
    layout_name = result.get('layout_name', 'unknown')
    slice_view_count = result.get('slice_view_count', 0)
    
    if layout_is_multipanel:
        score += w_layout
        feedback_parts.append(f"Multi-panel layout ({layout_name})")
    elif slice_view_count >= 3:
        # Partial credit if multiple views but not recognized multi-panel
        score += int(w_layout * 0.6)
        feedback_parts.append(f"Multiple views ({slice_view_count})")
    elif layout_id != 1 and layout_id > 0:
        # Some credit for changing from default
        score += int(w_layout * 0.3)
        feedback_parts.append(f"Layout changed from default ({layout_name})")
    else:
        feedback_parts.append("Layout NOT changed to multi-panel")
    
    details['layout_id'] = layout_id
    details['layout_name'] = layout_name
    details['layout_is_multipanel'] = layout_is_multipanel

    # ============================================================
    # CRITERION 6: Screenshot saved (10 pts)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size_bytes = result.get('screenshot_size_bytes', 0)
    screenshot_created_during_task = result.get('screenshot_created_during_task', False)
    screenshot_size_kb = screenshot_size_bytes / 1024.0
    
    if screenshot_exists and screenshot_created_during_task:
        if screenshot_size_kb >= min_screenshot_size_kb:
            score += w_screenshot
            feedback_parts.append(f"Screenshot saved ({screenshot_size_kb:.1f}KB)")
        else:
            score += int(w_screenshot * 0.5)
            feedback_parts.append(f"Screenshot small ({screenshot_size_kb:.1f}KB)")
    elif screenshot_exists:
        score += int(w_screenshot * 0.3)
        feedback_parts.append("Screenshot exists (not created during task)")
    elif result.get('new_screenshot_count', 0) > 0:
        score += int(w_screenshot * 0.5)
        feedback_parts.append(f"{result.get('new_screenshot_count')} new screenshot(s)")
    else:
        feedback_parts.append("Screenshot NOT saved")
    
    details['screenshot_exists'] = screenshot_exists
    details['screenshot_size_kb'] = screenshot_size_kb

    # ============================================================
    # CRITERION 7-9: VLM verification using trajectory frames
    # ============================================================
    vlm_score = 0
    vlm_feedback = []
    
    # Try to get VLM query function from env_info
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            # Combine for comprehensive verification
            all_frames = trajectory_frames + ([final_screenshot] if final_screenshot else [])
            
            if all_frames:
                # VLM Check: Multiple MRI contrasts visible
                contrast_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The user was asked to load and compare 4 different MRI sequences of a brain:
- T1-weighted (CSF appears dark)
- T1 contrast-enhanced (similar to T1 but with bright enhancing regions)
- T2-weighted (CSF appears bright)
- FLAIR (similar to T2 but CSF is suppressed/dark)

Looking at the final frames, assess:
1. Are there multiple viewing panels showing brain MRI data?
2. Do different panels show visibly different MRI contrasts?
   (Look for differences in how bright/dark the ventricles/CSF appears)
3. Is brain anatomy clearly visible (gray matter, white matter, ventricles)?

Respond in JSON format:
{
    "multiple_panels_visible": true/false,
    "different_contrasts_visible": true/false,
    "brain_anatomy_visible": true/false,
    "estimated_panel_count": <number>,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=contrast_prompt, images=all_frames[-3:])
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Multiple contrasts visible (15 pts)
                    if parsed.get('different_contrasts_visible', False):
                        vlm_score += w_vlm_contrasts
                        vlm_feedback.append("VLM: Different contrasts visible")
                    elif parsed.get('multiple_panels_visible', False):
                        vlm_score += int(w_vlm_contrasts * 0.5)
                        vlm_feedback.append("VLM: Multiple panels, contrasts unclear")
                    
                    # Multi-panel layout (10 pts) - supplement programmatic check
                    panel_count = parsed.get('estimated_panel_count', 1)
                    if parsed.get('multiple_panels_visible', False) and panel_count >= 3:
                        vlm_score += w_dimensions  # Repurposed for VLM multi-panel
                        vlm_feedback.append(f"VLM: {panel_count} panels visible")
                    elif panel_count >= 2:
                        vlm_score += int(w_dimensions * 0.5)
                        vlm_feedback.append(f"VLM: {panel_count} panels")
                    
                    # Brain anatomy visible (5 pts)
                    if parsed.get('brain_anatomy_visible', False):
                        vlm_score += w_consistent
                        vlm_feedback.append("VLM: Brain anatomy visible")
                    
                    details['vlm_result'] = parsed
                else:
                    vlm_feedback.append("VLM query returned no result")
            else:
                vlm_feedback.append("No trajectory frames available")
                
        except ImportError as e:
            vlm_feedback.append(f"VLM module not available: {e}")
        except Exception as e:
            vlm_feedback.append(f"VLM verification error: {e}")
            logger.warning(f"VLM verification failed: {e}")
    else:
        vlm_feedback.append("VLM verification skipped (no query function or trajectory)")
    
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ============================================================
    # Final scoring and pass determination
    # ============================================================
    
    # Key criteria: At least 3 volumes loaded AND some evidence of work
    key_criteria_met = (
        sequences_loaded >= 3 and
        (layout_is_multipanel or slice_view_count >= 3 or screenshot_exists)
    )
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Alternative pass: if 4 volumes loaded and layout changed, even without screenshot
    if not passed and sequences_loaded == 4 and layout_is_multipanel:
        passed = score >= 60
    
    details['sequences_loaded'] = sequences_loaded
    details['key_criteria_met'] = key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }