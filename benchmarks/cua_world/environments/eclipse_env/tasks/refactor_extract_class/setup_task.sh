#!/bin/bash
set -e
echo "=== Setting up refactor_extract_class task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_NAME="MedTechCore"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Clean up any previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Create project directories
mkdir -p "$PROJECT_DIR/src/main/java/com/medtech/device"
mkdir -p "$PROJECT_DIR/src/test/java/com/medtech/device"
mkdir -p "$PROJECT_DIR/.settings"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.medtech</groupId>
  <artifactId>MedTechCore</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# 2. Create the "God Class" (RadiationTreatmentUnit.java)
cat > "$PROJECT_DIR/src/main/java/com/medtech/device/RadiationTreatmentUnit.java" << 'EOF'
package com.medtech.device;

/**
 * Represents a Linear Accelerator (LINAC) used for radiation therapy.
 * Stores device specifications, calibration data, and network connection details.
 */
public class RadiationTreatmentUnit {

    // Device Identity
    private String serialNumber;
    private String modelName;
    
    // Network Connection Details (To be extracted)
    private String ipAddress;
    private int port;
    private String protocol;
    private int connectionTimeout; // in milliseconds
    
    // Calibration Data
    private double maxEnergyMv;
    private long lastCalibrationTimestamp;
    
    public RadiationTreatmentUnit(String serialNumber, String modelName) {
        this.serialNumber = serialNumber;
        this.modelName = modelName;
        // Default network settings
        this.ipAddress = "192.168.1.100";
        this.port = 8080;
        this.protocol = "HTTPS";
        this.connectionTimeout = 5000;
    }
    
    // --- Device Identity Methods ---
    
    public String getSerialNumber() {
        return serialNumber;
    }
    
    public String getModelName() {
        return modelName;
    }
    
    // --- Network Methods (These use the fields to be extracted) ---
    
    public String getConnectionString() {
        return String.format("%s://%s:%d", protocol, ipAddress, port);
    }
    
    public void configureNetwork(String ip, int port, String proto) {
        this.ipAddress = ip;
        this.port = port;
        this.protocol = proto;
    }
    
    public boolean isNetworkReady() {
        return ipAddress != null && !ipAddress.isEmpty() && port > 0;
    }
    
    public int getPort() {
        return port;
    }
    
    public String getIpAddress() {
        return ipAddress;
    }
    
    // --- Calibration Methods ---
    
    public void calibrate(double energy) {
        this.maxEnergyMv = energy;
        this.lastCalibrationTimestamp = System.currentTimeMillis();
    }
    
    public double getMaxEnergy() {
        return maxEnergyMv;
    }
}
EOF

# 3. Create the Test Class
cat > "$PROJECT_DIR/src/test/java/com/medtech/device/RadiationTreatmentUnitTest.java" << 'EOF'
package com.medtech.device;

import static org.junit.Assert.*;
import org.junit.Test;

public class RadiationTreatmentUnitTest {

    @Test
    public void testDeviceIdentity() {
        RadiationTreatmentUnit unit = new RadiationTreatmentUnit("SN-1001", "Varian-X");
        assertEquals("SN-1001", unit.getSerialNumber());
        assertEquals("Varian-X", unit.getModelName());
    }
    
    @Test
    public void testNetworkConfiguration() {
        RadiationTreatmentUnit unit = new RadiationTreatmentUnit("SN-1002", "Elekta-Y");
        
        // Test default
        assertEquals("HTTPS://192.168.1.100:8080", unit.getConnectionString());
        
        // Reconfigure
        unit.configureNetwork("10.0.0.50", 9090, "TCP");
        
        assertEquals("TCP://10.0.0.50:9090", unit.getConnectionString());
        assertTrue(unit.isNetworkReady());
    }
    
    @Test
    public void testCalibration() {
        RadiationTreatmentUnit unit = new RadiationTreatmentUnit("SN-1003", "CyberKnife");
        unit.calibrate(6.0);
        assertEquals(6.0, unit.getMaxEnergy(), 0.001);
    }
}
EOF

# 4. Create Eclipse Metadata (.project and .classpath)
# This allows Eclipse to recognize the project immediately without manual import wizard steps
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>MedTechCore</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
            <attribute name="test" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# Set JDT preferences to match Java 17
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'EOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
EOF

# Set Ownership
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Eclipse and wait
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="