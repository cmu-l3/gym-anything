#!/usr/bin/env python3
"""
Verifier for Create Chapter Markers task

Checks:
1. Output video file exists
2. Video properties preserved (duration, resolution)
3. Chapters exist in metadata
4. Correct number of chapters (3)
5. Chapter timestamps approximately correct
6. Chapter titles present
"""

import json
import logging
import os
import sys
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_chapter_markers(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that chapter markers were correctly created.
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration (unused)
        
    Returns:
        Dict with success status, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available"
        }
    
    feedback = []
    score = 0.0
    max_score = 100.0
    
    # Import tempfile here to avoid issues
    import tempfile
    import shutil
    
    # Create temporary directory for verification
    temp_dir = tempfile.mkdtemp(prefix='vlc_chapters_verify_')
    
    try:
        # Check 1: Output file exists (20 points)
        output_path = Path(temp_dir) / "lecture_with_chapters.mp4"
        
        try:
            copy_from_env("/tmp/task_export/lecture_with_chapters.mp4", str(output_path))
        except Exception as e:
            logger.error(f"Failed to copy output video: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Output file 'lecture_with_chapters.mp4' not found: {e}"
            }
        
        if not output_path.exists() or output_path.stat().st_size < 1000:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Output file not found or too small"
            }
        
        score += 20
        feedback.append(f"✅ Output file exists ({output_path.stat().st_size / 1024:.1f} KB)")
        
        # Check 2: Video properties preserved (20 points)
        source_props_path = Path(temp_dir) / "source_properties.json"
        output_props_path = Path(temp_dir) / "video_properties.json"
        
        try:
            copy_from_env("/tmp/task_export/source_properties.json", str(source_props_path))
            copy_from_env("/tmp/task_export/video_properties.json", str(output_props_path))
            
            with open(source_props_path) as f:
                source_props = json.load(f)
            with open(output_props_path) as f:
                output_props = json.load(f)
            
            # Check duration preserved (within 2%)
            source_duration = float(source_props.get('format', {}).get('duration', 0))
            output_duration = float(output_props.get('format', {}).get('duration', 0))
            
            if source_duration > 0:
                duration_diff_pct = abs(output_duration - source_duration) / source_duration * 100
                
                if duration_diff_pct <= 2.0:
                    score += 10
                    feedback.append(f"✅ Duration preserved ({output_duration:.1f}s vs {source_duration:.1f}s, {duration_diff_pct:.2f}% diff)")
                else:
                    feedback.append(f"⚠️ Duration changed significantly ({duration_diff_pct:.1f}% difference)")
            else:
                feedback.append("⚠️ Could not verify duration")
            
            # Check resolution preserved
            source_streams = source_props.get('streams', [])
            output_streams = output_props.get('streams', [])
            
            if source_streams and output_streams:
                source_stream = source_streams[0]
                output_stream = output_streams[0]
                
                if (source_stream.get('width') == output_stream.get('width') and 
                    source_stream.get('height') == output_stream.get('height')):
                    score += 10
                    feedback.append(f"✅ Resolution preserved ({output_stream.get('width')}x{output_stream.get('height')})")
                else:
                    feedback.append(f"⚠️ Resolution changed")
            else:
                feedback.append("⚠️ Could not verify resolution")
        
        except Exception as e:
            logger.warning(f"Could not compare video properties: {e}")
            feedback.append(f"⚠️ Could not verify video properties: {e}")
        
        # Check 3: Chapters exist (30 points)
        chapters_path = Path(temp_dir) / "chapters_metadata.json"
        
        try:
            copy_from_env("/tmp/task_export/chapters_metadata.json", str(chapters_path))
        except Exception as e:
            logger.error(f"Failed to copy chapter metadata: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback) + f" | ❌ Chapter metadata not found: {e}"
            }
        
        try:
            with open(chapters_path) as f:
                chapters_data = json.load(f)
            
            chapters = chapters_data.get('chapters', [])
            
            if len(chapters) == 0:
                feedback.append("❌ No chapters found in output video")
                shutil.rmtree(temp_dir, ignore_errors=True)
                return {
                    "passed": False,
                    "score": score,
                    "feedback": " | ".join(feedback)
                }
            
            score += 15
            feedback.append(f"✅ Found {len(chapters)} chapter(s)")
            
            # Verify exactly 3 chapters
            if len(chapters) == 3:
                score += 15
                feedback.append("✅ Correct number of chapters (3)")
            elif len(chapters) > 3:
                score += 10
                feedback.append(f"⚠️ More chapters than expected (found {len(chapters)}, expected 3)")
            else:
                score += 5
                feedback.append(f"⚠️ Fewer chapters than expected (found {len(chapters)}, expected 3)")
        
        except Exception as e:
            logger.error(f"Error parsing chapters: {e}")
            feedback.append(f"❌ Error parsing chapter data: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback)
            }
        
        # Check 4: Chapter timestamps (20 points)
        # Expected times for 3-minute video (scaled from 45-minute):
        # Chapter 1: 0-5s
        # Chapter 2: 50-60s (around 54s)
        # Chapter 3: 100-120s (around 108s)
        expected_times = [
            (0, 5, "Chapter 1 (Introduction)"),
            (50, 60, "Chapter 2 (Neural Networks)"),
            (100, 120, "Chapter 3 (Coding Examples)")
        ]
        
        timestamp_points = 20.0 / len(expected_times)
        
        for i, chapter in enumerate(chapters[:3]):  # Check first 3 chapters
            start_time = float(chapter.get('start_time', -1))
            
            if i < len(expected_times):
                min_time, max_time, desc = expected_times[i]
                
                if min_time <= start_time <= max_time:
                    score += timestamp_points
                    feedback.append(f"✅ {desc} at correct time ({start_time:.1f}s)")
                else:
                    # Partial credit if at least in reasonable range
                    if abs(start_time - (min_time + max_time) / 2) < 30:
                        score += timestamp_points * 0.5
                        feedback.append(f"⚠️ {desc} at acceptable time ({start_time:.1f}s, expected {min_time}-{max_time}s)")
                    else:
                        feedback.append(f"❌ {desc} at wrong time ({start_time:.1f}s, expected {min_time}-{max_time}s)")
        
        # Check 5: Chapter titles present (10 points)
        title_points = 10.0 / max(len(chapters), 1)
        chapters_with_titles = 0
        
        for i, chapter in enumerate(chapters):
            # Try different tag locations
            title = ""
            tags = chapter.get('tags', {})
            
            if isinstance(tags, dict):
                title = tags.get('title', '').strip()
            
            # Some ffprobe versions put title directly in chapter
            if not title:
                title = chapter.get('title', '').strip()
            
            if title:
                chapters_with_titles += 1
                score += title_points
                logger.info(f"Chapter {i+1}: '{title}' at {chapter.get('start_time', 0):.1f}s")
        
        if chapters_with_titles == len(chapters):
            feedback.append(f"✅ All {len(chapters)} chapters have titles")
        elif chapters_with_titles > 0:
            feedback.append(f"⚠️ {chapters_with_titles}/{len(chapters)} chapters have titles")
        else:
            feedback.append(f"❌ No chapters have titles")
        
        # Clean up
        shutil.rmtree(temp_dir, ignore_errors=True)
        
        # Final assessment
        success = score >= 70.0  # Need 70% to pass
        
        feedback.append(f"📊 Final Score: {score:.1f}/{max_score}")
        
        return {
            "passed": success,
            "score": score / max_score,
            "feedback": " | ".join(feedback),
            "metadata": {
                "chapters_found": len(chapters),
                "chapters_expected": 3,
                "chapters_with_titles": chapters_with_titles,
                "output_file_size_kb": output_path.stat().st_size / 1024 if output_path.exists() else 0
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification failed: {str(e)}"
        }
