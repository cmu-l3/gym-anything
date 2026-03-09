# Eyes-Open Resting-State Alpha Wave Analysis Setup

## Domain Context

Alpha waves (8–12 Hz) are prominent in the EEG during relaxed, eyes-open wakefulness, particularly over posterior regions of the scalp. Resting-state EEG analysis is a standard measure in cognitive neuroscience, clinical neuroimaging, and sleep research. The "eyes-open" condition serves as the canonical baseline for alpha suppression studies: alpha power is typically reduced (suppressed) when the eyes are open compared to eyes closed, making it an important reference condition for studying attention, arousal, and neurological disorders.

A cognitive neuroscience researcher setting up an alpha analysis session must load the appropriate baseline recording, configure the display widgets to simultaneously show both the time-domain signal and the frequency-domain spectrum (for direct alpha peak identification), set the bandpass filter to include the full frequency range (1–50 Hz) so that all physiologically relevant bands from delta to gamma are visible, set the amplitude scale appropriate for eyes-open EEG (100 µV range captures typical alpha amplitude), enable Expert Mode for documentation, and save the analysis configuration.

## Task Overview

Load the Eyes Open EEG baseline recording in Playback mode and configure OpenBCI GUI for resting-state alpha wave analysis. The recording (`OpenBCI-EEG-S001-EyesOpen.txt`) is from the PhysioNet EEG Motor Movement/Imagery Dataset, Subject S001, Run R01 (61 seconds of 8-channel EEG recorded at 250 Hz during eyes-open rest). The analysis environment requires Band Power and FFT Plot widgets for spectral analysis, appropriate bandpass filtering and amplitude scaling, and documented configuration.

## Required End State

- Playback session running with file `OpenBCI-EEG-S001-EyesOpen.txt`
- Band Power widget visible in at least one display panel
- FFT Plot widget visible in at least one display panel (distinct from Band Power)
- Bandpass filter set to 1–50 Hz (full spectrum: delta through gamma)
- Time Series vertical scale set to 100 µV
- Expert Mode enabled
- New screenshot captured in ~/Documents/OpenBCI_GUI/Screenshots/
- Settings file saved to ~/Documents/OpenBCI_GUI/Settings/

## Data Source

Real EEG recording from PhysioNet EEG Motor Movement/Imagery Database (eegmmidb 1.0.0), Subject S001, Run R01 (eyes open baseline). 8 channels, 250 Hz sample rate. Channels: Fp1, Fp2, C3, C4, P7, P8, O1, O2.

## Success Criteria

1. Settings file saved after task start
2. Band Power widget present in settings
3. FFT Plot widget present in settings
4. Bandpass filter is 1–50 Hz (low ~1 Hz, high ~50 Hz)
5. New screenshot file captured

## Verification Strategy

- `setup_task.sh`: Verifies recording file exists; records baseline; launches at Control Panel
- `export_result.sh`: Parses settings for widgets, bandpass values; counts new screenshots
- `verifier.py`: Multi-criterion scoring; pass at 60/100

## Difficulty Rationale

This task is very hard because the agent must:
1. Navigate to Playback mode and select a specific file from the filesystem
2. Independently identify that Band Power AND FFT Plot are both needed (two different widget interactions, not just one)
3. Set a specific bandpass filter range (1–50 Hz requires changing both the low and high cutoff from defaults)
4. Find and change the Time Series vertical scale to a specific value (100 µV, not the default)
5. Enable Expert Mode (in a hidden menu)
6. Press the 'm' key shortcut to capture a screenshot
7. Save the complete settings configuration
Each step requires navigating to a different part of the interface without UI guidance.
