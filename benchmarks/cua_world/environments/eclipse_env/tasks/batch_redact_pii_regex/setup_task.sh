#!/bin/bash
set -e
echo "=== Setting up batch_redact_pii_regex task ==="

source /workspace/scripts/task_utils.sh

# Define paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/PatientConnector"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/medsoft/connector"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/logs"

# 1. Create Project Metadata (.project)
cat > "$PROJECT_DIR/.project" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>PatientConnector</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# 2. Create Classpath (.classpath)
cat > "$PROJECT_DIR/.classpath" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src/main/java"/>
	<classpathentry kind="src" path="src/main/resources"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 3. Create Source Files with PII
# Total SSNs: 15
# Total MRNs: 10

# File A: Java Class (SSNs: 5, MRNs: 3)
cat > "$PROJECT_DIR/src/main/java/com/medsoft/connector/TestPatient.java" <<EOF
package com.medsoft.connector;

public class TestPatient {
    // TODO: Remove test user (SSN: 234-56-7890) before production
    private String testSsn = "123-45-6789"; 
    private String secondarySsn = "987-65-4321";
    
    // Legacy mapping for MRN-102938
    public String getIdentifier() {
        return "MRN-839201"; 
    }
    
    public void validate() {
        String invalid = "000-00-0000"; // Dummy
        // Processing MRN-112233
        System.out.println("Validating user 456-78-1234...");
        String deepHidden = "User[555-55-5555]";
    }
}
EOF

# File B: Properties file (SSNs: 3, MRNs: 3)
cat > "$PROJECT_DIR/src/main/resources/config.properties" <<EOF
# Database Configuration
db.url=jdbc:mysql://localhost:3306/patients
db.user=admin
# Last tested with patient MRN-556677
test.case.primary=MRN-998877
test.case.secondary=MRN-112233
# Emergency contact SSN: 333-22-1111 (Dr. Smith)
contact.phone=555-0199
debug.user.ssn=999-00-1234
backup.admin.ssn=111-22-3333
EOF

# File C: XML Data (SSNs: 4, MRNs: 2)
cat > "$PROJECT_DIR/src/main/resources/import_batch.xml" <<EOF
<patients>
    <patient>
        <id>1</id>
        <mrn>MRN-445566</mrn>
        <ssn>666-55-4444</ssn>
    </patient>
    <patient>
        <id>2</id>
        <!-- Use MRN-778899 for failure testing -->
        <ssn>111-22-3333</ssn>
        <dependents>
            <ssn>888-88-8888</ssn>
            <ssn>777-77-7777</ssn>
        </dependents>
    </patient>
</patients>
EOF

# File D: Log File (SSNs: 3, MRNs: 2)
cat > "$PROJECT_DIR/logs/server.log" <<EOF
INFO  [main] Connector - Starting import for MRN-654321
WARN  [main] Connector - SSN 999-88-7777 format questionable
ERROR [main] Connector - Duplicate record found: MRN-123123
DEBUG [main] Connector - Raw payload: { ssn: "444-33-2222", name: "Doe" }
DEBUG [main] Connector - Previous payload: { ssn: "321-65-9876", name: "Smith" }
EOF

# File E: Readme (No PII, just instructions)
cat > "$PROJECT_DIR/README.md" <<EOF
# Patient Connector

## Testing
Please ensure all sensitive data is redacted before committing.
Use placeholders XXX-XX-XXXX and MRN-000000.
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Eclipse and load project
# We use a trick to force Eclipse to refresh/recognize the project if it's already open
# or just ensure it's there when it starts.
# Since the workspace dir is mounted/persisted, we just need to restart Eclipse or refresh.
# For this env, we'll rely on Eclipse startup scanning the workspace or user doing Import.
# But to be safe, we'll wait for Eclipse to be up.

wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="