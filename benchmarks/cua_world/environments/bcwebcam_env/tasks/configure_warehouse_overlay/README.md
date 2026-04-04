# Task: configure_warehouse_overlay

## Overview

**Domain**: Warehousing / Logistics – WMS overlay scanning
**Difficulty**: Hard
**Industry context**: Warehouse order pickers (the top bcWebCam occupation by GDP, $1.9B) use bcWebCam as a transparent overlay on their WMS terminal, enabling simultaneous barcode scanning and order management.

## Scenario

An Amazon-style fulfillment center in Kaiserslautern, Germany uses SAP EWM (Extended Warehouse Management) at its pick stations. Workers must scan product barcodes while maintaining visibility of their SAP task list. The station runs Windows with bcWebCam overlay configured to let the WMS show through.

**Three configuration requirements:**
1. **No terminating character**: SAP EWM's barcode input field uses its own scan protocol — any keystroke appended after the barcode corrupts the input. Remove the {ENTER} that is currently appended.
2. **60% opacity**: Workers must clearly see the SAP task list through the bcWebCam overlay. Current opacity is 80%.
3. **1-second duplicate prevention**: On fast pick conveyor sections, the same bin location barcode may appear twice in a scan. The 1-second grace period discards the second read.

## Goal

Configure bcWebCam so that:
- No keystroke is appended after barcode scans (empty terminating character)
- Window opacity is **60%** (`0,6` in bcWebCam notation with comma as decimal separator)
- Duplicate barcodes within **1 second** are suppressed

## Starting State

bcWebCam is running with:
- Terminating character: `{ENTER}`
- Opacity: `0,8` (80%)
- Duplicate prevention: 0 (disabled)

## Success Criteria

The INI file at `C:\Users\Docker\AppData\Local\bcWebCam\bcWebCam.ini` must contain:
1. `SendKeysPostfix =` (empty value — no keystroke after scan)
2. `Opacity = 0,6` (60% opacity, decimal with comma)
3. `BcGracePeriod = 1` (1-second duplicate suppression)

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| No terminating keystroke | 34 | `SendKeysPostfix == ""` (empty) |
| 60% opacity | 33 | `Opacity == "0,6"` |
| 1-second grace period | 33 | `BcGracePeriod == "1"` |

Total: 100 points. Pass threshold: 80 (all 3 criteria correct = 100).

## Important Notes

- bcWebCam uses a comma as the decimal separator for opacity (`0,6` not `0.6`)
- The "None" option for terminating character results in an empty `SendKeysPostfix =` line in the INI
- Opacity is set in the Options dialog (gear icon), not the Barcode Options dialog
- Always-on-top (TopMost) should remain enabled but is not explicitly verified
