# BCI Research Multi-Modal Dashboard Configuration

## Domain Context

Cognitive neuroscience and BCI labs run complex multi-modal data collection sessions where researchers must simultaneously monitor raw EEG waveforms, frequency spectra, brainwave band power distributions, inertial movement data, cognitive state metrics, and topographic scalp maps. A graduate researcher or lab technician must configure a multi-panel dashboard that captures all relevant biosignal streams before each participant session. In the US, the 60 Hz power line interference is the dominant noise source in EEG and must be filtered with a notch filter. The complete configuration — including the 6-panel layout, all widget assignments, and filter settings — must be saved and documented so the same workspace can be reliably reproduced across participants and sessions.

## Task Overview

Configure OpenBCI GUI as a comprehensive 6-panel BCI research monitoring dashboard. This requires starting a Synthetic EEG session, selecting a 6-panel display layout (the maximum simultaneously visible panels), assigning a distinct widget type to each of the 6 panels (using all available major widget types), enabling 60 Hz notch filtering, enabling Expert Mode, taking a documentation screenshot, and saving the full configuration.

## Required End State

- Active Synthetic EEG session
- 6-panel display layout active
- Each of the 6 panels configured with a distinct widget type:
  - Time Series (raw EEG waveforms)
  - FFT Plot (frequency spectrum)
  - Band Power (brainwave power bars)
  - Accelerometer (inertial measurement)
  - Focus (concentration index)
  - Head Plot (topographic scalp map)
- Notch filter set to 60 Hz
- Expert Mode enabled
- New screenshot captured in ~/Documents/OpenBCI_GUI/Screenshots/
- Settings saved to ~/Documents/OpenBCI_GUI/Settings/

## Success Criteria

1. Settings file saved after task start
2. At least 5 distinct major widget types present in the saved settings
3. Notch filter configured at 60 Hz
4. Expert Mode enabled
5. New screenshot file exists (proving Expert Mode was active and 'm' was pressed)

## Verification Strategy

- `setup_task.sh`: Records baseline; launches at Control Panel
- `export_result.sh`: Parses settings JSON for widget types, notch frequency, expert mode; counts screenshots; writes results
- `verifier.py`: Awards points per criterion; pass at 60/100

## Difficulty Rationale

This is the most challenging task because:
1. The 6-panel layout option must be discovered among multiple layout choices without being told which icon represents it
2. All 6 panels must each be individually configured — the agent must click each panel's widget selector and choose from a potentially long dropdown list
3. The "Head Plot" and "Accelerometer" widgets are less obvious than Time Series and FFT — the agent must explore the widget list
4. The notch filter is a separate setting from the bandpass filter (a distinct UI dialog or panel)
5. Expert Mode is hidden in an overflow/hamburger menu and must be found
6. Screenshot capture requires Expert Mode AND pressing the 'm' keyboard shortcut
7. Settings must be saved via a separate menu action
All 7 of these are independent features the agent must discover and use.
