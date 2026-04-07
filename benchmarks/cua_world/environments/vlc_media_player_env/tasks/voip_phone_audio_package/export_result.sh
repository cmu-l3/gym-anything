#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will use an inline Python script to robustly extract metadata and verify the audio beep
# This avoids relying on external audio tools being available in the host verifier environment
cat > /tmp/extract_audio_stats.py << 'EOF'
import os
import json
import subprocess
import wave
import math

def get_audio_info(filepath):
    if not os.path.exists(filepath):
        return {'exists': False}
    
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-show_entries', 'stream=codec_name,channels,sample_rate,bit_rate',
            '-show_entries', 'format=duration,size,bit_rate',
            '-of', 'json', filepath
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        data = json.loads(res.stdout)
        
        stream = data.get('streams', [{}])[0]
        fmt = data.get('format', {})
        
        return {
            'exists': True,
            'size': int(fmt.get('size', 0)),
            'mtime': os.path.getmtime(filepath),
            'codec': stream.get('codec_name', ''),
            'channels': int(stream.get('channels', 0)),
            'sample_rate': int(stream.get('sample_rate', 0)),
            'bitrate': int(stream.get('bit_rate') or fmt.get('bit_rate') or 0),
            'duration': float(fmt.get('duration', 0))
        }
    except Exception as e:
        return {'exists': True, 'error': str(e)}

def verify_beep_and_silence(filepath):
    """Verifies the presence of a beep followed by silence in an 8kHz mono WAV file."""
    if not os.path.exists(filepath):
        return False
        
    try:
        with wave.open(filepath, 'rb') as w:
            rate = w.getframerate()
            frames = w.getnframes()
            dur = frames / float(rate)
            
            # Voicemail should be ~8.5s. If it's completely wrong, fail early.
            if dur < 6.0 or dur > 11.0:
                return False
                
            # Check for silence in the last 2.5 seconds
            w.setpos(int(max(0, dur - 2.5) * rate))
            silence_data = w.readframes(int(2.0 * rate))
            
            import struct
            # Assuming 16-bit PCM (2 bytes per sample)
            silence_samples = struct.unpack(f"<{len(silence_data)//2}h", silence_data)
            rms_silence = math.sqrt(sum(s*s for s in silence_samples) / max(1, len(silence_samples)))
            
            # Check for beep around dur - 3.4s to dur - 3.1s
            w.setpos(int(max(0, dur - 3.4) * rate))
            beep_data = w.readframes(int(0.3 * rate))
            beep_samples = struct.unpack(f"<{len(beep_data)//2}h", beep_data)
            rms_beep = math.sqrt(sum(s*s for s in beep_samples) / max(1, len(beep_samples)))
            
            # Beep must have high energy, silence must have very low energy
            return (rms_beep > 1000) and (rms_silence < 100)
    except Exception:
        return False

# Main execution
results = {
    'task_start': float(os.environ.get('TASK_START', 0)),
    'task_end': float(os.environ.get('TASK_END', 0)),
    'files': {},
    'manifest_data': None,
    'voicemail_beep_verified': False
}

base_dir = '/home/ga/Music/phone_system'
expected_files = [
    'main_greeting.wav',
    'ivr_full_menu.wav',
    'hold_music.wav',
    'voicemail.wav',
    'ivr_full_menu.mp3'
]

for f in expected_files:
    results['files'][f] = get_audio_info(os.path.join(base_dir, f))

# Specific custom verification for the beep logic
results['voicemail_beep_verified'] = verify_beep_and_silence(os.path.join(base_dir, 'voicemail.wav'))

# Read the manifest JSON if it exists
manifest_path = os.path.join(base_dir, 'manifest.json')
if os.path.exists(manifest_path):
    try:
        with open(manifest_path, 'r') as mf:
            results['manifest_data'] = json.load(mf)
    except Exception:
        results['manifest_data'] = 'invalid_json'

with open('/tmp/task_result.json', 'w') as out:
    json.dump(results, out)

EOF

export TASK_START
export TASK_END
python3 /tmp/extract_audio_stats.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="