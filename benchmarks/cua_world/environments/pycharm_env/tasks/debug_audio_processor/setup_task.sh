#!/bin/bash
echo "=== Setting up debug_audio_processor task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/audio_core"

# Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/debug_audio_result.json 2>/dev/null || true

# Create structure
mkdir -p "$PROJECT_DIR/audio_processor"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
scipy>=1.10.0
pytest>=7.0
EOF

# --- audio_processor/__init__.py ---
touch "$PROJECT_DIR/audio_processor/__init__.py"

# --- BUG 1: utils.py (Duration) ---
# Bug: uses data.size (total elements) instead of shape[0] (frames)
cat > "$PROJECT_DIR/audio_processor/utils.py" << 'EOF'
import numpy as np
import wave
import contextlib

def get_audio_duration(data: np.ndarray, sample_rate: int) -> float:
    """
    Calculate duration of audio data in seconds.
    
    Args:
        data: Numpy array of audio samples (N_samples, N_channels) or (N_samples,)
        sample_rate: Sampling rate in Hz
        
    Returns:
        Duration in seconds
    """
    if sample_rate <= 0:
        raise ValueError("Sample rate must be positive")
    
    # BUG: This calculates total elements / rate, which is wrong for stereo
    # Correct: data.shape[0] / sample_rate
    return data.size / sample_rate

def load_wav(path: str) -> tuple[np.ndarray, int]:
    """Helper to load wav file (returns float32 array -1..1 and sr)."""
    # Implementation not relevant for bug, provided for context
    with contextlib.closing(wave.open(path, 'rb')) as wf:
        sr = wf.getframerate()
        frames = wf.readframes(wf.getnframes())
        dtype = np.int16
        data = np.frombuffer(frames, dtype=dtype).astype(np.float32)
        if wf.getnchannels() > 1:
            data = data.reshape(-1, wf.getnchannels())
        return data / 32768.0, sr
EOF

# --- BUG 2: filters.py (Filter Cutoff) ---
# Bug: signal.butter cutoff interpreted as normalized frequency (0-1) if fs not provided.
# We pass 100Hz, which scipy interprets as 100 * Nyquist if not careful, or fails if > 1.
cat > "$PROJECT_DIR/audio_processor/filters.py" << 'EOF'
import numpy as np
from scipy import signal

def apply_low_cut_filter(data: np.ndarray, sample_rate: int, cutoff_freq: float = 80.0) -> np.ndarray:
    """
    Apply a High-pass (Low-cut) filter to remove rumble/noise below cutoff.
    
    Args:
        data: Audio array
        sample_rate: Sampling rate
        cutoff_freq: Frequency in Hz to cut below
        
    Returns:
        Filtered audio array
    """
    # 2nd order Butterworth filter
    # BUG: signal.butter expects normalized frequency (0 to 1, where 1 is Nyquist)
    # unless 'fs' parameter is provided (added in recent scipy versions).
    # If using old style, needs cutoff / (0.5 * sample_rate).
    # Passing raw Hz (e.g. 80) usually results in error or wrong filter if < 1.
    
    sos = signal.butter(2, cutoff_freq, btype='highpass', output='sos')
    
    # Apply filter along time axis
    if data.ndim > 1:
        return signal.sosfilt(sos, data, axis=0)
    return signal.sosfilt(sos, data)
EOF

# --- BUG 3: loudness.py (RMS Calculation) ---
# Bug: Calculates Mean Absolute Deviation instead of Root Mean Square
cat > "$PROJECT_DIR/audio_processor/loudness.py" << 'EOF'
import numpy as np

def calculate_rms_amplitude(data: np.ndarray) -> float:
    """
    Calculate the RMS (Root Mean Square) amplitude of the signal.
    Used for loudness normalization.
    
    Args:
        data: Audio array
        
    Returns:
        RMS value (0.0 to 1.0)
    """
    if data.size == 0:
        return 0.0
        
    # BUG: This calculates Mean Absolute Deviation, not RMS
    # RMS should be sqrt(mean(square(data)))
    return np.mean(np.abs(data))

def normalize_loudness(data: np.ndarray, target_dbfs: float = -14.0) -> np.ndarray:
    """Normalize audio to target dBFS."""
    rms = calculate_rms_amplitude(data)
    if rms <= 0:
        return data
        
    target_linear = 10 ** (target_dbfs / 20.0)
    gain = target_linear / rms
    
    # Clip to prevent distortion
    return np.clip(data * gain, -1.0, 1.0)
EOF

# --- TESTS ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import numpy as np

@pytest.fixture
def mono_sine_wave():
    """1 second of 440Hz sine wave at 44.1kHz"""
    sr = 44100
    t = np.linspace(0, 1, sr, endpoint=False)
    return np.sin(2 * np.pi * 440 * t).astype(np.float32), sr

@pytest.fixture
def stereo_noise():
    """1 second of stereo white noise"""
    sr = 44100
    return np.random.uniform(-0.5, 0.5, (sr, 2)).astype(np.float32), sr
EOF

cat > "$PROJECT_DIR/tests/test_utils.py" << 'EOF'
import numpy as np
from audio_processor.utils import get_audio_duration

def test_duration_mono():
    sr = 48000
    # 2 seconds of mono
    data = np.zeros(sr * 2)
    assert get_audio_duration(data, sr) == 2.0

def test_duration_stereo():
    sr = 44100
    # 1.5 seconds of stereo (N, 2)
    data = np.zeros((int(sr * 1.5), 2))
    
    # If bug exists (size/rate), this returns 3.0 instead of 1.5
    duration = get_audio_duration(data, sr)
    assert duration == 1.5, f"Expected 1.5s, got {duration}s. Did you handle channel count correctly?"

def test_duration_empty():
    assert get_audio_duration(np.array([]), 44100) == 0.0
EOF

cat > "$PROJECT_DIR/tests/test_filters.py" << 'EOF'
import numpy as np
from audio_processor.filters import apply_low_cut_filter

def test_filter_attenuates_low_freq():
    sr = 44100
    t = np.linspace(0, 1, sr, endpoint=False)
    
    # Signal: 20Hz (should be cut) + 1000Hz (should pass)
    # 80Hz cutoff
    low_freq = np.sin(2 * np.pi * 20 * t)
    high_freq = np.sin(2 * np.pi * 1000 * t)
    mix = low_freq + high_freq
    
    try:
        filtered = apply_low_cut_filter(mix, sr, cutoff_freq=80.0)
    except Exception as e:
        pytest.fail(f"Filter crashed: {e}")
        
    # Check if 20Hz component is attenuated significantly
    # We can check by doing an FFT or roughly checking energy
    # But for a unit test, let's just ensure it runs and outputs reasonable range
    # and isn't silence (bug might cause silence or explosion)
    assert not np.allclose(filtered, 0), "Filter output is silence"
    assert not np.any(np.isnan(filtered)), "Filter output contains NaNs"
    
    # Simple check: Energy of filtered should be less than input (removed low freq)
    # but more than 0
    input_energy = np.sum(mix**2)
    output_energy = np.sum(filtered**2)
    
    assert output_energy < input_energy, "Filter did not remove energy"
    assert output_energy > input_energy * 0.3, "Filter removed too much energy (likely everything)"

def test_filter_shape_preservation():
    sr = 44100
    data = np.random.randn(sr, 2)
    filtered = apply_low_cut_filter(data, sr)
    assert filtered.shape == data.shape
EOF

cat > "$PROJECT_DIR/tests/test_loudness.py" << 'EOF'
import numpy as np
from audio_processor.loudness import calculate_rms_amplitude, normalize_loudness

def test_rms_sine_wave():
    # RMS of a sine wave with amplitude A is A / sqrt(2) ~= 0.707 * A
    sr = 1000
    t = np.linspace(0, 1, sr)
    amp = 1.0
    data = amp * np.sin(2 * np.pi * 50 * t)
    
    rms = calculate_rms_amplitude(data)
    expected = 1.0 / np.sqrt(2)
    
    # The buggy implementation (Mean Abs) gives 2/pi * A ~= 0.637 * A
    # The correct implementation gives ~0.707
    assert abs(rms - expected) < 0.05, f"RMS incorrect. Expected ~{expected:.3f}, got {rms:.3f}"

def test_rms_dc_offset():
    # Constant DC signal of 1.0
    # RMS should be 1.0
    # Mean Abs is also 1.0, so this doesn't catch the bug, but good for sanity
    data = np.ones(100)
    assert abs(calculate_rms_amplitude(data) - 1.0) < 0.001

def test_normalize_target():
    data = np.random.uniform(-0.5, 0.5, 1000)
    target_db = -20.0
    norm = normalize_loudness(data, target_db)
    
    new_rms = calculate_rms_amplitude(norm)
    expected_rms = 10**(target_db/20)
    
    assert abs(new_rms - expected_rms) < 0.01
EOF

# Generate a reference wav file for the agent to potentially test with
# (Though they are encouraged to use unit tests)
cat > "$PROJECT_DIR/data/generate_reference.py" << 'EOF'
import wave
import struct
import math

def generate_sine(freq, duration, rate, amp=0.5):
    n_frames = int(duration * rate)
    data = []
    for i in range(n_frames):
        value = int(amp * 32767.0 * math.sin(2 * math.pi * freq * i / rate))
        data.append(struct.pack('<h', value))
    return b''.join(data)

with wave.open('reference.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(44100)
    f.writeframes(generate_sine(440, 1.0, 44100))
EOF

cd "$PROJECT_DIR/data" && python3 generate_reference.py && rm generate_reference.py

# Record setup time
date +%s > /tmp/task_start_time.txt

# Open PyCharm
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Wait for PyCharm
wait_for_pycharm 60 || echo "WARNING: PyCharm not detected"
focus_pycharm_window
sleep 3

# Screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="