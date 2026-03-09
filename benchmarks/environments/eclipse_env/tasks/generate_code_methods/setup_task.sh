#!/bin/bash
set -e
echo "=== Setting up generate_code_methods task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ---- Create the EmployeeModel Maven project ----
PROJECT_DIR="/home/ga/eclipse-workspace/EmployeeModel"
# Clean up any previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/model"
mkdir -p "$PROJECT_DIR/.settings"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>employee-model</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>Employee Model</name>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# 2. Create Employee.java (INCOMPLETE - Fields only)
cat > "$PROJECT_DIR/src/main/java/com/example/model/Employee.java" << 'JAVAEOF'
package com.example.model;

/**
 * Employee data model class.
 * 
 * TODO: Use Eclipse Source menu to generate:
 * 1. Constructor using Fields (all fields)
 * 2. Getters and Setters (all fields)
 * 3. toString() (all fields)
 * 4. hashCode() and equals() (all fields)
 */
public class Employee {

    private String firstName;
    private String lastName;
    private int employeeId;
    private String department;
    private double salary;

}
JAVAEOF

# 3. Create EmployeeTest.java (COMPLETE - Tests expected methods)
cat > "$PROJECT_DIR/src/test/java/com/example/model/EmployeeTest.java" << 'TESTEOF'
package com.example.model;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

public class EmployeeTest {

    private Employee emp1;
    private Employee emp2;

    @BeforeEach
    void setUp() {
        // This constructor call will fail compilation until the agent generates it
        emp1 = new Employee("John", "Doe", 1001, "Engineering", 85000.0);
        emp2 = new Employee("John", "Doe", 1001, "Engineering", 85000.0);
    }

    @Test
    void testConstructorAndGetters() {
        assertEquals("John", emp1.getFirstName());
        assertEquals("Doe", emp1.getLastName());
        assertEquals(1001, emp1.getEmployeeId());
        assertEquals("Engineering", emp1.getDepartment());
        assertEquals(85000.0, emp1.getSalary(), 0.01);
    }

    @Test
    void testSetters() {
        emp1.setFirstName("Jane");
        assertEquals("Jane", emp1.getFirstName());
        emp1.setSalary(90000.0);
        assertEquals(90000.0, emp1.getSalary(), 0.01);
    }

    @Test
    void testEquals() {
        assertEquals(emp1, emp2);
        assertNotEquals(emp1, new Employee("Jane", "Doe", 1001, "Engineering", 85000.0));
    }

    @Test
    void testHashCode() {
        assertEquals(emp1.hashCode(), emp2.hashCode());
    }

    @Test
    void testToString() {
        String str = emp1.toString();
        assertTrue(str.contains("John") && str.contains("Doe") && str.contains("1001"), 
                   "toString should contain field values");
    }
}
TESTEOF

# 4. Create Eclipse Project Metadata (.project)
cat > "$PROJECT_DIR/.project" << 'PROJEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>EmployeeModel</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
PROJEOF

# 5. Create Eclipse Classpath (.classpath)
cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
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
CPEOF

# 6. Configure JDT Settings (Java 17)
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'JDTEOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
JDTEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record hash of initial Employee.java for anti-gaming verification
md5sum "$PROJECT_DIR/src/main/java/com/example/model/Employee.java" | awk '{print $1}' > /tmp/initial_employee_hash.txt

# Pre-warm Maven to avoid timeout
su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn dependency:resolve -q" || true

# Prepare Eclipse
# Ensure Eclipse is running
if ! pgrep -f eclipse > /dev/null; then
    echo "Starting Eclipse..."
    su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /dev/null 2>&1 &"
    wait_for_eclipse 60
fi

# Focus Eclipse
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="