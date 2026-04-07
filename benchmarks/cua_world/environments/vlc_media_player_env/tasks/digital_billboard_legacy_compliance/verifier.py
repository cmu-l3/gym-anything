#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _probe_media(filepath):
    """Uses ffprobe to extract comprehensive information about the video and audio streams."""
    info = {
        'video_codec': None,
        'width': 0,
        'height': 0,
        'fps': 0.0,
        'audio_streams': 0,
        'error': None
    }
    
    if not os.path.exists(filepath):
        info['error'] = 'File not found'
        return info

    try:
        # Probe all streams
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'stream=codec_type,codec_name,width,height,r_frame_rate',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        if res.returncode == 0:
            data = json.loads(res.stdout)
            streams = data.get('streams', [])
            
            for s in streams:
                if s.get('codec_type') == 'video' and not info['video_codec']:
                    info['video_codec'] = s.get('codec_name', '').lower()
                    info['width'] = int(s.get('width', 0))
                    info['height'] = int(s.get('height', 0))
                    
                    fps_str = s.get('r_frame_rate', '0/1')
                    if '/' in fps_str:
                        num, den = map(int, fps_str.split('/'))
                        info['fps'] = num / den if den > 0 else 0
                    else:
                        info['fps'] = float(fps_str)
                elif s.get('codec_type') == 'audio':
                    info['audio_streams'] += 1
        else:
            info['error'] = res.stderr
    except Exception as e:
        info['error'] = str(e)
        
    return info

def verify_digital_billboard_legacy_compliance(traj, env_info, task_info):
    """
    Verify the DOOH legacy compliance task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification framework failure (copy_from_env missing)."}

    feedback = []
    score = 0.0
    
    # Create a local temp directory for exported files
    temp_dir = tempfile.mkdtemp(prefix='dooh_verify_')
    
    try:
        # We copy the entire export directory which includes metadata and deliverables
        try:
            # We copy the individual files directly from /tmp/dooh_export/
            export_files = [
                'file_metadata.json',
                'highway_board.avi',
                'subway_screen.mpg',
                'stadium_ribbon.mp4',
                'proofs/highway_proof.png',
                'proofs/subway_proof.png',
                'proofs/stadium_proof.png',
                'dooh_manifest.json',
                'client_master_promo.mp4'
            ]
            
            # Since proofs is a subdirectory, create it locally
            os.makedirs(os.path.join(temp_dir, 'proofs'), exist_ok=True)
            
            for f in export_files:
                local_path = os.path.join(temp_dir, f)
                try:
                    copy_from_env(f"/tmp/dooh_export/{f}", local_path)
                except Exception as e:
                    # It's fine if some don't copy, we will penalize missing files later
                    logger.warning(f"Failed to copy {f}: {e}")
                    pass
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve files: {e}"}

        # 1. Load Anti-gaming Metadata
        metadata_path = os.path.join(temp_dir, 'file_metadata.json')
        if not os.path.exists(metadata_path):
            return {"passed": False, "score": 0, "feedback": "Anti-gaming metadata missing."}
            
        with open(metadata_path, 'r') as f:
            file_meta = json.loads(f.read())
            
        files_meta = file_meta.get('files', {})

        # Track audio stripping success for the GATE
        successfully_stripped = 0

        # --- CRITERION 1: Highway Board (20 points) ---
        hw_meta = files_meta.get('highway_board', {})
        if hw_meta.get('exists') and hw_meta.get('created_during_task'):
            hw_info = _probe_media(os.path.join(temp_dir, 'highway_board.avi'))
            
            pts = 0
            if hw_info['video_codec'] in ['mpeg4', 'msmpeg4', 'msmpeg4v2', 'msmpeg4v3', 'xvid']:
                pts += 5
            if hw_info['width'] == 800 and hw_info['height'] == 400:
                pts += 5
            if abs(hw_info['fps'] - 15.0) <= 1.0:
                pts += 5
            if hw_info['audio_streams'] == 0:
                pts += 5
                successfully_stripped += 1
                
            score += pts
            feedback.append(f"Highway Board: {pts}/20 pts (Codec: {hw_info['video_codec']}, Res: {hw_info['width']}x{hw_info['height']}, FPS: {hw_info['fps']:.1f}, Audio Streams: {hw_info['audio_streams']})")
        else:
            feedback.append("Highway Board: 0/20 pts (Missing or not created during task)")

        # --- CRITERION 2: Subway Screen (20 points) ---
        sw_meta = files_meta.get('subway_screen', {})
        if sw_meta.get('exists') and sw_meta.get('created_during_task'):
            sw_info = _probe_media(os.path.join(temp_dir, 'subway_screen.mpg'))
            
            pts = 0
            if sw_info['video_codec'] in ['mpeg2video', 'mpeg1video']:
                pts += 5
            if sw_info['width'] == 1024 and sw_info['height'] == 768:
                pts += 10
            if sw_info['audio_streams'] == 0:
                pts += 5
                successfully_stripped += 1
                
            score += pts
            feedback.append(f"Subway Screen: {pts}/20 pts (Codec: {sw_info['video_codec']}, Res: {sw_info['width']}x{sw_info['height']}, Audio Streams: {sw_info['audio_streams']})")
        else:
            feedback.append("Subway Screen: 0/20 pts (Missing or not created during task)")

        # --- CRITERION 3: Stadium Ribbon (20 points) ---
        st_meta = files_meta.get('stadium_ribbon', {})
        if st_meta.get('exists') and st_meta.get('created_during_task'):
            st_info = _probe_media(os.path.join(temp_dir, 'stadium_ribbon.mp4'))
            
            pts = 0
            if st_info['video_codec'] == 'h264':
                pts += 5
            if st_info['width'] == 1920 and st_info['height'] == 200:
                pts += 5
            if abs(st_info['fps'] - 30.0) <= 1.0:
                pts += 5
            if st_info['audio_streams'] == 0:
                pts += 5
                successfully_stripped += 1
                
            score += pts
            feedback.append(f"Stadium Ribbon: {pts}/20 pts (Codec: {st_info['video_codec']}, Res: {st_info['width']}x{st_info['height']}, FPS: {st_info['fps']:.1f}, Audio Streams: {st_info['audio_streams']})")
        else:
            feedback.append("Stadium Ribbon: 0/20 pts (Missing or not created during task)")

        # --- CRITERION 4: Proof Snapshots (15 points) ---
        proof_pts = 0
        p1 = files_meta.get('highway_proof', {})
        p2 = files_meta.get('subway_proof', {})
        p3 = files_meta.get('stadium_proof', {})
        
        if p1.get('exists') and p1.get('size_bytes', 0) > 5000 and p1.get('created_during_task'): proof_pts += 5
        if p2.get('exists') and p2.get('size_bytes', 0) > 5000 and p2.get('created_during_task'): proof_pts += 5
        if p3.get('exists') and p3.get('size_bytes', 0) > 5000 and p3.get('created_during_task'): proof_pts += 5
        
        score += proof_pts
        feedback.append(f"Snapshots: {proof_pts}/15 pts")

        # --- CRITERION 5: JSON Manifest (15 points) ---
        manifest_meta = files_meta.get('manifest', {})
        manifest_pts = 0
        if manifest_meta.get('exists') and manifest_meta.get('created_during_task'):
            try:
                with open(os.path.join(temp_dir, 'dooh_manifest.json'), 'r') as mf:
                    manifest = json.load(mf)
                
                if manifest.get('campaign') == 'DOOH-Q3-PROMO':
                    manifest_pts += 5
                
                deliverables = manifest.get('deliverables', [])
                if isinstance(deliverables, list) and len(deliverables) >= 3:
                    manifest_pts += 5
                    
                    # Check if has_audio is properly documented as False
                    audio_correct = True
                    for d in deliverables:
                        if d.get('has_audio', True) is not False:
                            audio_correct = False
                            
                    if audio_correct:
                        manifest_pts += 5
                        
            except Exception as e:
                feedback.append(f"Manifest parsing error: {str(e)}")
        
        score += manifest_pts
        feedback.append(f"JSON Manifest: {manifest_pts}/15 pts")

        # --- CRITERION 6: Source Preservation (10 points) ---
        master_meta = files_meta.get('master_promo', {})
        master_info = _probe_media(os.path.join(temp_dir, 'client_master_promo.mp4'))
        
        source_pts = 0
        if master_meta.get('exists') and master_info['width'] == 1920 and master_info['audio_streams'] > 0:
            source_pts = 10
            
        score += source_pts
        feedback.append(f"Source Preservation: {source_pts}/10 pts")

        # --- GATE CHECK ---
        passed = False
        if score >= 75.0 and successfully_stripped >= 2:
            passed = True
        elif score >= 75.0:
            feedback.append("FAILED GATE: Failed to strip audio from at least two deliverable files (CRITICAL REQUIREMENT).")

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)