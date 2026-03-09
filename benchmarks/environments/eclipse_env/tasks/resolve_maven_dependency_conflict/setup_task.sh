#!/bin/bash
set -e
echo "=== Setting up resolve_maven_dependency_conflict task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="DoseCalcService"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# 1. Create Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/healthcare/dose"
mkdir -p "$PROJECT_DIR/src/test/java/com/healthcare/dose"
mkdir -p "$PROJECT_DIR/.settings"

# 2. Create pom.xml with the conflict
# We include httpclient (brings commons-logging) and jcl-over-slf4j (replacement)
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.healthcare</groupId>
  <artifactId>DoseCalcService</artifactId>
  <version>1.0-SNAPSHOT</version>
  <packaging>jar</packaging>

  <name>DoseCalcService</name>
  <url>http://maven.apache.org</url>

  <properties>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>

  <dependencies>
    <!-- This dependency transitively brings in commons-logging -->
    <dependency>
      <groupId>org.apache.httpcomponents</groupId>
      <artifactId>httpclient</artifactId>
      <version>4.5.13</version>
    </dependency>
    
    <!-- We want to use SLF4J instead -->
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>jcl-over-slf4j</artifactId>
      <version>1.7.32</version>
    </dependency>
    <dependency>
      <groupId>org.slf4j</groupId>
      <artifactId>slf4j-api</artifactId>
      <version>1.7.32</version>
    </dependency>
    
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.11</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POMEOF

# 3. Create a Java source file
cat > "$PROJECT_DIR/src/main/java/com/healthcare/dose/App.java" << 'JAVAEOF'
package com.healthcare.dose;

import org.apache.http.client.HttpClient;
import org.apache.http.impl.client.HttpClients;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class App {
    private static final Logger logger = LoggerFactory.getLogger(App.class);

    public static void main(String[] args) {
        logger.info("Starting DoseCalcService...");
        HttpClient client = HttpClients.createDefault();
        System.out.println("Client created: " + client);
    }
}
JAVAEOF

# 4. Create Eclipse Metadata (.project, .classpath, .settings)
# This ensures the project appears "Imported" when Eclipse starts

cat > "$PROJECT_DIR/.project" << 'PROJECTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>DoseCalcService</name>
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
PROJECTEOF

cat > "$PROJECT_DIR/.classpath" << 'CLASSPATHEOF'
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
CLASSPATHEOF

cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" << 'PREFSEOF'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
PREFSEOF

chown -R ga:ga "$PROJECT_DIR"

# 5. Start Eclipse
# We start Eclipse normally; it should pick up the project in the workspace
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Force Eclipse to refresh workspace/indexes (sometimes needed for new files)
# Ctrl+F5 is 'Update Project' in some contexts, but just opening it is usually enough.
# We'll rely on the agent to navigate.

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="