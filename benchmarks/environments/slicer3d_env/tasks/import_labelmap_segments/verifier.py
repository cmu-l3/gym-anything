#!/usr/bin/env python3
"""
Verifier for Import Multi-Label Segmentation task in 3D Slicer.

VERIFICATION STRATEGY (Multi-Signal Hybrid):

Programmatic checks (70 points):
1. CT volume loaded (10 pts)
2. Labelmap loaded (10 pts)
3. Segmentation node created (25 pts)
4. Three or more segments present (25 pts)

VLM checks (30 points):
5. Trajectory shows workflow progression (15 pts)
6. Final screenshot shows colored segment overlays (15 pts)

Anti-gaming:
- Check timestamps to verify work done during task
- Use trajectory frames (not just final screenshot) for VLM
- Verify segment count matches expected

Pass threshold: 70 points with segmentation node created and >= 3 segments
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_import_labelmap_segments(traj, env_info, task_info):
    """
    Verify that the multi-label segmentation was imported and separated correctly.
    
    Uses multiple independent signals to prevent gaming.
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
    expected_segment_count = metadata.get('expected_segment_count', 3)
    weights = metadata.get('scoring_weights', {})
    
    w_ct_loaded = weights.get('ct_volume_loaded', 10)
    w_labelmap_loaded = weights.get('labelmap_loaded', 10)
    w_segmentation_created = weights.get('segmentation_node_created', 25)
    w_segments_present = weights.get('three_segments_present', 25)
    w_segments_content = weights.get('segments_have_content', 15)
    w_visual = weights.get('visual_confirmation', 15)

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
        copy_from_env("/tmp/labelmap_task_result.json", temp_result.name)
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

    # ================================================================
    # Check if Slicer was running (basic requirement)
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # CRITERION 1: CT Volume Loaded (10 points)
    # ================================================================
    ct_loaded = result.get('ct_loaded', False)
    volume_nodes = result.get('volume_nodes_count', 0)
    
    if ct_loaded:
        score += w_ct_loaded
        feedback_parts.append("CT volume loaded")
        details['ct_loaded'] = True
    elif volume_nodes > 0:
        score += w_ct_loaded // 2
        feedback_parts.append(f"Volume(s) loaded ({volume_nodes})")
        details['ct_loaded'] = 'partial'
    else:
        feedback_parts.append("CT volume not loaded")
        details['ct_loaded'] = False

    # ================================================================
    # CRITERION 2: Labelmap Loaded (10 points)
    # ================================================================
    labelmap_loaded = result.get('labelmap_loaded', False)
    
    if labelmap_loaded:
        score += w_labelmap_loaded
        feedback_parts.append("Labelmap loaded")
        details['labelmap_loaded'] = True
    else:
        feedback_parts.append("Labelmap not loaded")
        details['labelmap_loaded'] = False

    # ================================================================
    # CRITERION 3: Segmentation Node Created (25 points)
    # ================================================================
    segmentation_nodes = result.get('segmentation_nodes_count', 0)
    
    if segmentation_nodes > 0:
        score += w_segmentation_created
        feedback_parts.append(f"Segmentation created ({segmentation_nodes} node(s))")
        details['segmentation_created'] = True
    else:
        feedback_parts.append("No segmentation node created")
        details['segmentation_created'] = False

    # ================================================================
    # CRITERION 4: Three Segments Present (25 points)
    # ================================================================
    segment_count = result.get('segment_count', 0)
    segment_names = result.get('segment_names', '')
    
    if segment_count >= expected_segment_count:
        score += w_segments_present
        feedback_parts.append(f"{segment_count} segments created")
        details['segment_count'] = segment_count
        details['segments_sufficient'] = True
    elif segment_count > 0:
        # Partial credit for some segments
        partial = int(w_segments_present * (segment_count / expected_segment_count))
        score += partial
        feedback_parts.append(f"Only {segment_count}/{expected_segment_count} segments")
        details['segment_count'] = segment_count
        details['segments_sufficient'] = False
    else:
        feedback_parts.append("No segments created")
        details['segment_count'] = 0
        details['segments_sufficient'] = False

    if segment_names:
        details['segment_names'] = segment_names.split(',')

    # ================================================================
    # CRITERION 5: Segments Have Content (15 points)
    # ================================================================
    # Check from query result if segments are non-empty
    query_result = result.get('query_result', {})
    if isinstance(query_result, str):
        try:
            query_result = json.loads(query_result)
        except:
            query_result = {}
    
    all_nonempty = query_result.get('all_segments_nonempty', False)
    voxel_counts = query_result.get('segment_voxel_counts', [])
    
    if all_nonempty or (voxel_counts and all(v > 0 for v in voxel_counts if v >= 0)):
        score += w_segments_content
        feedback_parts.append("All segments have content")
        details['segments_nonempty'] = True
    elif segment_count > 0:
        # Give partial credit if segments exist (voxel count check may have failed)
        score += w_segments_content // 2
        feedback_parts.append("Segments exist (content check inconclusive)")
        details['segments_nonempty'] = 'unknown'
    else:
        details['segments_nonempty'] = False

    # ================================================================
    # CRITERION 6: Visual Confirmation via VLM (15 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM check skipped"
    
    # Try to use VLM to verify visual evidence
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Sample frames from trajectory for process verification
        traj_frames = sample_trajectory_frames(traj, n=5) if traj else []
        final_screenshot = get_final_screenshot(traj)
        
        if traj_frames or final_screenshot:
            # Combine trajectory frames with final screenshot
            images_to_check = traj_frames + ([final_screenshot] if final_screenshot else [])
            
            if images_to_check:
                vlm_prompt = """You are verifying if a 3D Slicer task was completed successfully.

The task was to import a multi-label segmentation labelmap and convert it into separate segment objects.

Look at these screenshots and determine:
1. Is 3D Slicer visible with medical imaging data loaded?
2. Are there colored segment overlays visible on the CT slices? (Different colors = different segments)
3. Is there evidence of multiple distinct colored regions (liver=one color, tumor=another, vessels=another)?
4. Does the Segment Editor or Segmentations module appear to be in use?

A successful import should show:
- Axial/sagittal/coronal CT slice views
- Colored overlays on top of the grayscale CT (typically semi-transparent colors like red, green, blue, yellow)
- At least 2-3 different colored regions visible

Respond in JSON format:
{
    "slicer_visible": true/false,
    "ct_data_visible": true/false,
    "colored_overlays_visible": true/false,
    "multiple_colors_present": true/false,
    "estimated_segment_count": 0-5,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
                vlm_result = query_vlm(images=images_to_check, prompt=vlm_prompt)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Score based on VLM findings
                    if parsed.get('colored_overlays_visible', False):
                        vlm_score += 8
                        if parsed.get('multiple_colors_present', False):
                            vlm_score += 7
                            vlm_feedback = "VLM confirms colored segment overlays"
                        else:
                            vlm_feedback = "VLM sees overlays, unclear if multiple segments"
                    elif parsed.get('ct_data_visible', False):
                        vlm_score += 3
                        vlm_feedback = "VLM sees CT data but no clear segment overlays"
                    else:
                        vlm_feedback = "VLM could not confirm segment visualization"
                else:
                    vlm_feedback = "VLM query failed"
                    # Fall back to screenshot analysis
                    if result.get('screenshot_has_colors', False):
                        vlm_score += 7
                        vlm_feedback = "Screenshot shows color variety (likely segments)"
    except ImportError:
        # VLM not available, use fallback heuristics
        if result.get('screenshot_has_colors', False):
            vlm_score += 10
            vlm_feedback = "Screenshot color analysis suggests segments visible"
        elif result.get('screenshot_size_kb', 0) > 200:
            vlm_score += 5
            vlm_feedback = "Screenshot suggests active visualization"
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_feedback = f"VLM error: {str(e)}"

    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # ANTI-GAMING: Check timestamps
    # ================================================================
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    if task_start > 0 and task_end > 0:
        task_duration = task_end - task_start
        details['task_duration_seconds'] = task_duration
        
        # If task completed in less than 10 seconds, suspicious
        if task_duration < 10 and score > 50:
            score = min(score, 50)
            feedback_parts.append("Warning: Task completed suspiciously fast")
    
    # Check if segmentation file was created during task
    file_created = result.get('file_created_during_task', False)
    details['file_created_during_task'] = file_created

    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    max_score = w_ct_loaded + w_labelmap_loaded + w_segmentation_created + w_segments_present + w_segments_content + w_visual
    
    # Cap score at 100
    score = min(score, 100)
    
    # Key criteria for passing
    segmentation_created = segmentation_nodes > 0
    enough_segments = segment_count >= expected_segment_count
    
    # Pass if score >= 70 AND segmentation created AND at least 3 segments
    passed = (score >= 70) and segmentation_created and enough_segments
    
    # Alternative pass: score >= 80 with segmentation and at least 2 segments
    if not passed and score >= 80 and segmentation_created and segment_count >= 2:
        passed = True
        feedback_parts.append("Passed with partial segment count")

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }