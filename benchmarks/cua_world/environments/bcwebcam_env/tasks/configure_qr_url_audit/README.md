# Task: configure_qr_url_audit

## Overview

**Domain**: Healthcare / Biomedical Engineering – Medical device compliance auditing
**Difficulty**: Very Hard
**Industry context**: Hospital biomedical engineers and compliance officers use mobile/webcam scanners to audit medical devices against regulatory databases. GS1 Digital Link QR codes on devices encode URLs pointing to CE documentation, IFU (Instructions for Use), and recall notices.

## Scenario

A hospital biomedical engineering department in Munich is conducting a quarterly audit of medical devices under MDR (EU Medical Device Regulation 2017/745). Each device carries a GS1 Digital Link QR code. When scanned, this QR code URL should automatically open in the browser so the auditor can immediately verify the device's regulatory status on the manufacturer's portal.

The audit workflow requires:
1. **Automatic URL opening**: When bcWebCam detects a URL in a scanned QR code, it must automatically open the URL in the default browser (Edge/Chrome). This is the core workflow — auditor scans, browser opens documentation.
2. **No acoustic beep**: Auditing in hospital rooms requires silence (patients are present). The beep must be disabled.
3. **No terminating character**: URL-bearing QR codes must not have any extra keystroke appended — this would corrupt URL inputs in browser address bars.
4. **70% opacity**: The auditor needs to see the browser documentation BEHIND the bcWebCam window. Reduce to 70% opacity.
5. **Disable linear barcodes**: Medical devices don't use 1D barcodes for GS1 Digital Link — disabling prevents false reads from nearby product packaging.

## Goal

Configure bcWebCam for medical device compliance auditing:
- URL auto-open enabled (the "Open detected URL" option in Options dialog)
- Acoustic beep disabled (`Beep = False`)
- No terminating character (`SendKeysPostfix` empty)
- Window opacity at 70% (`Opacity = 0,7`)
- Linear barcodes disabled (`[BarcodeL] Type = 0`)

## Starting State

bcWebCam is running with default settings: URL detection disabled, beep enabled, Enter key, 80% opacity, linear barcodes disabled.

## Verification Strategy

This task is **very_hard** because:
- Requires 5 distinct settings across two dialogs (Options + Barcode Options)
- The URL auto-open setting is not immediately obvious — agent must discover it in the Options dialog
- The opacity uses European decimal notation (comma)
- Linear barcode state must be checked separately from other settings

| Criterion | Points | Check |
|-----------|--------|-------|
| URL auto-open enabled | 25 | INI contains a URL-open key set to True |
| Beep disabled | 20 | `Beep == "False"` |
| No terminating key | 20 | `SendKeysPostfix == ""` |
| 70% opacity | 20 | `Opacity == "0,7"` |
| Linear barcodes disabled | 15 | `[BarcodeL] Type == "0"` |

Total: 100 points. Pass threshold: 60 (3 of 5 criteria, weighted).

## Notes

- The URL auto-open INI key name is application-defined — the verifier checks for any key that enables URL opening
- bcWebCam's Options dialog has a "Open detected URL" checkbox that enables this feature
- The decimal separator for Opacity is a comma (German locale): `0,7` not `0.7`
