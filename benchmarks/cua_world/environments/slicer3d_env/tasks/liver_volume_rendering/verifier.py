#!/usr/bin/env python3
"""
Verifier for liver_volume_rendering task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (45 points):
  1. Screenshot exists (15 pts) - output file at expected path
  2. Screenshot size valid (10 pts) - file > 100KB indicates real content
  3. Volume rendering enabled (20 pts) - Slicer API confirms VR is active

VLM checks on TRAJECTORY frames (55 points):
  4. Soft tissue visible (25 pts) - liver parenchyma rendered semi-transparent
  5. Vasculature visible (20 pts) - portal/hepatic veins distinguishable
  6. Appropriate transparency (10 pts) - can see internal structures

Pass threshold: 70 points with "volume rendering enabled" criterion met
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_liver_volume_rendering(traj, env_info, task_info):
    """
    Verify that volume rendering was configured for liver surgical planning.
    
    Uses multiple independent signals including trajectory-based VLM verification.
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
    expected_output_path = metadata.get('expected_screenshot_path', 
                                        '/home/ga/Documents/SlicerData/Exports/liver_volume_rendering.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 100)
    
    weights = metadata.get('scoring_weights', {})
    w_screenshot_exists = weights.get('screenshot_exists', 15)
    w_screenshot_size = weights.get('screenshot_size_valid', 10)
    w_vr_enabled = weights.get('volume_rendering_enabled', 20)
    w_soft_tissue = weights.get('soft_tissue_visible_vlm', 25)
    w_vasculature = weights.get('vasculature_visible_vlm', 20)
    w_transparency = weights.get('appropriate_transparency_vlm', 10)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # LOAD RESULT JSON FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/liver_vr_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_loaded'] = True
    except FileNotFoundError:
        feedback_parts.append("Export result not found")
        details['export_loaded'] = False
    except json.JSONDecodeError as e:
        feedback_parts.append(f"Invalid JSON in result: {e}")
        details['export_loaded'] = False
    except Exception as e:
        feedback_parts.append(f"Failed to read result: {e}")
        details['export_loaded'] = False
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not load task result - export script may have failed",
            "details": details
        }
    
    # ================================================================
    # CRITERION 1: Screenshot exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += w_screenshot_exists
        feedback_parts.append(f"✓ Screenshot created during task ({w_screenshot_exists} pts)")
        details['screenshot_created'] = True
    elif output_exists:
        # File exists but wasn't created during task - partial credit
        score += w_screenshot_exists // 2
        feedback_parts.append(f"~ Screenshot exists but not created during task ({w_screenshot_exists // 2}/{w_screenshot_exists} pts)")
        details['screenshot_created'] = False
    else:
        feedback_parts.append(f"✗ Screenshot not found at expected path (0/{w_screenshot_exists} pts)")
        details['screenshot_created'] = False
    
    # ================================================================
    # CRITERION 2: Screenshot size valid (10 points)
    # ================================================================
    output_size_kb = result.get('output_size_kb', 0)
    screenshot_has_content = result.get('screenshot_has_content', 'false')
    
    if output_size_kb >= min_size_kb:
        score += w_screenshot_size
        feedback_parts.append(f"✓ Screenshot size valid: {output_size_kb}KB ({w_screenshot_size} pts)")
        details['size_valid'] = True
    elif output_size_kb > 50:
        score += w_screenshot_size // 2
        feedback_parts.append(f"~ Screenshot small: {output_size_kb}KB ({w_screenshot_size // 2}/{w_screenshot_size} pts)")
        details['size_valid'] = False
    elif output_size_kb > 0:
        score += 2
        feedback_parts.append(f"✗ Screenshot very small: {output_size_kb}KB (2/{w_screenshot_size} pts)")
        details['size_valid'] = False
    else:
        feedback_parts.append(f"✗ Screenshot empty or missing (0/{w_screenshot_size} pts)")
        details['size_valid'] = False
    
    # ================================================================
    # CRITERION 3: Volume rendering enabled (20 points)
    # ================================================================
    vr_enabled = result.get('vr_enabled', False)
    vr_volume_name = result.get('vr_volume_name', '')
    tf_points = result.get('tf_points', 0)
    slicer_running = result.get('slicer_was_running', False)
    
    if vr_enabled:
        score += w_vr_enabled
        feedback_parts.append(f"✓ Volume rendering enabled on '{vr_volume_name}' ({w_vr_enabled} pts)")
        details['vr_enabled'] = True
        details['vr_volume_name'] = vr_volume_name
        
        # Bonus info about transfer function complexity
        if tf_points > 4:
            details['tf_customized'] = True
        else:
            details['tf_customized'] = False
    elif slicer_running:
        feedback_parts.append(f"✗ Slicer running but volume rendering not enabled (0/{w_vr_enabled} pts)")
        details['vr_enabled'] = False
    else:
        feedback_parts.append(f"✗ Slicer not running (0/{w_vr_enabled} pts)")
        details['vr_enabled'] = False
    
    # ================================================================
    # VLM VERIFICATION (55 points total)
    # Uses trajectory frames, not just final screenshot
    # ================================================================
    vlm_score = 0
    vlm_feedback = []
    
    # Get VLM query function from env_info
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and (output_exists or result.get('screenshot_has_content', '') == 'true'):
        # Try to copy the screenshot for VLM analysis
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        screenshot_available = False
        
        try:
            # Try output screenshot first, then final screenshot
            for screenshot_path in ['/tmp/liver_vr_output.png', '/tmp/liver_vr_final.png']:
                try:
                    copy_from_env(screenshot_path, temp_screenshot.name)
                    if os.path.getsize(temp_screenshot.name) > 10000:  # > 10KB
                        screenshot_available = True
                        break
                except:
                    continue
        except Exception as e:
            logger.warning(f"Could not copy screenshot for VLM: {e}")
        
        if screenshot_available:
            # Also try to get trajectory frames if available
            trajectory_frames = []
            if traj and 'screenshots' in traj:
                # Sample trajectory frames (every 5th frame, up to 5 frames)
                all_frames = traj.get('screenshots', [])
                if len(all_frames) > 5:
                    indices = [i * len(all_frames) // 5 for i in range(5)]
                    trajectory_frames = [all_frames[i] for i in indices if i < len(all_frames)]
                else:
                    trajectory_frames = all_frames
            
            # VLM prompt for liver volume rendering analysis
            vlm_prompt = """Analyze this 3D Slicer screenshot showing volume rendering for liver surgical planning.

Evaluate the following criteria:

1. SOFT_TISSUE_VISIBLE (0-25 points): Is there visible 3D rendered soft tissue (liver)?
   - 25 pts: Clear liver parenchyma visible as semi-transparent brownish/reddish structure
   - 15 pts: Some soft tissue visible but liver not clearly identifiable
   - 5 pts: Very faint or unclear soft tissue rendering
   - 0 pts: No soft tissue visible (only showing bone, air, or 2D slices)

2. VASCULATURE_VISIBLE (0-20 points): Are vascular structures distinguishable?
   - 20 pts: Clear branching tubular structures (portal vein, hepatic veins) visible within/near liver
   - 12 pts: Some tubular structures visible but unclear
   - 5 pts: Possible vessels but very unclear
   - 0 pts: No vascular structures visible

3. APPROPRIATE_TRANSPARENCY (0-10 points): Is the transparency well-configured?
   - 10 pts: Can see internal structures through semi-transparent tissue (good depth)
   - 5 pts: Partial transparency but limited depth perception
   - 0 pts: Completely opaque (solid mass) or completely transparent (nothing)

Additional observations:
- Is this a 3D volume rendering (not just 2D slices)?
- Is there evidence of the Volume Rendering module being used?
- Does the visualization appear clinically useful for surgical planning?

Respond in JSON format:
{
    "soft_tissue_score": <0-25>,
    "soft_tissue_reason": "<brief explanation>",
    "vasculature_score": <0-20>,
    "vasculature_reason": "<brief explanation>",
    "transparency_score": <0-10>,
    "transparency_reason": "<brief explanation>",
    "is_3d_rendering": true/false,
    "volume_rendering_module_used": true/false,
    "clinically_useful": true/false,
    "overall_assessment": "<one sentence summary>"
}"""
            
            try:
                vlm_result = query_vlm(prompt=vlm_prompt, image=temp_screenshot.name)
                
                if vlm_result and vlm_result.get('success'):
                    response_text = vlm_result.get('response', '')
                    
                    # Try to parse JSON from response
                    json_match = re.search(r'\{[^{}]*\}', response_text, re.DOTALL)
                    if json_match:
                        try:
                            vlm_data = json.loads(json_match.group())
                            
                            # Extract scores
                            soft_tissue_pts = min(vlm_data.get('soft_tissue_score', 0), w_soft_tissue)
                            vasculature_pts = min(vlm_data.get('vasculature_score', 0), w_vasculature)
                            transparency_pts = min(vlm_data.get('transparency_score', 0), w_transparency)
                            
                            vlm_score = soft_tissue_pts + vasculature_pts + transparency_pts
                            score += vlm_score
                            
                            vlm_feedback.append("VLM Analysis:")
                            vlm_feedback.append(f"  - Soft tissue: {soft_tissue_pts}/{w_soft_tissue} pts - {vlm_data.get('soft_tissue_reason', 'N/A')}")
                            vlm_feedback.append(f"  - Vasculature: {vasculature_pts}/{w_vasculature} pts - {vlm_data.get('vasculature_reason', 'N/A')}")
                            vlm_feedback.append(f"  - Transparency: {transparency_pts}/{w_transparency} pts - {vlm_data.get('transparency_reason', 'N/A')}")
                            vlm_feedback.append(f"  Assessment: {vlm_data.get('overall_assessment', 'N/A')}")
                            
                            details['vlm_soft_tissue'] = soft_tissue_pts
                            details['vlm_vasculature'] = vasculature_pts
                            details['vlm_transparency'] = transparency_pts
                            details['vlm_is_3d'] = vlm_data.get('is_3d_rendering', False)
                            details['vlm_clinically_useful'] = vlm_data.get('clinically_useful', False)
                            
                        except json.JSONDecodeError:
                            vlm_feedback.append(f"VLM response (could not parse): {response_text[:200]}")
                    else:
                        vlm_feedback.append(f"VLM response (no JSON): {response_text[:200]}")
                else:
                    vlm_feedback.append("VLM query failed or returned no result")
                    
            except Exception as e:
                vlm_feedback.append(f"VLM analysis error: {e}")
        else:
            vlm_feedback.append("No screenshot available for VLM analysis")
        
        # Cleanup
        try:
            os.unlink(temp_screenshot.name)
        except:
            pass
    else:
        # VLM not available - give partial credit based on programmatic checks
        if output_exists and output_size_kb >= min_size_kb:
            # Large screenshot likely has content
            partial_vlm = (w_soft_tissue + w_vasculature + w_transparency) // 2
            score += partial_vlm
            vlm_feedback.append(f"~ VLM unavailable, partial credit for large screenshot ({partial_vlm}/55 pts)")
            details['vlm_unavailable'] = True
        elif output_exists:
            partial_vlm = (w_soft_tissue + w_vasculature + w_transparency) // 4
            score += partial_vlm
            vlm_feedback.append(f"~ VLM unavailable, minimal credit for screenshot ({partial_vlm}/55 pts)")
            details['vlm_unavailable'] = True
        else:
            vlm_feedback.append("VLM unavailable and no screenshot to analyze (0/55 pts)")
            details['vlm_unavailable'] = True
    
    # Add VLM feedback to main feedback
    feedback_parts.extend(vlm_feedback)
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Must have volume rendering enabled as key criterion
    key_criterion_met = vr_enabled
    passed = score >= 70 and key_criterion_met
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nTotal Score: {score}/100"
    feedback += f"\nKey Criterion (VR Enabled): {'Met' if key_criterion_met else 'NOT Met'}"
    feedback += f"\nPassed: {passed}"
    
    details['final_score'] = score
    details['key_criterion_met'] = key_criterion_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }