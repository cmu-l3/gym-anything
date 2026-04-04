#!/bin/bash
set -e

echo "=== Setting up refactor_infer_generics task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define project paths
PROJECT_NAME="LegacyHospitalSystem"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Create project directory structure
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src/com/hospital/core"
chown -R ga:ga "$PROJECT_DIR"

# 1. Create .project file
cat > "$PROJECT_DIR/.project" << EOFPROJECT
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$PROJECT_NAME</name>
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
EOFPROJECT

# 2. Create .classpath file (Standard Java + JUnit 4)
cat > "$PROJECT_DIR/.classpath" << EOFCLASSPATH
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
	<classpathentry kind="con" path="org.eclipse.jdt.junit.JUNIT_CONTAINER/4"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOFCLASSPATH

# 3. Create Patient.java (POJO)
cat > "$PROJECT_DIR/src/com/hospital/core/Patient.java" << EOFJAVA
package com.hospital.core;

public class Patient {
    private String mrn;
    private String name;
    private int triageLevel;

    public Patient(String mrn, String name, int triageLevel) {
        this.mrn = mrn;
        this.name = name;
        this.triageLevel = triageLevel;
    }

    public String getMrn() { return mrn; }
    public String getName() { return name; }
    public int getTriageLevel() { return triageLevel; }
    
    @Override
    public String toString() {
        return "Patient{" + name + "}";
    }
}
EOFJAVA

# 4. Create AdmissionQueue.java (LEGACY CODE WITH RAW TYPES)
# This is the file the agent needs to refactor
cat > "$PROJECT_DIR/src/com/hospital/core/AdmissionQueue.java" << EOFJAVA
package com.hospital.core;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

public class AdmissionQueue {
    // Raw type usage - needs refactoring to List<Patient>
    private List waitingList = new ArrayList();

    public void addPatient(Patient p) {
        // Unchecked call to add(E) as a member of the raw type List
        waitingList.add(p);
    }

    public Patient getNextPatient() {
        if (waitingList.isEmpty()) {
            return null;
        }
        // Explicit cast required because waitingList is raw
        return (Patient) waitingList.remove(0);
    }
    
    public List getAllPatients() {
        // Raw type return
        return waitingList;
    }
    
    public void printQueue() {
        // Raw iterator
        Iterator it = waitingList.iterator();
        while (it.hasNext()) {
            // Explicit cast required
            Patient p = (Patient) it.next();
            System.out.println(p.getName());
        }
    }
}
EOFJAVA

# 5. Create AdmissionQueueTest.java (JUnit Test)
cat > "$PROJECT_DIR/src/com/hospital/core/AdmissionQueueTest.java" << EOFJAVA
package com.hospital.core;

import static org.junit.Assert.*;
import org.junit.Test;
import java.util.List;

public class AdmissionQueueTest {

    @Test
    public void testQueueOperations() {
        AdmissionQueue queue = new AdmissionQueue();
        Patient p1 = new Patient("MRN001", "John Doe", 1);
        Patient p2 = new Patient("MRN002", "Jane Smith", 2);
        
        queue.addPatient(p1);
        queue.addPatient(p2);
        
        // This cast logic is implicit in the test, but verifies the API works
        assertEquals("John Doe", queue.getNextPatient().getName());
        assertEquals("Jane Smith", queue.getNextPatient().getName());
        assertNull(queue.getNextPatient());
    }
}
EOFJAVA

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record file timestamp and initial content hash
TARGET_FILE="$PROJECT_DIR/src/com/hospital/core/AdmissionQueue.java"
md5sum "$TARGET_FILE" > /tmp/initial_hash.txt
date +%s > /tmp/task_start_time.txt

# Start Eclipse
echo "Starting Eclipse..."
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected, starting it..."
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data $WORKSPACE_DIR > /tmp/eclipse.log 2>&1 &"
    wait_for_eclipse 60
fi

# Focus Eclipse
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="