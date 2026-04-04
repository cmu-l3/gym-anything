#!/bin/bash
set -e
echo "=== Setting up FRS Patient Portal Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create directory structure
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean up artifacts from previous runs
rm -f /home/ga/Documents/FRS-PC3-2024-012.odt 2>/dev/null || true
rm -f /home/ga/Documents/patientconnect_requirements.json 2>/dev/null || true

# 3. Generate the realistic JSON data file
echo "Generating requirements data file..."
cat > /home/ga/Documents/patientconnect_requirements.json << 'EOF'
{
  "document_metadata": {
    "number": "FRS-PC3-2024-012",
    "title": "Functional Requirements Specification — PatientConnect 3.0",
    "revision": "1.0",
    "date": "2024-11-15",
    "status": "Draft"
  },
  "project_info": {
    "name": "PatientConnect 3.0",
    "company": "Pinnacle Health Informatics, Inc.",
    "description": "Next-generation patient engagement portal compliant with 21st Century Cures Act."
  },
  "functional_requirements": {
    "FR-AUTH": {
      "module": "Authentication & Identity",
      "items": [
        {"id": "FR-AUTH-01", "priority": "High", "desc": "System shall support Multi-Factor Authentication (MFA) using SMS or Authenticator app."},
        {"id": "FR-AUTH-02", "priority": "High", "desc": "System shall support Single Sign-On (SSO) via SAML 2.0 for enterprise staff."},
        {"id": "FR-AUTH-03", "priority": "Medium", "desc": "System shall enforce NIST 800-63B identity proofing standards for new patient registration."},
        {"id": "FR-AUTH-04", "priority": "Low", "desc": "System shall support biometric login (FaceID/TouchID) on supported mobile devices."},
        {"id": "FR-AUTH-05", "priority": "High", "desc": "Session timeout shall occur after 15 minutes of inactivity."}
      ]
    },
    "FR-APPT": {
      "module": "Appointment Scheduling",
      "items": [
        {"id": "FR-APPT-01", "priority": "High", "desc": "System shall query real-time slot availability using HL7 FHIR Slot resources."},
        {"id": "FR-APPT-02", "priority": "Medium", "desc": "Patients shall be able to book appointments across multiple provider locations."},
        {"id": "FR-APPT-03", "priority": "Low", "desc": "System shall offer a waitlist option for fully booked slots."},
        {"id": "FR-APPT-04", "priority": "High", "desc": "Automated confirmations shall be sent via SMS/Email upon booking."},
        {"id": "FR-APPT-05", "priority": "High", "desc": "System shall integrate with Zoom API for telehealth visits."}
      ]
    },
    "FR-MR": {
      "module": "Medical Records",
      "items": [
        {"id": "FR-MR-01", "priority": "High", "desc": "System shall display USCDI v3 core data classes including vitals, labs, and immunizations."},
        {"id": "FR-MR-02", "priority": "High", "desc": "Lab results shall verify against reference ranges and flag abnormal values."},
        {"id": "FR-MR-03", "priority": "Medium", "desc": "System shall include a zero-footprint DICOM viewer for radiology images."},
        {"id": "FR-MR-04", "priority": "High", "desc": "Medication list shall display RxNorm codes and interaction warnings."},
        {"id": "FR-MR-05", "priority": "Medium", "desc": "Patients shall be able to download their record as a C-CDA 2.1 XML file."}
      ]
    },
    "FR-MSG": {
      "module": "Secure Messaging",
      "items": [
        {"id": "FR-MSG-01", "priority": "High", "desc": "System shall support asynchronous secure messaging between patient and provider."},
        {"id": "FR-MSG-02", "priority": "Medium", "desc": "Messages shall be logically routed to care teams based on provider specialty."},
        {"id": "FR-MSG-03", "priority": "Low", "desc": "System shall support file attachments up to 25MB (PDF, JPG, PNG)."},
        {"id": "FR-MSG-04", "priority": "Medium", "desc": "System shall provide read receipts for sent messages."},
        {"id": "FR-MSG-05", "priority": "High", "desc": "System shall flag urgent keywords and display a warning to call 911."}
      ]
    },
    "FR-BILL": {
      "module": "Billing & Payments",
      "items": [
        {"id": "FR-BILL-01", "priority": "High", "desc": "System shall display Explanation of Benefits (EOB) documents."},
        {"id": "FR-BILL-02", "priority": "High", "desc": "Payments shall be processed via PCI DSS Level 1 compliant gateway."},
        {"id": "FR-BILL-03", "priority": "Medium", "desc": "Patients shall be able to set up recurring payment plans."},
        {"id": "FR-BILL-04", "priority": "High", "desc": "System shall verify insurance eligibility via X12 270/271 transactions."},
        {"id": "FR-BILL-05", "priority": "Low", "desc": "System shall provide a cost estimator for common procedures."}
      ]
    }
  },
  "non_functional_requirements": [
    {"id": "NFR-PERF-01", "category": "Performance", "desc": "Page load time shall be ≤ 2 seconds for 95% of requests."},
    {"id": "NFR-SEC-01", "category": "Security", "desc": "Data at rest shall be encrypted using AES-256."},
    {"id": "NFR-ACC-01", "category": "Accessibility", "desc": "UI shall comply with WCAG 2.1 Level AA standards."},
    {"id": "NFR-INT-01", "category": "Interoperability", "desc": "API shall conform to HL7 FHIR R4 standard."}
  ],
  "external_interfaces": [
    {"id": "IF-01", "system": "Epic EHR", "protocol": "FHIR R4 / CDS Hooks"},
    {"id": "IF-02", "system": "Twilio", "protocol": "REST API (SMS)"},
    {"id": "IF-03", "system": "Stripe Connect", "protocol": "REST API (Payments)"}
  ]
}
EOF
chown ga:ga /home/ga/Documents/patientconnect_requirements.json

# 4. Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenOffice Writer
# We launch it so the agent doesn't have to wait for startup, 
# ensuring they can start working immediately.
echo "Launching OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "OpenOffice Writer started."
            break
        fi
        sleep 1
    done
fi

# 6. Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="