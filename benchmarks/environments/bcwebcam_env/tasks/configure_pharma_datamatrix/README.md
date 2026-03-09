# Task: configure_pharma_datamatrix

## Overview

**Domain**: Healthcare / Pharmaceuticals – EU FMD compliance scanning
**Difficulty**: Hard
**Industry context**: Pharmacists and pharmacy technicians use barcode scanners (including webcam-based) for drug verification under EU Directive 2011/62/EU (Falsified Medicines Directive), which mandates scanning of serialized 2D DataMatrix codes on all prescription drugs.

## Scenario

A German hospital pharmacy (Krankenhaus-Apotheke) is implementing FMD compliance. Under EU FMD, every prescription medicine box carries a serialized 2D DataMatrix code (GS1 standard). The pharmacy's verification workflow scans the code against the EU Hub database before dispensing.

The current bcWebCam setup was configured for a retail pharmacy workflow: linear barcodes enabled (for customer loyalty cards) and DataMatrix disabled. For FMD compliance, this must be reversed.

**Four configuration requirements:**
1. **Disable all linear barcodes**: Drug packages have lot-number labels with Code 128 barcodes that are NOT FMD codes — they cause false reads. Linear barcode scanning must be disabled.
2. **Enable DataMatrix 2D codes**: The FMD serialization code is a 2D DataMatrix. This must be enabled in bcWebCam's Barcode Options.
3. **No terminating character**: The hospital's FMD verification software (SecurPharm client) reads raw scan input without expecting an appended keystroke.
4. **1-second duplicate prevention**: The same medicine box must not be validated twice (FMD Hub rejects duplicate serial number submissions within a session).

## Goal

Configure bcWebCam for EU FMD pharmaceutical scanning:
- Linear barcodes (`[BarcodeL]` section) disabled (Type = 0)
- DataMatrix codes (`[BarcodeD]` section) enabled (Type nonzero)
- No terminating character (`SendKeysPostfix` empty)
- 1-second duplicate prevention (`BcGracePeriod = 1`)

## Starting State

bcWebCam is running with:
- `[BarcodeL] Type = 8416887` (linear barcodes ENABLED)
- `[BarcodeD] Type = 0` (DataMatrix DISABLED)
- `SendKeysPostfix = {ENTER}`
- `BcGracePeriod = 0`

## Verification Strategy

The agent must navigate BOTH the Options dialog (gear icon, for general settings) AND the Barcode Options dialog (barcode icon, left of gear) to complete this task.

| Criterion | Points | Check |
|-----------|--------|-------|
| Linear barcodes disabled | 25 | `[BarcodeL] Type == "0"` |
| DataMatrix enabled | 25 | `[BarcodeD] Type != "0"` (nonzero) |
| No terminating key | 25 | `SendKeysPostfix == ""` |
| 1-second grace period | 25 | `BcGracePeriod == "1"` |

Total: 100 points. Pass threshold: 75 (3 of 4 criteria).
