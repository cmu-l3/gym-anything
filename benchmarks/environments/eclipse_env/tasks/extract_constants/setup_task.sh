#!/bin/bash
echo "=== Setting up extract_constants task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="PhysicsCalc"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Create project structure
mkdir -p "$PROJECT_DIR/src/main/java/com/physicscalc"
mkdir -p "$PROJECT_DIR/src/test/java/com/physicscalc"
chown -R ga:ga "$WORKSPACE_DIR"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.physicscalc</groupId>
  <artifactId>physics-calc</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-api</artifactId>
      <version>5.10.0</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter-engine</artifactId>
      <version>5.10.0</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOFPOM

# 2. Create PhysicsConstants.java (with magic numbers)
cat > "$PROJECT_DIR/src/main/java/com/physicscalc/PhysicsConstants.java" << 'EOFJAVA'
package com.physicscalc;

public class PhysicsConstants {
    
    public double calculateWeight(double mass) {
        // Calculate weight on Earth
        return mass * 9.80665;
    }

    public double calculateEnergy(double mass) {
        // E = mc^2
        return mass * 299792458.0 * 299792458.0;
    }

    public double calculateGasEnergy(double temperature) {
        // E = kT (Boltzmann constant)
        return 1.380649e-23 * temperature;
    }
    
    public double molesToAtoms(double moles) {
        // Avogadro's number
        return moles * 6.02214076e23;
    }
}
EOFJAVA

# 3. Create UnitConverter.java (with magic numbers)
cat > "$PROJECT_DIR/src/main/java/com/physicscalc/UnitConverter.java" << 'EOFJAVA'
package com.physicscalc;

public class UnitConverter {
    
    public double milesToKm(double miles) {
        return miles * 1.60934;
    }

    public double poundsToKg(double pounds) {
        return pounds * 0.453592;
    }

    public double celsiusToFahrenheit(double celsius) {
        return (celsius * 1.8) + 32.0;
    }
    
    public double feetToMeters(double feet) {
        return feet * 0.3048;
    }
}
EOFJAVA

# 4. Create OrbitalMechanics.java (with magic numbers)
cat > "$PROJECT_DIR/src/main/java/com/physicscalc/OrbitalMechanics.java" << 'EOFJAVA'
package com.physicscalc;

public class OrbitalMechanics {
    
    public double orbitalVelocity(double radius) {
        // v = sqrt(GM / r) for Earth
        // GM = 3.986004418e14
        return Math.sqrt(3.986004418e14 / radius);
    }

    public double altitudeToRadius(double altitude) {
        // Earth radius = 6371000 meters
        return 6371000.0 + altitude;
    }
    
    public double daysToSeconds(double days) {
        return days * 86400.0;
    }
}
EOFJAVA

# 5. Create NetworkConfig.java (with magic numbers)
cat > "$PROJECT_DIR/src/main/java/com/physicscalc/NetworkConfig.java" << 'EOFJAVA'
package com.physicscalc;

public class NetworkConfig {
    
    public int getDefaultPort() {
        return 8080;
    }

    public int getConnectionTimeout() {
        return 30000;
    }
    
    public int getMaxRetries() {
        return 3;
    }
    
    public int getBufferSize() {
        return 8192;
    }
}
EOFJAVA

# 6. Create Tests (PhysicsCalcTest.java)
cat > "$PROJECT_DIR/src/test/java/com/physicscalc/PhysicsCalcTest.java" << 'EOFJAVA'
package com.physicscalc;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class PhysicsCalcTest {

    @Test
    void testPhysicsConstants() {
        PhysicsConstants pc = new PhysicsConstants();
        assertEquals(98.0665, pc.calculateWeight(10), 0.0001);
        assertEquals(8.987551787e16, pc.calculateEnergy(1), 1e10);
        assertEquals(4.141947e-21, pc.calculateGasEnergy(300), 1e-25);
    }

    @Test
    void testUnitConverter() {
        UnitConverter uc = new UnitConverter();
        assertEquals(16.0934, uc.milesToKm(10), 0.0001);
        assertEquals(4.53592, uc.poundsToKg(10), 0.0001);
        assertEquals(212.0, uc.celsiusToFahrenheit(100), 0.001);
    }

    @Test
    void testOrbital() {
        OrbitalMechanics om = new OrbitalMechanics();
        assertEquals(6381000.0, om.altitudeToRadius(10000), 1.0);
        // Velocity at low earth orbit (approx)
        double radius = 6371000 + 400000; // 400km altitude
        double v = om.orbitalVelocity(radius);
        assertTrue(v > 7600 && v < 7700);
    }
    
    @Test
    void testConfig() {
        NetworkConfig nc = new NetworkConfig();
        assertEquals(8080, nc.getDefaultPort());
        assertEquals(3, nc.getMaxRetries());
    }
}
EOFJAVA

# Create Eclipse metadata (.project, .classpath)
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>PhysicsCalc</name>
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
EOFPROJECT

cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
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
EOFCLASSPATH

# Create JDT settings to ensure compliance 17
mkdir -p "$PROJECT_DIR/.settings"
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'EOFPREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
EOFPREFS

chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab
focus_eclipse_window
sleep 2

# Maximize Eclipse
DISPLAY=:1 wmctrl -r "Eclipse" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Record file timestamps and checksums for anti-gaming
date +%s > /tmp/task_start_time.txt
for f in PhysicsConstants.java UnitConverter.java OrbitalMechanics.java NetworkConfig.java; do
    sha256sum "$PROJECT_DIR/src/main/java/com/physicscalc/$f" >> /tmp/initial_checksums.txt
done

echo "=== Task setup complete ==="