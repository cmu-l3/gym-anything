#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Timezone Display Bug Task ==="

WORKSPACE_DIR="/home/ga/workspace/appointment-booking"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/components"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/services"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create buggy AppointmentCard.js
cat > "$WORKSPACE_DIR/src/components/AppointmentCard.js" << 'EOF'
// src/components/AppointmentCard.js
import React from 'react';

export function AppointmentCard({ appointment }) {
  // BUG: This incorrectly handles timezones
  // The backend sends UTC strings like "2024-03-15T17:00:00Z"
  // But this code displays them as if they were local times
  const displayTime = appointment.scheduledTime.replace('Z', '');
  const dateObj = new Date(displayTime);
  
  return (
    <div className="appointment-card">
      <h3>Appointment Details</h3>
      <p>Patient: {appointment.patientName}</p>
      <p>Time: {dateObj.toTimeString()}</p>
      <p>Date: {dateObj.toDateString()}</p>
    </div>
  );
}
EOF

# Create incomplete dateHelpers.js
cat > "$WORKSPACE_DIR/src/utils/dateHelpers.js" << 'EOF'
// src/utils/dateHelpers.js
// This file exists but is mostly empty - needs a proper utility function

/**
 * Formats a UTC timestamp for display in user's local timezone
 * TODO: Implement this function properly!
 * 
 * @param {string} utcTimestamp - ISO 8601 UTC timestamp (e.g., "2024-03-15T17:00:00Z")
 * @returns {string} Formatted date and time in user's local timezone
 */
export function formatAppointmentTime(utcTimestamp) {
  // Empty implementation - needs to be written
  return "TODO";
}

export function getCurrentTimezone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}
EOF

# Create correct API service (for reference)
cat > "$WORKSPACE_DIR/src/services/appointmentService.js" << 'EOF'
// src/services/appointmentService.js
// This service correctly returns UTC timestamps from the backend

export async function fetchAppointments() {
  // Mock API response - backend correctly sends UTC times
  return [
    {
      id: "apt-12345",
      patientName: "Jane Doe",
      scheduledTime: "2024-03-15T17:00:00Z",  // 5 PM UTC
      duration: 30,
      doctorName: "Dr. Smith"
    },
    {
      id: "apt-67890",
      patientName: "John Smith",
      scheduledTime: "2024-03-16T14:00:00Z",  // 2 PM UTC
      duration: 45,
      doctorName: "Dr. Johnson"
    }
  ];
}
EOF

# Create package.json
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "appointment-booking",
  "version": "1.0.0",
  "description": "Healthcare appointment booking system",
  "main": "src/index.js",
  "scripts": {
    "test": "jest"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@testing-library/react": "^14.0.0",
    "jest": "^29.5.0"
  }
}
EOF

# Create README with problem description
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Appointment Booking System - Timezone Bug Fix

## 🐛 Current Issue: Timezone Display Bug

**Severity**: CRITICAL  
**Reported by**: Customer Support (multiple escalations)

### Problem Description

Patients in different timezones are seeing wildly incorrect appointment times in the frontend application:

**Examples of reported issues:**
- Los Angeles patient: Scheduled for 9:00 AM, confirmation shows 5:00 PM
- New York patient: Scheduled for 10:00 AM, confirmation shows 2:00 AM
- London patient: Scheduled for 3:00 PM, confirmation shows 10:00 PM

### Root Cause

The **backend correctly stores all appointments in UTC** (ISO 8601 format with 'Z' suffix).

Example backend response: