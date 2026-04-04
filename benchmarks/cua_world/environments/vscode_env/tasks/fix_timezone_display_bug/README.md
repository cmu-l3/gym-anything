# Fix Timezone Display Bug Task

**Difficulty**: 🟡 Medium  
**Skills**: JavaScript, debugging, datetime handling, refactoring  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Fix a critical timezone handling bug in a healthcare appointment booking system where patient appointments are displaying incorrect times due to improper UTC-to-local timezone conversion in the frontend JavaScript code.

## Problem Description

**Scenario**: Customer support has escalated a bug where patients in different timezones see wildly incorrect appointment times:
- A Los Angeles patient scheduled for 9:00 AM sees 5:00 PM
- A New York patient scheduled for 10:00 AM sees 2:00 AM

The backend correctly stores appointments in UTC, but the frontend JavaScript in `AppointmentCard.js` is mishandling timezone conversion when displaying times to users.

## Expected Workflow

1. **Read the README.md** in the workspace to understand the problem
2. **Examine `src/components/AppointmentCard.js`** to identify the buggy timezone handling code (around line 6-8)
3. **Implement `formatAppointmentTime()`** function in `src/utils/dateHelpers.js`:
   - Accept UTC timestamp string (ISO 8601 with 'Z')
   - Return properly formatted date/time in user's local timezone
   - Use JavaScript Date API methods like `toLocaleString()`, `toLocaleDateString()`, or `toLocaleTimeString()`
4. **Refactor `AppointmentCard.js`** to:
   - Import `formatAppointmentTime` from `../utils/dateHelpers`
   - Replace buggy code with call to utility function
   - Pass `appointment.scheduledTime` to the utility
5. **Save all files** (Ctrl+S)

## Key Concepts

- **UTC**: Universal Coordinated Time - timezone-agnostic standard
- **ISO 8601**: Standard format like "2024-03-15T17:00:00Z" (Z means UTC)
- **JavaScript Date**: Automatically handles timezone conversion when parsed correctly
- **toLocaleString()**: Converts to user's local timezone for display

## Buggy Code Pattern

The current code incorrectly strips the 'Z' timezone indicator: