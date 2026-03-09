# Task: configure_production_scanner

## Overview

**Domain**: Manufacturing / Production – Inbound goods verification
**Difficulty**: Hard
**Industry context**: Production line workers and warehouse receivers use barcode scanners for parts verification. bcWebCam provides a low-cost scanning solution on existing Windows workstations at receiving docks.

## Scenario

A Bosch automotive parts factory in Stuttgart uses bcWebCam at the inbound goods station. Automotive components arrive sealed in clear plastic bags with Code 128 barcodes on the inner label. When bags are placed flat on the inspection camera, the barcode appears mirrored/inverted from above.

The current configuration has image inversion disabled (labels appear unreadable), no linear barcode support, Enter key, and no duplicate prevention. The factory needs a working scan station.

**Four configuration requirements:**
1. **Enable image inversion (FlipBitmap)**: Allows reading mirrored labels through the plastic bag bottom. Without this, the mirrored Code 128 cannot be decoded.
2. **Enable linear barcodes**: Code 128 is the Bosch standard for part identification. Must be enabled in bcWebCam's Barcode Options.
3. **TAB terminating character**: The parts tracking system (SAP MM) has a quantity field after the part number field — TAB moves to the correct next field.
4. **2-second duplicate prevention**: During conveyor jams, the same bag may be presented to the camera twice within 2 seconds. The grace period prevents double-recording.

## Goal

Configure bcWebCam for automotive parts production scanning:
- Image inversion enabled (`FlipBitmap = True`)
- Linear barcodes enabled (`[BarcodeL] Type` nonzero)
- TAB terminating character (`SendKeysPostfix = {TAB}`)
- 2-second duplicate prevention (`BcGracePeriod = 2`)

## Starting State

bcWebCam is running with:
- `FlipBitmap = False` (image inversion DISABLED)
- `[BarcodeL] Type = 0` (linear barcodes DISABLED)
- `SendKeysPostfix = {ENTER}`
- `BcGracePeriod = 0`

## Verification Strategy

The agent must use BOTH the Options dialog (gear icon, for FlipBitmap/SendKeysPostfix/BcGracePeriod) AND the Barcode Options dialog (for linear barcode enabling).

| Criterion | Points | Check |
|-----------|--------|-------|
| Image inversion enabled | 25 | `FlipBitmap == "True"` |
| Linear barcodes enabled | 25 | `[BarcodeL] Type != "0"` (nonzero) |
| TAB terminating character | 25 | `SendKeysPostfix == "{TAB}"` |
| 2-second grace period | 25 | `BcGracePeriod == "2"` |

Total: 100 points. Pass threshold: 75 (3 of 4 criteria).
