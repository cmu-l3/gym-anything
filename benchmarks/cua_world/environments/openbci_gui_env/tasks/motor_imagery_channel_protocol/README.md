# Motor Imagery Channel Protocol Setup

## Domain Context

Motor imagery BCI research is a cornerstone of neural prosthetics and stroke rehabilitation. In motor imagery paradigms, subjects imagine moving their limbs without executing movement, producing characteristic event-related desynchronization (ERD) and synchronization (ERS) patterns in the Mu (8–13 Hz) and Beta (13–30 Hz) frequency bands over the primary motor cortex. Electrodes placed over motor cortex — specifically C3 (left motor) and C4 (right motor) in the 10-20 system — capture these signals. Non-motor channels (Fp1/Fp2 over prefrontal cortex, P7/P8 over parietal cortex, O1/O2 over occipital cortex) contain irrelevant signals that add noise and distract from the motor imagery analysis.

A BCI researcher loading a motor imagery EEG recording must: select the correct file, apply domain knowledge to identify which channels correspond to motor cortex, disable all non-relevant channels, configure the bandpass filter to the motor-imagery-specific frequency range (Mu + Beta band: 8–30 Hz), add the FFT Plot widget for spectral monitoring, and save the protocol settings for reproducibility.

## Task Overview

Load the Motor Imagery EEG recording in Playback mode and configure OpenBCI GUI for motor cortex analysis. The recording uses the electrode order: Channel 1=Fp1, Channel 2=Fp2, Channel 3=C3, Channel 4=C4, Channel 5=P7, Channel 6=P8, Channel 7=O1, Channel 8=O2. For motor imagery analysis, only C3 (channel 3) and C4 (channel 4) are relevant; all other channels must be disabled. The bandpass filter must be set to the Mu+Beta band (8–30 Hz), the FFT Plot widget must be visible, and the configuration must be saved.

## Required End State

- Playback session running with file `OpenBCI-EEG-S001-MotorImagery.txt`
- Channels 1, 2, 5, 6, 7, 8 disabled (non-motor cortex channels)
- Channels 3 (C3) and 4 (C4) remaining active (motor cortex)
- Bandpass filter set to 8–30 Hz (Mu + Beta band)
- FFT Plot widget visible in at least one panel
- Settings file saved to ~/Documents/OpenBCI_GUI/Settings/

## Data Source

Real EEG data from the PhysioNet EEG Motor Movement/Imagery Dataset (eegmmidb 1.0.0), Subject S001, converted to OpenBCI format. This is authentic human EEG recorded at 250 Hz during a motor imagery task. The electrode channels (in order) are: Fp1, Fp2, C3, C4, P7, P8, O1, O2.

## Success Criteria

1. A settings JSON file was saved after the task began
2. At least 4 of the 6 non-motor channels (1, 2, 5, 6, 7, 8) are inactive in settings
3. Bandpass low cutoff is approximately 8 Hz
4. Bandpass high cutoff is approximately 30 Hz
5. FFT Plot widget appears in the saved settings

## Verification Strategy

- `setup_task.sh`: Records baseline settings state; launches GUI at Control Panel (Playback mode must be selected by the agent)
- `export_result.sh`: Finds the newest settings file, uses Python to parse channel active/inactive states and filter values; checks for FFT Plot widget name; writes results to `/tmp/motor_imagery_channel_protocol_result.json`
- `verifier.py`: Awards points per criterion; pass at 60/100

## Difficulty Rationale

This task is very hard because the agent must:
1. Load a Playback session and navigate the file browser to select the correct file path
2. Apply domain knowledge to identify that C3=channel 3 and C4=channel 4 in this recording's electrode order — this is not stated in the UI, requiring neuroscience knowledge
3. Individually disable 6 of 8 channels by toggling each channel button
4. Navigate to the Filters dialog and set specific numeric values for both cutoff frequencies (8 Hz and 30 Hz, which are non-default values)
5. Find and add the FFT Plot widget (a non-obvious UI interaction)
6. Find and save the settings via the Settings menu
