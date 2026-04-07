#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair DSP Audio Effects Library Task ==="

WORKSPACE_DIR="/home/ga/workspace/audio_dsp"
sudo -u ga mkdir -p "$WORKSPACE_DIR/dsp/effects"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate realistic 48kHz WAV file (Plucked string synth)
# ─────────────────────────────────────────────────────────────
echo "Generating test audio file..."
python3 << 'PYWAV'
import wave
import struct
import math

sample_rate = 48000
duration = 2.0
num_samples = int(sample_rate * duration)

with wave.open("/home/ga/workspace/audio_dsp/data/raw_guitar.wav", 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    
    for i in range(num_samples):
        t = float(i) / sample_rate
        # Basic Karplus-Strong-like decay envelope
        envelope = math.exp(-3.0 * t)
        # Fundamental + harmonics
        val = math.sin(2.0 * math.pi * 330.0 * t) + 0.5 * math.sin(2.0 * math.pi * 660.0 * t)
        val *= envelope * 0.8
        
        # 16-bit PCM
        pcm_val = int(max(-1.0, min(1.0, val)) * 32767)
        wav_file.writeframesraw(struct.pack('<h', pcm_val))
PYWAV

# ─────────────────────────────────────────────────────────────
# 2. dsp/__init__.py
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/dsp/__init__.py" << 'EOF'
# DSP Package
EOF
cat > "$WORKSPACE_DIR/dsp/effects/__init__.py" << 'EOF'
# Effects Package
EOF

# ─────────────────────────────────────────────────────────────
# 3. dsp/core.py (BUGS: Hardcoded 44100 SR, PCM Truncation)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/dsp/core.py" << 'EOF'
import numpy as np
import wave
from dsp.effects.delay import DelayEffect
from dsp.effects.distortion import DistortionEffect
from dsp.effects.chorus import ChorusEffect

class AudioPipeline:
    def __init__(self, sample_rate=48000):
        self.sample_rate = sample_rate
        
        # BUG: Hardcoded 44100 instead of dynamic sample_rate causes pitch-shifting and timing errors
        self.delay = DelayEffect(sample_rate=44100)
        self.distortion = DistortionEffect()
        self.chorus = ChorusEffect(sample_rate=44100)

    def process(self, data):
        """Run audio through the effect chain."""
        data = self.distortion.process(data)
        data = self.chorus.process(data)
        data = self.delay.process(data)
        return data

    def export_wav(self, data, filename):
        """Export float array [-1.0, 1.0] to a 16-bit WAV file."""
        data = np.clip(data, -1.0, 1.0)
        
        # BUG: Direct cast truncates floats (e.g., 0.99 -> 0). Causes quantization/bit-crushing noise.
        pcm_data = (data * 32767).astype(np.int16)
        
        with wave.open(filename, 'w') as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(pcm_data.tobytes())
EOF

# ─────────────────────────────────────────────────────────────
# 4. dsp/effects/delay.py (BUG: Buffer Overrun)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/dsp/effects/delay.py" << 'EOF'
import numpy as np

class DelayEffect:
    def __init__(self, sample_rate, delay_ms=200, feedback=0.4):
        self.delay_samples = int((delay_ms / 1000.0) * sample_rate)
        self.feedback = feedback
        self.buffer_size = self.delay_samples * 2
        self.buffer = np.zeros(self.buffer_size)
        self.write_ptr = 0

    def process(self, data):
        out = np.zeros_like(data)
        for i in range(len(data)):
            read_ptr = self.write_ptr - self.delay_samples
            if read_ptr < 0:
                read_ptr += self.buffer_size
                
            delayed_sample = self.buffer[read_ptr]
            out[i] = data[i] + delayed_sample
            
            self.buffer[self.write_ptr] = data[i] + delayed_sample * self.feedback
            
            self.write_ptr += 1
            # BUG: Write pointer is never wrapped. Will cause IndexError when processing long files.
            
        return out
EOF

# ─────────────────────────────────────────────────────────────
# 5. dsp/effects/distortion.py (BUG: DC Offset)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/dsp/effects/distortion.py" << 'EOF'
import numpy as np

class DistortionEffect:
    def __init__(self, drive=5.0):
        self.drive = drive

    def process(self, data):
        """Asymmetrical overdrive transfer function."""
        driven = data * self.drive
        
        # BUG: This specific asymmetrical math accidentally shifts the waveform up by exactly 0.25 on the Y axis
        # creating a severe DC offset that damages speakers.
        out = np.where(driven > 0, 1.0 - np.exp(-driven), -1.0 + np.exp(driven)) + 0.25
        
        return out
EOF

# ─────────────────────────────────────────────────────────────
# 6. dsp/effects/chorus.py (BUG: Zipper Noise / Truncation)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/dsp/effects/chorus.py" << 'EOF'
import numpy as np

class ChorusEffect:
    def __init__(self, sample_rate, rate_hz=1.2, depth_ms=3.0):
        self.sample_rate = sample_rate
        self.rate_hz = rate_hz
        self.depth_samples = (depth_ms / 1000.0) * sample_rate
        self.buffer_size = int(self.depth_samples * 4)
        self.buffer = np.zeros(self.buffer_size)
        self.write_ptr = 0
        self.lfo_phase = 0.0

    def process(self, data):
        out = np.zeros_like(data)
        phase_inc = 2.0 * np.pi * self.rate_hz / self.sample_rate
        
        for i in range(len(data)):
            lfo_val = (np.sin(self.lfo_phase) + 1.0) / 2.0
            current_delay = 1.0 + lfo_val * self.depth_samples
            
            read_ptr = self.write_ptr - current_delay
            while read_ptr < 0:
                read_ptr += self.buffer_size
                
            # BUG: Truncating a continuously floating read_ptr to int causes "zipper noise" (staircase jumps).
            # It needs linear interpolation between idx and idx+1.
            idx = int(read_ptr) % self.buffer_size
            delayed_sample = self.buffer[idx]
            
            out[i] = data[i] * 0.7 + delayed_sample * 0.5
            
            self.buffer[self.write_ptr] = data[i]
            self.write_ptr = (self.write_ptr + 1) % self.buffer_size
            self.lfo_phase += phase_inc
            
        return out
EOF

# ─────────────────────────────────────────────────────────────
# 7. tests/test_dsp.py
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_dsp.py" << 'EOF'
import unittest
import numpy as np
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dsp.core import AudioPipeline
from dsp.effects.delay import DelayEffect
from dsp.effects.distortion import DistortionEffect
from dsp.effects.chorus import ChorusEffect

class TestDSPLibrary(unittest.TestCase):
    def test_sample_rate_passthrough(self):
        pipeline = AudioPipeline(sample_rate=48000)
        # Ensure effects utilize the dynamic sample rate, not hardcoded 44100
        self.assertEqual(pipeline.delay.delay_samples, int((200 / 1000.0) * 48000))
        self.assertEqual(pipeline.chorus.sample_rate, 48000)

    def test_delay_buffer_overrun(self):
        delay = DelayEffect(48000, delay_ms=10)
        long_audio = np.zeros(delay.buffer_size + 1000)
        try:
            delay.process(long_audio)
        except IndexError:
            self.fail("Delay buffer caused IndexError. Check wrap-around logic.")

    def test_distortion_dc_offset(self):
        dist = DistortionEffect()
        # Processing absolute silence should return 0.0, not shift to 0.25
        silence = np.zeros(100)
        out = dist.process(silence)
        self.assertAlmostEqual(np.mean(out), 0.0, places=4, msg="Severe DC offset detected in distortion algorithm.")

    def test_pcm_export_rounding(self):
        pipeline = AudioPipeline()
        # A float that should round UP to 17, but truncation leaves it at 16
        test_data = np.array([16.9 / 32767.0])
        pipeline.export_wav(test_data, "tests/temp.wav")
        import wave, struct
        with wave.open("tests/temp.wav", 'r') as w:
            frames = w.readframes(1)
            val = struct.unpack('<h', frames)[0]
            self.assertEqual(val, 17, "PCM export is truncating floats instead of rounding.")
        os.remove("tests/temp.wav")

if __name__ == '__main__':
    unittest.main()
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Start VS Code with the workspace
echo "Starting VS Code..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" > /tmp/vscode_task.log 2>&1 &
sleep 5

# Wait for VS Code window
wait_for_vscode 30 || true

# Maximize and Focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'Visual Studio Code' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="