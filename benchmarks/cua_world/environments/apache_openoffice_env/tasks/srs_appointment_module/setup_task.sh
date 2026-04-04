#!/bin/bash
set -e
echo "=== Setting up SRS Appointment Module Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous artifacts
rm -f /home/ga/Documents/SRS_Appointment_Module_v1.odt 2>/dev/null || true
rm -f /home/ga/Documents/requirements_data.json 2>/dev/null || true

# Write the JSON data file
cat > /home/ga/Documents/requirements_data.json << 'JSONEOF'
{
  "document": {
    "id": "PHS-SRS-APT-2024-001",
    "title": "Software Requirements Specification: Patient Appointment Scheduling Module",
    "version": "1.0",
    "date": "2024-11-15",
    "product": "Integrated Care Platform (ICP) v4.2",
    "module": "Appointment Scheduling Module (ASM)"
  },
  "functional_requirements": [
    {"id": "REQ-F-001", "name": "Schedule New Appointment", "priority": "High", "description": "The system shall allow authorized users to schedule a new appointment by selecting patient, provider, and time slot."},
    {"id": "REQ-F-002", "name": "Cancel Appointment", "priority": "High", "description": "The system shall allow users to cancel appointments with a mandatory reason code."},
    {"id": "REQ-F-003", "name": "Reschedule Appointment", "priority": "High", "description": "The system shall allow rescheduling without deleting the original record linkage."},
    {"id": "REQ-F-004", "name": "Provider Availability", "priority": "High", "description": "The system shall allow management of provider schedules and time-off blocks."},
    {"id": "REQ-F-005", "name": "Waitlist Management", "priority": "Medium", "description": "The system shall automatically notify waitlisted patients when a matching slot opens."},
    {"id": "REQ-F-006", "name": "Recurring Series", "priority": "Medium", "description": "The system shall support recurring appointment patterns (daily, weekly, monthly)."},
    {"id": "REQ-F-007", "name": "Multi-Location Support", "priority": "High", "description": "The system shall prevent booking conflicts across different physical locations."},
    {"id": "REQ-F-008", "name": "Insurance Verification", "priority": "High", "description": "The system shall trigger real-time X12 270/271 eligibility checks."},
    {"id": "REQ-F-009", "name": "Appointment Types", "priority": "Medium", "description": "The system shall allow configuration of appointment durations and color codes."},
    {"id": "REQ-F-010", "name": "Patient Notifications", "priority": "High", "description": "The system shall send SMS/Email reminders 24h and 2h before appointments."},
    {"id": "REQ-F-011", "name": "Overbooking Controls", "priority": "Medium", "description": "The system shall restrict overbooking based on provider-specific rules."},
    {"id": "REQ-F-012", "name": "Analytics Dashboard", "priority": "Low", "description": "The system shall provide reports on utilization, no-shows, and cancellation rates."}
  ],
  "non_functional_requirements": [
    {"id": "REQ-NF-001", "category": "Performance", "description": "Pages load < 2s under normal load."},
    {"id": "REQ-NF-002", "category": "Security", "description": "HIPAA compliant encryption (AES-256) at rest."},
    {"id": "REQ-NF-003", "category": "Availability", "description": "99.9% uptime required."},
    {"id": "REQ-NF-004", "category": "Scalability", "description": "Support 10,000 concurrent users."},
    {"id": "REQ-NF-005", "category": "Accessibility", "description": "WCAG 2.1 Level AA compliant."},
    {"id": "REQ-NF-006", "category": "Audit", "description": "Immutable audit logs for 7 years."}
  ],
  "use_cases": [
    {"id": "UC-001", "name": "Schedule New Appointment", "actor": "Scheduler", "precondition": "Patient exists", "postcondition": "Appointment confirmed"},
    {"id": "UC-002", "name": "Cancel/Reschedule", "actor": "Scheduler", "precondition": "Appt exists", "postcondition": "Slot released"},
    {"id": "UC-003", "name": "Manage Waitlist", "actor": "System", "precondition": "Slot opens", "postcondition": "Patient notified"},
    {"id": "UC-004", "name": "Run Utilization Report", "actor": "Admin", "precondition": "Auth valid", "postcondition": "Report generated"}
  ],
  "external_interfaces": [
    {"id": "IF-001", "name": "EHR Integration", "protocol": "FHIR R4", "description": "Sync patient demographics and provider directory."},
    {"id": "IF-002", "name": "Insurance Clearinghouse", "protocol": "X12 270/271", "description": "Real-time eligibility verification."},
    {"id": "IF-003", "name": "Notification Gateway", "protocol": "REST API", "description": "Send SMS/Email via Twilio/SendGrid."}
  ],
  "data_dictionary": [
    {"entity": "Patient", "attributes": "id, mrn, name, dob, phone, email"},
    {"entity": "Provider", "attributes": "id, npi, name, specialty, locations"},
    {"entity": "Appointment", "attributes": "id, patient_id, provider_id, time, status, type"},
    {"entity": "Location", "attributes": "id, name, address, timezone"},
    {"entity": "InsurancePlan", "attributes": "id, payer_id, subscriber_id, effective_date"},
    {"entity": "WaitlistEntry", "attributes": "id, patient_id, preferences, priority"},
    {"entity": "RecurringSchedule", "attributes": "id, pattern, start_date, end_date"},
    {"entity": "AuditRecord", "attributes": "id, timestamp, user, action, old_val, new_val"}
  ]
}
JSONEOF

# Fix ownership
chown ga:ga /home/ga/Documents/requirements_data.json

# Record initial state
echo "0" > /tmp/initial_file_count
ls -la /home/ga/Documents/ > /tmp/initial_dir_state 2>&1 || true

# Start OpenOffice Writer
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "Window found."
            break
        fi
        sleep 1
    done
fi

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="