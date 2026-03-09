#!/bin/bash
set -e
echo "=== Setting up implement_builder_pattern task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/eclipse-workspace/hr-core"
mkdir -p "$PROJECT_DIR/src/main/java/com/acme/hr/model"
mkdir -p "$PROJECT_DIR/src/test/java/com/acme/hr/model"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOFPOM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.acme.hr</groupId>
    <artifactId>hr-core</artifactId>
    <version>1.0.0-SNAPSHOT</version>
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
EOFPOM

# 2. Create Employee.java (Initial State)
cat > "$PROJECT_DIR/src/main/java/com/acme/hr/model/Employee.java" << 'EOFJAVA'
package com.acme.hr.model;

/**
 * Represents an employee in the ACME HR system.
 * 
 * TODO: Implement the Builder pattern for this class.
 *       The Builder should be a public static inner class
 *       with fluent setter methods and a build() method.
 */
public class Employee {

    private long id;
    private String firstName;
    private String lastName;
    private String email;
    private String department;
    private String position;
    private double salary;
    private String hireDate;
    private boolean active;
    private String phoneNumber;
    private String address;
    private String managerId;

    public long getId() { return id; }
    public String getFirstName() { return firstName; }
    public String getLastName() { return lastName; }
    public String getEmail() { return email; }
    public String getDepartment() { return department; }
    public String getPosition() { return position; }
    public double getSalary() { return salary; }
    public String getHireDate() { return hireDate; }
    public boolean isActive() { return active; }
    public String getPhoneNumber() { return phoneNumber; }
    public String getAddress() { return address; }
    public String getManagerId() { return managerId; }
}
EOFJAVA

# 3. Create Eclipse project metadata (Simulates "Imported Project")
# .project
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>hr-core</name>
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

# .classpath
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

# .settings (Compiler prefs)
mkdir -p "$PROJECT_DIR/.settings"
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'EOFJDT'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
EOFJDT

# Fix ownership
chown -R ga:ga "$PROJECT_DIR"

# 4. Start Eclipse and open the file
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
dismiss_dialogs 3
close_welcome_tab
focus_eclipse_window
sleep 2

# Open Employee.java in the editor
echo "Opening Employee.java..."
# Use eclipse command line to open file if possible, or just rely on project explorer navigation by agent.
# Ideally, we set the initial view.
# We can use xdg-open which delegates to Eclipse if running
su - ga -c "DISPLAY=:1 xdg-open $PROJECT_DIR/src/main/java/com/acme/hr/model/Employee.java" || true
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="