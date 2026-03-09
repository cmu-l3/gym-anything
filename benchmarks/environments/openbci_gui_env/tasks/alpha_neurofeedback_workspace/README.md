# Alpha Neurofeedback Workspace Configuration

## Domain Context

Neurofeedback therapy uses real-time EEG feedback to help patients self-regulate their brainwave activity. Alpha-wave neurofeedback (8–12 Hz) is a clinically established treatment for anxiety and ADHD, used in licensed clinical practices and research hospitals. A neurofeedback technician must configure the OpenBCI GUI workstation with a standardized, reproducible workspace for each treatment protocol so that sessions can be reliably replicated across multiple patients and visits. Setting up the workspace involves selecting the correct data source, arranging the display panels, assigning specific analytical widgets, configuring the signal filter to the appropriate frequency band, enabling expert controls, documenting the workspace state, and saving the configuration file for reuse.

## Task Overview

Configure OpenBCI GUI as a complete alpha neurofeedback monitoring workspace. This involves starting an EEG session in Synthetic mode, arranging the interface into a 4-panel display, assigning four specific analysis widgets to those panels, setting the bandpass filter to pass the 1–40 Hz range (preserving delta through low-gamma while rejecting EMG noise), enabling Expert Mode (which unlocks advanced controls and the screenshot shortcut), capturing a screenshot to document the final workspace state, and saving the entire configuration to a settings file.

## Required End State

- Active Synthetic EEG session running in the GUI
- 4-panel widget layout configured with:
  - Panel 1: Time Series (raw EEG waveforms)
  - Panel 2: FFT Plot (frequency spectrum)
  - Panel 3: Band Power (delta/theta/alpha/beta/gamma power bars)
  - Panel 4: Focus (concentration metric widget)
- Bandpass filter set to 1–40 Hz (1 Hz low cutoff, 40 Hz high cutoff)
- Expert Mode enabled
- At least one new screenshot saved to ~/Documents/OpenBCI_GUI/Screenshots/
- Settings file saved to ~/Documents/OpenBCI_GUI/Settings/ (any filename)

## Success Criteria

1. A settings JSON file was saved to ~/Documents/OpenBCI_GUI/Settings/ after the task began
2. The saved settings include evidence of the four required widget types (Time Series, FFT Plot, Band Power, Focus)
3. The bandpass filter low cutoff is approximately 1 Hz
4. The bandpass filter high cutoff is approximately 40 Hz
5. A new screenshot file exists in ~/Documents/OpenBCI_GUI/Screenshots/ (created after task start, which requires Expert Mode to be active)

## Verification Strategy

- `setup_task.sh`: Records the initial screenshot count and settings file list as baseline; launches OpenBCI GUI at the Control Panel
- `export_result.sh`: Finds the newest settings JSON (by modification time), parses it with Python extracting widget names, filter values, and expert mode state; counts new screenshots; writes all findings to `/tmp/alpha_neurofeedback_workspace_result.json`
- `verifier.py`: Reads the result JSON, awards partial credit per criterion, requires 60/100 points to pass

## Difficulty Rationale

This task is very hard because the agent must independently:
1. Navigate from the Control Panel to start a Synthetic session
2. Discover and use the Layout selector to switch to a 4-panel display
3. Individually configure each of the 4 panels by clicking panel dropdowns and selecting the correct widget type — including the non-obvious "Focus" widget
4. Find the Filters dialog and set precise numeric values for both the low and high cutoff
5. Locate and enable Expert Mode (hidden in a hamburger/overflow menu)
6. Use the keyboard shortcut 'm' to capture a screenshot (only works when Expert Mode is active)
7. Find and use the Save Settings feature to write the config to disk
No UI navigation steps are provided — the agent must explore the interface to discover each feature.
