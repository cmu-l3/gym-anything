# Task: configure_grocery_checkout

## Overview

**Domain**: Retail – Point-of-Sale (POS) integration
**Difficulty**: Hard
**Industry context**: bcWebCam is used by retail workers (Stockers/Order Fillers, Retail Salespersons) as a cost-effective barcode scanner substitute for dedicated hardware scanners like Zebra DataWedge.

## Scenario

A German supermarket chain is deploying bcWebCam at Windows-based self-checkout kiosks running NCR Counterpoint POS software. The POS integration has three mandatory requirements:

1. **TAB terminating character**: The POS form advances the cursor to the next field on TAB (not ENTER). Scanning a barcode must be followed by TAB so the POS correctly processes each item.
2. **3-second duplicate prevention**: Customers occasionally scan items twice during slow checkout (fumbling with packages). A 3-second grace period drops duplicate reads of the same barcode.
3. **No acoustic beep**: The NCR POS plays its own "scan accepted" audio. The bcWebCam beep creates a confusing double-sound that startles customers.

## Goal

Configure bcWebCam so that:
- Each scanned barcode is followed by a **TAB** keystroke (not ENTER)
- Duplicate barcodes within **3 seconds** are suppressed
- The acoustic beep is **disabled**

## Starting State

bcWebCam is running with default settings:
- Terminating character: ENTER
- Duplicate prevention timeout: 0 (disabled)
- Beep: enabled

## Success Criteria

The INI file at `C:\Users\Docker\AppData\Local\bcWebCam\bcWebCam.ini` must contain:
1. `SendKeysPostfix = {TAB}` (TAB terminating character)
2. `BcGracePeriod = 3` (3-second duplicate suppression)
3. `Beep = False` (acoustic feedback disabled)

## Verification Strategy

The export script kills bcWebCam (forcing INI flush to disk), reads the INI, and writes all relevant values to `/tmp/configure_grocery_checkout_result.json`. The verifier checks each of the 3 criteria independently and awards partial credit.

| Criterion | Points | Check |
|-----------|--------|-------|
| TAB terminating character | 33 | `SendKeysPostfix == "{TAB}"` |
| 3-second grace period | 33 | `BcGracePeriod == "3"` |
| Beep disabled | 34 | `Beep == "False"` |

Total: 100 points. Pass threshold: 80 (2 of 3 criteria correct, both key ones).

## Edge Cases

- The agent must find the Options dialog (gear icon in bottom toolbar), not the Barcode Options dialog
- The INI stores boolean as `True`/`False` (capital first letter)
- The INI stores `SendKeysPostfix = {TAB}` with curly braces (bcWebCam's key notation)
- If the agent disables beep but uses wrong format (lowercase `false`), the verifier still checks for it
