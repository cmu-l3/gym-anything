#!/usr/bin/env python3
"""
Verifier for implement_media3_exoplayer task.

Scoring (100 points total):
1. Dependencies Added (20 pts): media3-exoplayer and media3-ui in build.gradle.kts
2. Project Compiles (20 pts): gradle assembleDebug succeeds
3. Layout Configured (15 pts): PlayerView present in activity_main.xml
4. Player Initialization (20 pts): ExoPlayer created and bound to view in MainActivity
5. Resource Loading (10 pts): Correct URI/resource used for video
6. Lifecycle Cleanup (15 pts): release() called in onStop/onDestroy/onPause
"""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_media3_exoplayer(traj, env_info, task_info):
    """Verify that the Media3 ExoPlayer implementation task was completed correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Dependencies Added (20 pts)
    # Checked via export script grep, but double check content here for robustness
    bg_content = result.get('build_gradle_content', '')
    has_exoplayer = 'media3-exoplayer' in bg_content
    has_ui = 'media3-ui' in bg_content
    
    if has_exoplayer and has_ui:
        score += 20
        feedback_parts.append("Dependencies added correctly (20/20)")
    elif has_exoplayer or has_ui:
        score += 10
        feedback_parts.append("Missing one or more Media3 dependencies (10/20)")
    else:
        feedback_parts.append("No Media3 dependencies found (0/20)")

    # 2. Project Compiles (20 pts)
    if result.get('build_success', False):
        score += 20
        feedback_parts.append("Project compiles successfully (20/20)")
    else:
        feedback_parts.append("Project build failed (0/20)")

    # 3. Layout Configured (15 pts)
    layout_content = result.get('layout_content', '')
    if 'androidx.media3.ui.PlayerView' in layout_content:
        score += 15
        feedback_parts.append("PlayerView found in layout (15/15)")
    else:
        feedback_parts.append("PlayerView not found in layout (0/15)")

    # 4. Player Initialization (20 pts)
    ma_content = result.get('main_activity_content', '')
    
    # Check for ExoPlayer.Builder or ExoPlayer.Builder(context).build()
    has_builder = 'ExoPlayer.Builder' in ma_content
    # Check for setting player to view (e.g., binding.playerView.player = player or view.player = player)
    has_binding = re.search(r'\.player\s*=', ma_content) is not None
    # Check for prepare() call
    has_prepare = '.prepare()' in ma_content
    # Check for play() call
    has_play = '.play()' in ma_content or '.playWhenReady' in ma_content
    
    init_score = 0
    if has_builder: init_score += 5
    if has_binding: init_score += 5
    if has_prepare: init_score += 5
    if has_play: init_score += 5
    
    score += init_score
    if init_score == 20:
        feedback_parts.append("Player initialization logic correct (20/20)")
    else:
        feedback_parts.append(f"Partial player initialization ({init_score}/20)")

    # 5. Resource Loading (10 pts)
    # Look for R.raw.promo_video or the URI string
    has_resource = 'R.raw.promo_video' in ma_content
    has_uri = 'android.resource://' in ma_content
    
    if has_resource and has_uri:
        score += 10
        feedback_parts.append("Video resource loaded correctly (10/10)")
    elif has_resource: # Giving points if they used the ID even if URI construction is complex to regex
        score += 10
        feedback_parts.append("Video resource ID usage found (10/10)")
    else:
        feedback_parts.append("Video resource loading not found (0/10)")

    # 6. Lifecycle Cleanup (15 pts)
    # Check for release() call inside onStop, onPause, or onDestroy
    # Simple check: does .release() exist?
    has_release = '.release()' in ma_content
    
    # Check if it's likely inside a lifecycle method
    has_lifecycle_method = 'onStop' in ma_content or 'onDestroy' in ma_content or 'onPause' in ma_content
    
    if has_release and has_lifecycle_method:
        score += 15
        feedback_parts.append("Player release logic found in lifecycle (15/15)")
    elif has_release:
        score += 10
        feedback_parts.append("Player release called but lifecycle method unclear (10/15)")
    else:
        feedback_parts.append("Player release logic missing - potential memory leak (0/15)")

    # Final Score Calculation
    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }