# LibreOffice Calc Medication Refill Coordinator Task (`med_refill_coordinator@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, conditional logic, formula creation, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~11

## Overview

Help manage multiple prescription medications with different refill schedules, day supplies, and insurance restrictions. Calculate precise refill dates, identify which medications are due for refill soon, and flag potential issues where someone might run out before the insurance-allowed refill window opens.

## Scenario

You're helping a caregiver manage medications for an elderly parent with multiple chronic conditions. They've had scary incidents where medications ran out unexpectedly, causing emergency room visits. They need a spreadsheet that tells them exactly when to call the pharmacy for each medication—not too early (insurance will reject) or too late (risk running out).

## Starting Data

The spreadsheet opens with 5 medications and these columns:
- **Medication Name**: Name and dosage
- **Last Refill Date**: When prescription was most recently filled
- **Quantity Dispensed**: Number of pills/doses in the bottle
- **Daily Dosage**: How many pills taken per day
- **Pharmacy Name**: Where to call for refills

## Required Actions

### 1. Calculate Days Supply (Column F)
Create formula: `=D2/E2` (Quantity ÷ Daily Dosage)

### 2. Calculate Refill Due Date (Column G)
Create formula: `=C2+F2` (Last Refill Date + Days Supply)

### 3. Calculate Insurance Allows Refill Date (Column H)
Insurance typically allows refill at 75% through supply.
Create formula: `=C2+(F2*0.75)`

### 4. Calculate Days Until Can Refill (Column I)
Create formula: `=H2-TODAY()` (negative means can refill now)

### 5. Calculate Days Until Out (Column J)
Create formula: `=G2-TODAY()` (shows urgency)

### 6. Create Action Needed Flag (Column K)
Conditional formula: