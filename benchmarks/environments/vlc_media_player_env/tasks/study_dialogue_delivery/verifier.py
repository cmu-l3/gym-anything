#!/usr/bin/env python3
"""
Verifier for Study Dialogue Delivery task

Verifies:
1. Snapshot directory configuration in VLC config
2. Snapshot format configuration (PNG)
3. Time display enabled (OSD or similar)
4. At least 3 snapshot files created
5. Snapshots are valid images with reasonable size
"""

import sys
import os
import logging
import tempfile
import json
import tarfile
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_vlc_config,
    verify_image_quality,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_study_dialogue_delivery(traj, env_info, task_info):
    """
    Verify study dialogue delivery task completion.
    
    Checks:
    1. VLC config accessible and snapshot settings configured
    2. Snapshot directory set to voice_acting_reference
    3. Snapshot format set to PNG
    4. Time display enabled
    5. At least 3 snapshot files created
    6. Snapshots are valid images
    
    Scoring:
    - Snapshot config (directory + format): 2 points
    - Time display config: 1 point
    - Snapshots created (3+): 2 points
    - Snapshots valid: 1 point
    Total: 6 points (converted to 0-100 scale)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0.0
    max_criteria = 6.0
    feedback_parts = []
    temp_dir = tempfile.mkdtemp(prefix='vlc_dialogue_verify_')
    
    try:
        # ============================================================
        # 1. Load and parse VLC configuration
        # ============================================================
        config_path_host = Path(temp_dir) / "vlcrc"
        
        try:
            copy_from_env("/tmp/vlc_dialogue_config.txt", str(config_path_host))
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access VLC configuration: {str(e)}"
            }
        
        if not config_path_host.exists() or config_path_host.stat().st_size == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file not found or empty"
            }
        
        config = parse_vlc_config(str(config_path_host))
        
        # ============================================================
        # 2. Check snapshot directory configuration
        # ============================================================
        snapshot_dir = config.get('snapshot-path', '')
        
        if 'voice_acting_reference' in snapshot_dir or snapshot_dir.endswith('voice_acting_reference'):
            criteria_met += 1.0
            feedback_parts.append(f"✅ Snapshot directory configured: {snapshot_dir}")
        else:
            feedback_parts.append(f"⚠️ Snapshot directory not set correctly (found: '{snapshot_dir}')")
        
        # ============================================================
        # 3. Check snapshot format configuration
        # ============================================================
        snapshot_format = config.get('snapshot-format', '')
        
        if snapshot_format.lower() == 'png':
            criteria_met += 1.0
            feedback_parts.append("✅ Snapshot format: PNG")
        else:
            feedback_parts.append(f"⚠️ Snapshot format not PNG (found: '{snapshot_format}')")
        
        # ============================================================
        # 4. Check time display configuration
        # ============================================================
        osd_enabled = config.get('osd', '1') == '1'
        video_title_show = config.get('video-title-show', '1') == '1'
        time_display = config.get('video-title-show', '1') == '1'
        
        if osd_enabled or video_title_show or time_display:
            criteria_met += 1.0
            feedback_parts.append("✅ Time display enabled")
        else:
            # Partial credit - might be visible in interface even without OSD
            criteria_met += 0.5
            feedback_parts.append("⚠️ Time display configuration not found (may still be visible)")
        
        # ============================================================
        # 5. Check snapshot files created
        # ============================================================
        result_json_path = Path(temp_dir) / "result.json"
        
        try:
            copy_from_env("/tmp/vlc_dialogue_result.json", str(result_json_path))
            
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
            
            snapshot_count = result_data.get('snapshot_count', 0)
            
            if snapshot_count >= 3:
                criteria_met += 2.0
                feedback_parts.append(f"✅ {snapshot_count} snapshots created (required: 3+)")
            elif snapshot_count > 0:
                criteria_met += 1.0
                feedback_parts.append(f"⚠️ Only {snapshot_count} snapshot(s) created (required: 3+)")
            else:
                feedback_parts.append("❌ No snapshots created")
        
        except Exception as e:
            logger.error(f"Error reading result JSON: {e}")
            feedback_parts.append("❌ Could not verify snapshot count")
        
        # ============================================================
        # 6. Verify snapshot validity (extract and check images)
        # ============================================================
        snapshots_tar_path = Path(temp_dir) / "snapshots.tar.gz"
        
        try:
            copy_from_env("/tmp/vlc_dialogue_snapshots.tar.gz", str(snapshots_tar_path))
            
            # Extract snapshots
            snapshots_extract_dir = Path(temp_dir) / "snapshots"
            snapshots_extract_dir.mkdir(exist_ok=True)
            
            with tarfile.open(snapshots_tar_path, 'r:gz') as tar:
                tar.extractall(snapshots_extract_dir)
            
            # Verify each snapshot
            valid_snapshots = 0
            snapshot_files = list(snapshots_extract_dir.glob('*.png'))
            
            for snapshot_file in snapshot_files:
                if verify_image_quality(str(snapshot_file), min_size_kb=10):
                    valid_snapshots += 1
            
            if valid_snapshots >= 3:
                criteria_met += 1.0
                feedback_parts.append(f"✅ {valid_snapshots} valid snapshots verified")
            elif valid_snapshots > 0:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Only {valid_snapshots} valid snapshot(s)")
            else:
                feedback_parts.append("❌ No valid snapshots found")
        
        except Exception as e:
            logger.warning(f"Could not verify snapshot validity: {e}")
            feedback_parts.append("⚠️ Could not verify snapshot image quality")
        
        # ============================================================
        # Calculate final score
        # ============================================================
        score = int((criteria_met / max_criteria) * 100)
        passed = score >= 75
        
        if passed:
            feedback_parts.insert(0, "✅ Voice acting study setup verified successfully!")
        else:
            feedback_parts.insert(0, f"❌ Setup incomplete (score: {score}/100)")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        cleanup_verification_environment(temp_dir)