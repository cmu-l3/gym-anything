#!/usr/bin/env python3
"""
Verifier for Record Slice Animation task in 3D Slicer.

VERIFICATION STRATEGY:
Multi-signal verification to prevent gaming:

1. File Exists (20 pts) - GIF file exists at expected path
2. Valid GIF Format (15 pts) - File header matches GIF signature
3. Sufficient Size (15 pts) - File > 200KB indicates real content
4. Multiple Frames (15 pts) - GIF has >20 frames (actual animation)
5. Recent Timestamp (10 pts) - File created during task execution
6. Brain Content Visible (15 pts) - VLM confirms brain MRI in frames
7. Animation Progression (10 pts) - VLM confirms different slices across frames

Pass Threshold: 70 points with File Exists + Valid GIF Format criteria met
"""

import json
import os
import tempfile
import logging
import struct

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_record_slice_animation(traj, env_info, task_info):
    """
    Verify that slice sweep animation was created successfully.
    
    Uses multiple independent signals for robust verification.
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
    expected_output = metadata.get('expected_output_path', 
                                   '/home/ga/Documents/SlicerData/Exports/brain_axial_sweep.gif')
    min_size_kb = metadata.get('min_file_size_kb', 200)
    min_frames = metadata.get('min_frame_count', 20)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('file_exists', 20)
    w_valid_format = weights.get('valid_gif_format', 15)
    w_size = weights.get('sufficient_size', 15)
    w_frames = weights.get('multiple_frames', 15)
    w_timestamp = weights.get('recent_timestamp', 10)
    w_content = weights.get('brain_content_visible', 15)
    w_progression = weights.get('animation_progression', 10)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
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
    
    # ================================================================
    # CRITERION 1: File Exists (20 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += w_file_exists
        feedback_parts.append("GIF file created")
        details['file_exists'] = True
    else:
        feedback_parts.append("GIF file NOT found")
        details['file_exists'] = False
        # Early exit - can't verify anything else without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Valid GIF Format (15 pts)
    # ================================================================
    valid_format = result.get('valid_gif_format', False)
    
    if valid_format:
        score += w_valid_format
        feedback_parts.append("Valid GIF format")
        details['valid_format'] = True
    else:
        feedback_parts.append("Invalid GIF format")
        details['valid_format'] = False
    
    # ================================================================
    # CRITERION 3: Sufficient Size (15 pts)
    # ================================================================
    size_kb = result.get('output_size_kb', 0)
    details['size_kb'] = size_kb
    
    if size_kb >= min_size_kb:
        score += w_size
        feedback_parts.append(f"Good size ({size_kb}KB)")
    elif size_kb >= min_size_kb * 0.5:
        score += int(w_size * 0.5)
        feedback_parts.append(f"Marginal size ({size_kb}KB)")
    else:
        feedback_parts.append(f"File too small ({size_kb}KB)")
    
    # ================================================================
    # CRITERION 4: Multiple Frames (15 pts)
    # ================================================================
    frame_count = result.get('gif_frame_count', 0)
    details['frame_count'] = frame_count
    
    if frame_count >= min_frames:
        score += w_frames
        feedback_parts.append(f"Animation has {frame_count} frames")
    elif frame_count >= min_frames * 0.5:
        score += int(w_frames * 0.5)
        feedback_parts.append(f"Few frames ({frame_count})")
    elif frame_count > 1:
        score += int(w_frames * 0.25)
        feedback_parts.append(f"Minimal frames ({frame_count})")
    else:
        feedback_parts.append("Not animated (single frame)")
    
    # ================================================================
    # CRITERION 5: Recent Timestamp (10 pts) - Anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start_time', 0)
    output_mtime = result.get('output_mtime', 0)
    
    details['task_start'] = task_start
    details['file_mtime'] = output_mtime
    details['created_during_task'] = file_created_during_task
    
    if file_created_during_task:
        score += w_timestamp
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("WARNING: File timestamp suspicious")
    
    # ================================================================
    # CRITERION 6 & 7: VLM Verification (25 pts total)
    # Use trajectory frames AND extracted GIF frames
    # ================================================================
    vlm_score = 0
    vlm_feedback = []
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        # First, try to copy extracted frames from GIF
        gif_frames = []
        frames_dir = "/tmp/gif_frames"
        temp_frames_dir = tempfile.mkdtemp()
        
        try:
            for i in range(4):  # Try to get up to 4 frames
                frame_name = f"frame_{i:02d}.png"
                local_path = os.path.join(temp_frames_dir, frame_name)
                try:
                    copy_from_env(f"{frames_dir}/{frame_name}", local_path)
                    if os.path.exists(local_path) and os.path.getsize(local_path) > 1000:
                        gif_frames.append(local_path)
                except Exception:
                    pass
        except Exception as e:
            logger.warning(f"Could not copy GIF frames: {e}")
        
        # Also get trajectory frames for process verification
        traj_frames = []
        try:
            traj_frames = sample_trajectory_frames(traj, n=5)
        except Exception as e:
            logger.warning(f"Could not get trajectory frames: {e}")
        
        # VLM check on GIF content if we have frames
        if gif_frames and len(gif_frames) >= 2:
            content_prompt = """Analyze these frames extracted from an animated GIF created in 3D Slicer.

The task was to create a slice sweep animation through a brain MRI scan.

For each frame, assess:
1. Is this a medical image (MRI brain scan)?
2. Is it showing an axial (horizontal) cross-section of a brain?
3. Can you see brain anatomy (gray matter, white matter, ventricles)?

Also assess across ALL frames:
4. Do different frames show different anatomical levels (animation progresses)?
5. Is this consistent with a slice sweep through a brain volume?

Respond in JSON:
{
    "is_brain_mri": true/false,
    "is_axial_view": true/false,
    "brain_anatomy_visible": true/false,
    "frames_show_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the frames"
}"""
            
            content_result = query_vlm(prompt=content_prompt, images=gif_frames)
            
            if content_result and content_result.get('success'):
                parsed = content_result.get('parsed', {})
                details['vlm_content_result'] = parsed
                
                # Score brain content (15 pts)
                is_brain = parsed.get('is_brain_mri', False)
                brain_visible = parsed.get('brain_anatomy_visible', False)
                is_axial = parsed.get('is_axial_view', False)
                
                if is_brain and brain_visible:
                    vlm_score += w_content
                    vlm_feedback.append("Brain MRI confirmed")
                elif is_brain or brain_visible:
                    vlm_score += int(w_content * 0.5)
                    vlm_feedback.append("Partial brain content")
                else:
                    vlm_feedback.append("Brain content not confirmed")
                
                # Score animation progression (10 pts)
                shows_progression = parsed.get('frames_show_progression', False)
                confidence = parsed.get('confidence', 'low')
                
                if shows_progression and confidence in ['medium', 'high']:
                    vlm_score += w_progression
                    vlm_feedback.append("Animation progression verified")
                elif shows_progression:
                    vlm_score += int(w_progression * 0.5)
                    vlm_feedback.append("Some progression detected")
                else:
                    vlm_feedback.append("Progression not verified")
            else:
                vlm_feedback.append("VLM content check inconclusive")
        
        # If no GIF frames, try trajectory verification
        elif traj_frames:
            process_prompt = """Analyze these screenshots from a 3D Slicer session.

The task was to use the Screen Capture module to create a slice sweep animation of brain MRI.

Assess:
1. Is 3D Slicer visible with brain MRI data loaded?
2. Is the Screen Capture module visible at any point?
3. Is there evidence of animation capture in progress or completed?
4. Can you see brain anatomy in the slice views?

Respond in JSON:
{
    "slicer_with_brain_data": true/false,
    "screen_capture_visible": true/false,
    "animation_activity": true/false,
    "brain_slices_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you observe"
}"""
            
            process_result = query_vlm(prompt=process_prompt, images=traj_frames)
            
            if process_result and process_result.get('success'):
                parsed = process_result.get('parsed', {})
                details['vlm_process_result'] = parsed
                
                brain_visible = parsed.get('brain_slices_visible', False)
                screen_capture = parsed.get('screen_capture_visible', False)
                
                if brain_visible:
                    vlm_score += int(w_content * 0.5)
                    vlm_feedback.append("Brain data visible in Slicer")
                
                if screen_capture:
                    vlm_score += int(w_progression * 0.5)
                    vlm_feedback.append("Screen Capture module used")
        
        # Clean up temporary frame files
        import shutil
        try:
            shutil.rmtree(temp_frames_dir)
        except Exception:
            pass
        
    except ImportError:
        logger.warning("VLM utilities not available - skipping visual verification")
        vlm_feedback.append("VLM unavailable")
        # Give partial credit based on file characteristics
        if valid_format and frame_count >= min_frames and size_kb >= min_size_kb:
            vlm_score += int((w_content + w_progression) * 0.3)
            vlm_feedback.append("File characteristics suggest valid content")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_feedback.append(f"VLM error: {str(e)[:50]}")
    
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Calculate final result
    # ================================================================
    # Key criteria for passing: file exists AND valid format
    key_criteria_met = output_exists and valid_format
    
    # Pass threshold: 70 points AND key criteria
    passed = (score >= 70) and key_criteria_met
    
    # Adjust pass if very strong signal
    if score >= 85 and output_exists:
        passed = True
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }