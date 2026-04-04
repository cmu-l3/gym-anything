# EEG Data Collection Recording Session Setup

## Domain Context

EEG data collection sessions in clinical research and cognitive psychology labs require careful setup to produce high-quality, analyzable recordings. A research lab assistant or EEG technician is responsible for configuring the recording system before each participant session: selecting the appropriate data source, configuring signal filtering to remove power line interference and DC drift, arranging the multi-panel display to monitor signal quality across multiple feature views simultaneously, initiating the recording, documenting the session state with a screenshot, properly stopping the recording, and saving the configuration for reproducibility.

In the US, electrical power line interference occurs at 60 Hz and must be notch-filtered from EEG recordings. The 1–50 Hz bandpass filter removes slow DC drift (below 1 Hz) and high-frequency EMG artifacts (above 50 Hz) while preserving the clinically relevant EEG frequency bands (delta, theta, alpha, beta, low gamma). The Accelerometer widget allows simultaneous monitoring of head movement artifacts. Band Power and FFT Plot widgets provide real-time spectral monitoring to detect contamination.

## Task Overview

Set up OpenBCI GUI for a complete EEG data recording session: start a Synthetic EEG session, configure a 4-panel display with specific monitoring widgets, apply both bandpass (1–50 Hz) and notch (60 Hz) filters, enable Expert Mode, start an EEG recording, capture a documentation screenshot while the recording is active, stop the recording to finalize the file, and save the session configuration.

## Required End State

- Active Synthetic EEG session
- 4-panel display layout with: Time Series (panel 1), Band Power (panel 2), FFT Plot (panel 3), Accelerometer (panel 4)
- Bandpass filter set to 1–50 Hz
- Notch filter set to 60 Hz
- Expert Mode enabled
- At least one EEG recording file saved in ~/Documents/OpenBCI_GUI/Recordings/ that is newer than when the task started and has a non-trivial file size (>1 KB of actual EEG data)
- New screenshot captured in ~/Documents/OpenBCI_GUI/Screenshots/
- Settings file saved to ~/Documents/OpenBCI_GUI/Settings/

## Data

Real EEG recording capability uses the Synthetic data source, which generates algorithmically-correct 8-channel EEG-like signals. The recording file is saved in OpenBCI's .txt format.

## Success Criteria

1. Settings file saved after task start (configuration preservation)
2. A new recording file exists in Recordings/ directory, created after task start, with size > 2 KB (proving a real EEG capture was initiated and completed)
3. Bandpass filter at 1–50 Hz in the saved settings
4. Notch filter at 60 Hz in the saved settings
5. New screenshot captured (proving Expert Mode was active)

## Verification Strategy

- `setup_task.sh`: Records the initial set of recording files (so new ones can be detected); records screenshot count; records start timestamp; cleans any stale output
- `export_result.sh`: Lists recording files newer than task start; parses settings for filter values and widget names; counts new screenshots; builds result JSON
- `verifier.py`: Awards points per criterion; requires 60/100 to pass; notably awards 30 pts for a valid recording file since this is the most complex action (requires starting AND stopping the recording)

## Difficulty Rationale

This task is very hard because the agent must perform 8 independent operations in logical sequence:
1. Start a Synthetic session from the Control Panel
2. Change the layout to 4-panel (without being told which layout selector to use)
3. Assign 4 specific widgets including Accelerometer (non-obvious)
4. Set bandpass filter 1–50 Hz (two separate numeric values to change)
5. Set notch filter to 60 Hz (a separate filter setting, distinct from bandpass)
6. Enable Expert Mode (hidden in overflow menu)
7. Start a recording (may require finding a Record button or keyboard shortcut)
8. Press 'm' for screenshot
9. Stop the recording (requires finding the stop control)
10. Save settings (requires finding the Save Settings menu item)
The recording start/stop is a time-dependent operation — the agent must initiate, wait, then terminate the recording — creating a sequential dependency not present in purely configuration tasks.
