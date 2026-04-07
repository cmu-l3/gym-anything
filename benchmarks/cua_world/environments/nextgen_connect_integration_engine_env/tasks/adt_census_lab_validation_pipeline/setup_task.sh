#!/bin/bash
echo "=== Setting up adt_census_lab_validation_pipeline task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_adt_pipeline_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_adt_pipeline_channel_count
echo "Initial channel count: $INITIAL_COUNT"

# ── Write sample HL7 messages ────────────────────────────────────────────────

# ADT A01 — Admit patient MRN-3001 to ICU
cat > /home/ga/sample_adt_a01_admit.hl7 << 'ENDHL7'
MSH|^~\&|RegSystem|MercyGeneral|NextGenConnect|HealthNet|20240315080000||ADT^A01^ADT_A01|ADT20240315001|P|2.5
EVN|A01|20240315080000
PID|1||MRN-3001^^^MercyGeneral^MR||VASQUEZ^ELENA^M||19720614|F|||890 WILLOW CREEK DR^^PORTLAND^OR^97205||5031234567
PV1|1|I|ICU^401^A^MercyGeneral||||1234^FOSTER^AMANDA^L^^^MD|||MED||||||||V100001^^^MercyGeneral^VN|||||||||||||||||||||||||20240315080000
ENDHL7

# ORU R01 — Critical BMP for admitted patient MRN-3001 (Potassium HH, Creatinine HH)
cat > /home/ga/sample_oru_critical.hl7 << 'ENDHL7'
MSH|^~\&|LabCore|RegionalLab|NextGenConnect|HealthNet|20240315103045||ORU^R01|LAB20240315002|P|2.5
PID|1||MRN-3001^^^MercyGeneral^MR||VASQUEZ^ELENA^M||19720614|F|||890 WILLOW CREEK DR^^PORTLAND^OR^97205||5031234567
OBR|1|ORD20240315002|LAB20240315002|BMP^Basic Metabolic Panel^L|||20240315093000|||||||||FOSTER^AMANDA^^^DR||||||20240315103045|||F
OBX|1|NM|2823-3^Potassium^LN||6.9|mEq/L|3.5-5.5|HH|||F|||20240315103045
OBX|2|NM|2951-2^Sodium^LN||141|mEq/L|136-145|N|||F|||20240315103045
OBX|3|NM|2160-0^Creatinine^LN||7.2|mg/dL|0.7-1.3|HH|||F|||20240315103045
OBX|4|NM|2339-0^Glucose^LN||105|mg/dL|70-110|N|||F|||20240315103045
ENDHL7

# ORU R01 — Lab for unknown patient MRN-9999 (should be REJECTED)
cat > /home/ga/sample_oru_unknown.hl7 << 'ENDHL7'
MSH|^~\&|LabCore|RegionalLab|NextGenConnect|HealthNet|20240315114500||ORU^R01|LAB20240315003|P|2.5
PID|1||MRN-9999^^^RegionalHealth^MR||UNKNOWN^PATIENT^X||19900101|M|||000 NOWHERE ST^^ANYTOWN^CA^90001||0000000000
OBR|1|ORD20240315003|LAB20240315003|CBC^Complete Blood Count^L|||20240315100000|||||||||SMITH^JOHN^^^DR||||||20240315114500|||F
OBX|1|NM|6690-2^WBC^LN||8.5|10*3/uL|4.5-11.0|N|||F|||20240315114500
ENDHL7

# ORU R01 — Normal CBC for admitted patient MRN-3001
cat > /home/ga/sample_oru_normal.hl7 << 'ENDHL7'
MSH|^~\&|LabCore|RegionalLab|NextGenConnect|HealthNet|20240315121530||ORU^R01|LAB20240315004|P|2.5
PID|1||MRN-3001^^^MercyGeneral^MR||VASQUEZ^ELENA^M||19720614|F|||890 WILLOW CREEK DR^^PORTLAND^OR^97205||5031234567
OBR|1|ORD20240315004|LAB20240315004|CBC^Complete Blood Count^L|||20240315110000|||||||||FOSTER^AMANDA^^^DR||||||20240315121530|||F
OBX|1|NM|6690-2^WBC^LN||7.8|10*3/uL|4.5-11.0|N|||F|||20240315121530
OBX|2|NM|789-8^RBC^LN||4.62|10*6/uL|4.2-5.9|N|||F|||20240315121530
ENDHL7

# ADT A03 — Discharge patient MRN-3001
cat > /home/ga/sample_adt_a03_discharge.hl7 << 'ENDHL7'
MSH|^~\&|RegSystem|MercyGeneral|NextGenConnect|HealthNet|20240316140000||ADT^A03^ADT_A03|ADT20240316001|P|2.5
EVN|A03|20240316140000
PID|1||MRN-3001^^^MercyGeneral^MR||VASQUEZ^ELENA^M||19720614|F|||890 WILLOW CREEK DR^^PORTLAND^OR^97205||5031234567
PV1|1|I|ICU^401^A^MercyGeneral||||1234^FOSTER^AMANDA^L^^^MD|||MED||||||||V100001^^^MercyGeneral^VN|||||||||||||||||||||||||20240315080000|20240316140000
ENDHL7

chown ga:ga /home/ga/sample_adt_a01_admit.hl7 /home/ga/sample_oru_critical.hl7 /home/ga/sample_oru_unknown.hl7 /home/ga/sample_oru_normal.hl7 /home/ga/sample_adt_a03_discharge.hl7
chmod 644 /home/ga/sample_adt_a01_admit.hl7 /home/ga/sample_oru_critical.hl7 /home/ga/sample_oru_unknown.hl7 /home/ga/sample_oru_normal.hl7 /home/ga/sample_adt_a03_discharge.hl7

echo "Sample HL7 messages written to /home/ga/"

# ── Open terminal with instructions ──────────────────────────────────────────

DISPLAY=:1 gnome-terminal --geometry=130x55+70+30 -- bash -c '
echo "================================================================"
echo " NextGen Connect - ADT Census + Lab Validation Pipeline"
echo "================================================================"
echo ""
echo "ARCHITECTURE:"
echo ""
echo "  Registration -(ADT A01/A03)-> [ADT_Census_Manager] (port 6661)"
echo "                                    |"
echo "                    A01: INSERT into active_census (status=active)"
echo "                    A03: UPDATE active_census (status=discharged)"
echo "                    Return: standard HL7 ACK"
echo ""
echo "  Lab Analyzers -(ORU^R01)----> [Lab_Results_Validator] (port 6662)"
echo "                                    |"
echo "                    JS Transformer: query active_census by PID-3.1"
echo "                    |"
echo "                    |- Patient active:"
echo "                    |    |- Enrich with department + physician"
echo "                    |    |- Channel Writer -> [Critical_Value_Processor]"
echo "                    |    |- Response: ACK MSA|AA|...|<department>"
echo "                    |"
echo "                    |- Patient NOT found or discharged:"
echo "                         |- DB Writer -> rejected_results"
echo "                         |- Response: NACK MSA|AR"
echo ""
echo "  [Critical_Value_Processor] (receives from Lab_Results_Validator)"
echo "    |- ALL results -> lab_results table"
echo "    |- OBX-8 = HH or LL -> critical_alerts table + JSON file"
echo ""
echo "BUILD ORDER (Channel Writer needs target UUID):"
echo "  1. Create + Deploy: Critical_Value_Processor (get its channel ID)"
echo "  2. Create + Deploy: Lab_Results_Validator (uses Processor ID)"
echo "  3. Create + Deploy: ADT_Census_Manager (independent)"
echo ""
echo "TABLES YOU MUST CREATE:"
echo "  active_census (mrn, patient_name, department, attending_physician,"
echo "                 status, admit_time, discharge_time)"
echo "  lab_results (mrn, test_code, result_value, units, abnormal_flag,"
echo "               physician, department, received_at)"
echo "  critical_alerts (mrn, test_code, result_value, physician,"
echo "                   department, flagged_at)"
echo "  rejected_results (mrn, raw_message, reason, rejected_at)"
echo ""
echo "SAMPLE MESSAGES (test in this order):"
echo "  1. /home/ga/sample_adt_a01_admit.hl7  (admit MRN-3001)"
echo "  2. /home/ga/sample_oru_critical.hl7   (MRN-3001, K=6.9 HH)"
echo "  3. /home/ga/sample_oru_unknown.hl7    (MRN-9999, REJECT)"
echo "  4. /home/ga/sample_oru_normal.hl7     (MRN-3001, all normal)"
echo "  5. /home/ga/sample_adt_a03_discharge.hl7 (discharge MRN-3001)"
echo ""
echo "REST API: https://localhost:8443/api | admin:admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "PostgreSQL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres  Password: postgres"
echo "  CLI: docker exec nextgen-postgres psql -U postgres -d mirthdb"
echo "================================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
