#!/usr/bin/env python3
"""
Verifier for Batch Audio Balance task

Checks:
1. Output directory exists with audio files
2. Problematic files (segment_b, segment_c) were adjusted
3. Loudness consistency across outputs (std dev ≤ 3 LUFS)
4. Each file in target range [-21, -15] LUFS
5. Original files preserved (unchanged)
6. Audio integrity (no corruption, duration matches)
"""

import sys
import os
import logging
import tempfile
import json
import subprocess
import shutil
from pathlib import Path
from typing import Dict, List, Tuple
import statistics

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import get_audio_info

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def measure_loudness_lufs(filepath: str) -> float:
    """
    Measure integrated LUFS (Loudness Units relative to Full Scale) using ffmpeg.
    
    Args:
        filepath: Path to audio file
        
    Returns:
        Integrated LUFS value, or None if measurement fails
    """
    try:
        # Use ffmpeg with ebur128 filter to measure loudness
        cmd = [
            'ffmpeg',
            '-i', filepath,
            '-af', 'ebur128=framelog=verbose',
            '-f', 'null',
            '-'
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Parse output for integrated loudness
        # Look for line like: "  I:         -18.5 LUFS"
        for line in result.stderr.split('\n'):
            if 'I:' in line and 'LUFS' in line:
                # Extract the number
                parts = line.split()
                for i, part in enumerate(parts):
                    if part == 'I:' and i + 1 < len(parts):
                        try:
                            lufs = float(parts[i + 1])
                            return lufs
                        except ValueError:
                            continue
        
        logger.warning(f"Could not parse LUFS from ffmpeg output for {filepath}")
        return None
        
    except subprocess.TimeoutExpired:
        logger.error(f"ffmpeg timeout while measuring {filepath}")
        return None
    except Exception as e:
        logger.error(f"Error measuring LUFS for {filepath}: {e}")
        return None


def verify_batch_audio_balance(traj, env_info, task_info):
    """
    Verify batch audio balance task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Create temp directory for verification
    temp_dir = tempfile.mkdtemp(prefix='vlc_audio_balance_verify_')
    
    try:
        # Copy export directory from container
        export_dir = os.path.join(temp_dir, 'export')
        os.makedirs(export_dir, exist_ok=True)
        
        # Copy metadata
        metadata_file = os.path.join(temp_dir, 'metadata.json')
        try:
            copy_from_env("/tmp/vlc_audio_balance_metadata.json", metadata_file)
            with open(metadata_file, 'r') as f:
                metadata = json.load(f)
            logger.info(f"Metadata: {metadata}")
        except Exception as e:
            logger.warning(f"Could not load metadata: {e}")
            metadata = {}
        
        # Copy output count
        count_file = os.path.join(temp_dir, 'output_count.txt')
        try:
            copy_from_env("/tmp/vlc_audio_balance_output_count.txt", count_file)
            with open(count_file, 'r') as f:
                output_count = int(f.read().strip())
        except Exception:
            output_count = 0
        
        # Criterion 1: Output directory exists with files
        if output_count > 0:
            criteria_met += 1
            feedback_parts.append(f"✅ Output directory has {output_count} file(s)")
        else:
            feedback_parts.append("❌ No output files found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Copy all output files
        output_files = {}
        for segment in ['segment_a', 'segment_b', 'segment_c', 'segment_d']:
            src_path = f"/tmp/vlc_audio_balance_export/{segment}.mp3"
            dst_path = os.path.join(export_dir, f"{segment}.mp3")
            try:
                copy_from_env(src_path, dst_path)
                if os.path.exists(dst_path) and os.path.getsize(dst_path) > 0:
                    output_files[segment] = dst_path
                    logger.info(f"Copied output file: {segment}.mp3")
            except Exception as e:
                logger.info(f"Output file {segment}.mp3 not found (may be intentional): {e}")
        
        # Criterion 2: Problematic files (segment_b and segment_c) were adjusted
        has_segment_b = 'segment_b' in output_files
        has_segment_c = 'segment_c' in output_files
        
        if has_segment_b and has_segment_c:
            criteria_met += 1
            feedback_parts.append("✅ Both problematic files adjusted (segment_b, segment_c)")
        elif has_segment_b or has_segment_c:
            criteria_met += 0.5
            feedback_parts.append("⚠️ Only one problematic file adjusted")
        else:
            feedback_parts.append("❌ Problematic files not adjusted")
        
        # Measure LUFS for all output files
        lufs_values = {}
        for segment, filepath in output_files.items():
            lufs = measure_loudness_lufs(filepath)
            if lufs is not None:
                lufs_values[segment] = lufs
                logger.info(f"{segment}: {lufs:.1f} LUFS")
        
        if not lufs_values:
            feedback_parts.append("❌ Could not measure loudness (ffmpeg may not be available)")
            # Give partial credit for having output files
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": score >= 50,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 3: Loudness consistency (standard deviation ≤ 3 LUFS)
        if len(lufs_values) >= 2:
            lufs_list = list(lufs_values.values())
            std_dev = statistics.stdev(lufs_list) if len(lufs_list) > 1 else 0
            mean_lufs = statistics.mean(lufs_list)
            
            if std_dev <= 3.0:
                criteria_met += 1
                feedback_parts.append(f"✅ Loudness consistent (σ={std_dev:.2f} LUFS)")
            elif std_dev <= 5.0:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Loudness somewhat consistent (σ={std_dev:.2f} LUFS)")
            else:
                feedback_parts.append(f"❌ Loudness inconsistent (σ={std_dev:.2f} LUFS)")
        else:
            feedback_parts.append("⚠️ Not enough files to check consistency")
        
        # Criterion 4: Each file in target range [-21, -15] LUFS
        in_range_count = 0
        out_of_range = []
        for segment, lufs in lufs_values.items():
            if -21 <= lufs <= -15:
                in_range_count += 1
            else:
                out_of_range.append(f"{segment}({lufs:.1f})")
        
        if in_range_count == len(lufs_values):
            criteria_met += 1
            feedback_parts.append(f"✅ All files in target range [-21, -15] LUFS")
        elif in_range_count >= len(lufs_values) * 0.5:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ {in_range_count}/{len(lufs_values)} files in range")
        else:
            feedback_parts.append(f"❌ Files out of range: {', '.join(out_of_range)}")
        
        # Criterion 5: Original files preserved
        # Check checksums
        originals_dir = os.path.join(export_dir, '../originals')
        orig_checksums_file = os.path.join(temp_dir, 'originals.md5')
        
        try:
            # Copy original checksums
            copy_from_env("/tmp/vlc_audio_balance_export/vlc_audio_balance_originals.md5", 
                         orig_checksums_file)
            
            # Copy original files to verify
            os.makedirs(originals_dir, exist_ok=True)
            for segment in ['segment_a', 'segment_b', 'segment_c', 'segment_d']:
                src = f"/tmp/vlc_audio_balance_export/originals/{segment}.mp3"
                dst = os.path.join(originals_dir, f"{segment}.mp3")
                try:
                    copy_from_env(src, dst)
                except Exception as e:
                    logger.warning(f"Could not copy original {segment}.mp3: {e}")
            
            # Verify checksums match
            result = subprocess.run(
                ['md5sum', '-c', orig_checksums_file],
                cwd=originals_dir,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                criteria_met += 1
                feedback_parts.append("✅ Original files preserved")
            else:
                feedback_parts.append("⚠️ Original files may have been modified")
        except Exception as e:
            logger.warning(f"Could not verify originals: {e}")
            feedback_parts.append("⚠️ Could not verify original files")
        
        # Criterion 6: Audio integrity (duration matches, no corruption)
        integrity_ok = True
        for segment, filepath in output_files.items():
            info = get_audio_info(filepath)
            if 'error' in info:
                integrity_ok = False
                feedback_parts.append(f"❌ {segment} corrupted")
                break
            
            # Check duration is reasonable (should be ~8 seconds)
            duration = info.get('duration', 0)
            if not (7 <= duration <= 9):
                integrity_ok = False
                feedback_parts.append(f"❌ {segment} duration invalid ({duration:.1f}s)")
                break
        
        if integrity_ok and output_files:
            criteria_met += 1
            feedback_parts.append("✅ Audio integrity verified")
        elif not output_files:
            pass  # Already reported no files
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }