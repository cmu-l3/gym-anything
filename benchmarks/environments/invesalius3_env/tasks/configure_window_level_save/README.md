# Task: configure_window_level_save

## Overview

A radiologist needs to optimize a cranial CT scan for brain parenchyma visualization, create a soft-tissue segmentation mask, and save the configured project for team review. This requires changing InVesalius's window/level settings from the default bone window to a narrow brain window, creating an appropriate mask, and saving the project.

## Professional Context

Radiologists routinely switch between window/level presets to visualize different tissue types on the same CT study. The "brain window" (W=80, L=40) is the standard preset for evaluating cortical/subcortical grey-white differentiation and detecting subtle infarcts or contusions. Saving the configured project allows colleagues to review the case with the same settings.

## Goal

Complete all of the following and save the project to `/home/ga/Documents/brain_study.inv3`:
1. Adjust the window width to approximately 80 HU and window level to approximately 40 HU (brain soft-tissue window), using the window/level spinbox controls or by double-clicking the brightness/contrast indicator in InVesalius
2. Create a new segmentation mask using a soft tissue or muscle threshold preset (max HU ≤ 300, e.g. Muscle Tissue −5–135 HU, or Soft Tissue −700–225 HU)
3. Save the project via File > Save As to /home/ga/Documents/brain_study.inv3

## Required Steps (not told to agent)

1. Identify and use window/level controls (shown in the slice view or in Preferences)
2. Set W ≈ 80, L ≈ 40 (brain window)
3. Create a new mask → select soft tissue or muscle preset
4. File > Save As → navigate to /home/ga/Documents → name it brain_study.inv3

## Success Criteria

- `/home/ga/Documents/brain_study.inv3` exists and is a valid .inv3 file
- `main.plist` shows `window_width` between 30 and 250 HU (substantially narrower than default 406)
- Project contains at least 1 mask with max threshold ≤ 300 HU

## Verification Strategy

export_result.sh parses the .inv3 tarfile:
- Reads `window_width` from main.plist
- Reads each mask's `threshold_range` to find soft-tissue masks
- Records whether both conditions are met

## Ground Truth

- Default window_width in InVesalius CT Cranium: 406 HU
- Brain window standard: W=80, L=40 (acceptable range: W 30–250)
- Soft tissue masks: Soft Tissue (−700 to 225), Muscle Tissue (−5 to 135), Fat Tissue (−205 to −51), Skin Tissue (−718 to −177)

## Edge Cases

- Agent may set W=80 but L=30 or L=50 — still accepted (within ±30 of target)
- Agent may use any soft tissue preset — accepted as long as max_HU ≤ 300
- Window/level slider vs. spinbox vs. preset menu are all valid ways to change values
