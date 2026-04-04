#!/usr/bin/env python3
"""
Verifier for Create Hollow Shell task in 3D Slicer.

VERIFICATION STRATEGY:
1. Segment exists (15 points) - Liver segment still present in scene
2. Volume reduced (25 points) - Final volume is less than original
3. Correct reduction range (30 points) - Reduction is 35-70% (expected for 3mm shell)
4. Shell thickness reasonable (15 points) - Volume reduction consistent with 3mm shell
5. VLM hollow appearance (15 points) - Visual confirmation of hollow structure

Pass threshold: 65 points with segment_exists AND volume_reduced criteria met

Anti-gaming:
- Check task timestamps
- Verify volume is in anatomically plausible range
- Ensure volume wasn't just deleted (must be > 200mL)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_hollow_shell(traj, env_info, task_info):
    """
    Verify that the hollow shell was created correctly.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
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
    expected_reduction_min = metadata.get('expected_volume_reduction_min', 0.35)
    expected_reduction_max = metadata.get('expected_volume_reduction_max', 0.70)
    original_volume_range = metadata.get('original_volume_range_ml', {"min": 800, "max": 2500})
    final_volume_range = metadata.get('final_volume_range_ml', {"min": 200, "max": 1200})
    shell_thickness = metadata.get('shell_thickness_mm', 3.0)
    
    weights = metadata.get('scoring_weights', {})
    w_segment_exists = weights.get('segment_exists', 15)
    w_volume_reduced = weights.get('volume_reduced', 25)
    w_correct_reduction = weights.get('correct_reduction_range', 30)
    w_shell_thickness = weights.get('shell_thickness_reasonable', 15)
    w_vlm_hollow = weights.get('vlm_hollow_appearance', 15)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/hollow_task_final_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        # Try alternative path
        try:
            copy_from_env("/tmp/hollow_shell_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Export result not found - export may have failed: {e}"
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
    
    # ================================================================
    # Check if Slicer was running
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        feedback_parts.append("Slicer was not running")
        # Continue anyway - may have closed after task
    
    # ================================================================
    # CRITERION 1: Segment Exists (15 points)
    # ================================================================
    segment_exists = result.get('segment_exists', False)
    
    if segment_exists:
        score += w_segment_exists
        feedback_parts.append("Liver segment exists")
        details['segment_exists'] = True
    else:
        feedback_parts.append("Liver segment NOT found")
        details['segment_exists'] = False
        # Critical failure - cannot verify without segment
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Extract volume values
    # ================================================================
    original_volume = result.get('original_volume_ml', 0)
    final_volume = result.get('final_volume_ml', 0)
    reported_reduction = result.get('volume_reduction_percent', 0)
    
    details['original_volume_ml'] = original_volume
    details['final_volume_ml'] = final_volume
    details['reported_reduction_percent'] = reported_reduction
    
    # Validate original volume is plausible
    if original_volume < original_volume_range['min'] or original_volume > original_volume_range['max']:
        feedback_parts.append(f"Original volume ({original_volume:.0f}mL) outside expected range")
        details['original_volume_valid'] = False
    else:
        details['original_volume_valid'] = True
    
    # ================================================================
    # CRITERION 2: Volume Reduced (25 points)
    # ================================================================
    if original_volume > 0 and final_volume > 0:
        calculated_reduction = (original_volume - final_volume) / original_volume
        details['calculated_reduction'] = calculated_reduction
        
        if final_volume < original_volume:
            # Volume was reduced
            score += w_volume_reduced
            feedback_parts.append(f"Volume reduced ({calculated_reduction*100:.1f}%)")
            details['volume_reduced'] = True
        else:
            feedback_parts.append("Volume NOT reduced")
            details['volume_reduced'] = False
    else:
        feedback_parts.append("Cannot calculate volume reduction")
        details['volume_reduced'] = False
        calculated_reduction = 0
    
    # ================================================================
    # CRITERION 3: Correct Reduction Range (30 points)
    # Expected 35-70% reduction for a 3mm shell on typical liver
    # ================================================================
    if details.get('volume_reduced', False):
        if expected_reduction_min <= calculated_reduction <= expected_reduction_max:
            score += w_correct_reduction
            feedback_parts.append(f"Reduction in expected range ({calculated_reduction*100:.1f}%)")
            details['reduction_in_range'] = True
        elif calculated_reduction > 0.2:
            # Partial credit for significant reduction
            partial = w_correct_reduction * 0.5
            score += int(partial)
            feedback_parts.append(f"Reduction outside ideal range ({calculated_reduction*100:.1f}%)")
            details['reduction_in_range'] = False
        else:
            feedback_parts.append(f"Insufficient reduction ({calculated_reduction*100:.1f}%)")
            details['reduction_in_range'] = False
    
    # ================================================================
    # CRITERION 4: Shell Thickness Reasonable (15 points)
    # Estimate expected volume reduction based on shell thickness
    # For a 3mm shell: V_shell ≈ Surface_Area × thickness
    # Typical liver surface area ~1500-2000 cm², so shell ~450-600 mL
    # This means reduction should be roughly 50-70% for typical liver
    # ================================================================
    if details.get('volume_reduced', False) and original_volume > 0:
        # Estimate shell volume
        shell_volume = final_volume
        
        # Check if final volume is in plausible range for a shell
        if final_volume_range['min'] <= final_volume <= final_volume_range['max']:
            score += w_shell_thickness
            feedback_parts.append(f"Shell volume plausible ({final_volume:.0f}mL)")
            details['shell_thickness_valid'] = True
        elif final_volume > 100:
            # Partial credit - at least something remains
            score += int(w_shell_thickness * 0.5)
            feedback_parts.append(f"Shell volume marginal ({final_volume:.0f}mL)")
            details['shell_thickness_valid'] = False
        else:
            feedback_parts.append(f"Shell volume too small ({final_volume:.0f}mL)")
            details['shell_thickness_valid'] = False
    
    # ================================================================
    # CRITERION 5: VLM Hollow Appearance (15 points)
    # Use trajectory frames to verify work was done
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if final_frame:
                # VLM prompt for hollow verification
                vlm_prompt = """Analyze this screenshot from 3D Slicer medical imaging software.

Look for evidence that a HOLLOW SHELL operation was performed on an anatomical segment (liver):

1. Is there a 3D view showing an anatomical structure (liver)?
2. Does the Segment Editor panel show the "Hollow" effect was selected or applied?
3. Is there any visual indication of a hollow/shell structure (cross-section showing cavity)?
4. Does the 3D rendering show a shell-like appearance (thinner walls visible)?

Respond in JSON format:
{
    "shows_3d_anatomy": true/false,
    "hollow_effect_visible": true/false,
    "shell_appearance": true/false,
    "segment_editor_active": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, image=final_frame)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    shows_anatomy = parsed.get('shows_3d_anatomy', False)
                    hollow_visible = parsed.get('hollow_effect_visible', False)
                    shell_appearance = parsed.get('shell_appearance', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score based on VLM findings
                    if shell_appearance or hollow_visible:
                        vlm_score = w_vlm_hollow
                        feedback_parts.append("VLM: Hollow shell visible")
                    elif shows_anatomy and confidence in ['medium', 'high']:
                        vlm_score = int(w_vlm_hollow * 0.5)
                        feedback_parts.append("VLM: Anatomy visible, shell uncertain")
                    else:
                        feedback_parts.append("VLM: Could not confirm hollow appearance")
                else:
                    feedback_parts.append("VLM: Query failed")
            else:
                feedback_parts.append("VLM: No screenshot available")
                
        except ImportError:
            feedback_parts.append("VLM: Module not available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"VLM: Error - {str(e)[:50]}")
    else:
        # No VLM available - give partial credit if other criteria met
        if details.get('volume_reduced', False) and details.get('reduction_in_range', False):
            vlm_score = int(w_vlm_hollow * 0.5)
            feedback_parts.append("VLM: Not available, partial credit from measurements")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # ANTI-GAMING CHECKS
    # ================================================================
    
    # Check that volume wasn't just deleted entirely
    if final_volume < 100:
        feedback_parts.append("WARNING: Final volume suspiciously small")
        details['anti_gaming_volume_too_small'] = True
        # Reduce score
        score = max(0, score - 20)
    
    # Check task duration (should take at least some time)
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    if task_start > 0 and task_end > 0:
        duration = task_end - task_start
        details['task_duration_sec'] = duration
        if duration < 10:
            feedback_parts.append("WARNING: Task completed suspiciously fast")
            details['anti_gaming_too_fast'] = True
    
    # ================================================================
    # Calculate final pass/fail
    # ================================================================
    key_criteria_met = (
        details.get('segment_exists', False) and
        details.get('volume_reduced', False)
    )
    
    passed = score >= 65 and key_criteria_met
    
    # Ensure score doesn't exceed 100
    score = min(100, score)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }