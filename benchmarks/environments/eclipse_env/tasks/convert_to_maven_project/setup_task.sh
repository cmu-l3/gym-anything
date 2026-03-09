#!/bin/bash
set -e
echo "=== Setting up convert_to_maven_project task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECT_NAME="DateUtilsLegacy"
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/$PROJECT_NAME"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"

# Create project structure
mkdir -p "$PROJECT_DIR/src/com/legacy/dateutils"
mkdir -p "$PROJECT_DIR/lib"
mkdir -p "$PROJECT_DIR/bin"

# ------------------------------------------------------------------
# Create Source Files (Inline generation to ensure self-contained)
# ------------------------------------------------------------------

# DateFormatter.java
cat > "$PROJECT_DIR/src/com/legacy/dateutils/DateFormatter.java" << 'JAVAEOF'
package com.legacy.dateutils;

import org.joda.time.DateTime;
import org.joda.time.DateTimeZone;
import org.joda.time.format.DateTimeFormat;
import org.joda.time.format.DateTimeFormatter;

public class DateFormatter {
    private static final DateTimeFormatter ISO_FORMAT = DateTimeFormat.forPattern("yyyy-MM-dd'T'HH:mm:ss");
    private static final DateTimeFormatter DISPLAY_FORMAT = DateTimeFormat.forPattern("MMMM dd, yyyy hh:mm a");

    public String toIsoString(DateTime dateTime) {
        if (dateTime == null) return "";
        return ISO_FORMAT.print(dateTime);
    }

    public String toDisplayString(DateTime dateTime) {
        if (dateTime == null) return "N/A";
        return DISPLAY_FORMAT.print(dateTime);
    }
}
JAVAEOF

# DateCalculator.java
cat > "$PROJECT_DIR/src/com/legacy/dateutils/DateCalculator.java" << 'JAVAEOF'
package com.legacy.dateutils;

import org.joda.time.DateTime;
import org.joda.time.Days;
import org.joda.time.Period;
import org.joda.time.PeriodType;

public class DateCalculator {
    public int daysBetween(DateTime start, DateTime end) {
        return Days.daysBetween(start.toLocalDate(), end.toLocalDate()).getDays();
    }

    public String getReadableDuration(DateTime start, DateTime end) {
        Period period = new Period(start, end, PeriodType.yearMonthDayTime());
        return period.getYears() + " years, " + period.getMonths() + " months, " + period.getDays() + " days";
    }
}
JAVAEOF

# App.java
cat > "$PROJECT_DIR/src/com/legacy/dateutils/App.java" << 'JAVAEOF'
package com.legacy.dateutils;

import org.joda.time.DateTime;
import org.joda.time.DateTimeZone;

public class App {
    public static void main(String[] args) {
        DateFormatter formatter = new DateFormatter();
        DateCalculator calculator = new DateCalculator();
        DateTime now = DateTime.now();
        System.out.println("Current time: " + formatter.toDisplayString(now));
    }
}
JAVAEOF

# ------------------------------------------------------------------
# Setup Manual Dependency (Joda-Time JAR)
# ------------------------------------------------------------------
JODA_JAR="$PROJECT_DIR/lib/joda-time-2.12.5.jar"

# Try to copy from pre-warmed maven repo or download
MAVEN_LOCAL="$HOME/.m2/repository/joda-time/joda-time/2.12.5/joda-time-2.12.5.jar"
GA_MAVEN="/home/ga/.m2/repository/joda-time/joda-time/2.12.5/joda-time-2.12.5.jar"

if [ -f "$MAVEN_LOCAL" ]; then
    cp "$MAVEN_LOCAL" "$JODA_JAR"
elif [ -f "$GA_MAVEN" ]; then
    cp "$GA_MAVEN" "$JODA_JAR"
else
    echo "Downloading Joda-Time JAR from Maven Central..."
    wget -q -O "$JODA_JAR" "https://repo1.maven.org/maven2/joda-time/joda-time/2.12.5/joda-time-2.12.5.jar"
fi

# ------------------------------------------------------------------
# Create Eclipse Metadata (.project and .classpath)
# ------------------------------------------------------------------

# .project - Plain Java Project
cat > "$PROJECT_DIR/.project" << 'PROJECTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>DateUtilsLegacy</name>
    <comment>Legacy date utilities project</comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
PROJECTEOF

# .classpath - Manual JAR reference
cat > "$PROJECT_DIR/.classpath" << 'CLASSPATHEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="lib" path="lib/joda-time-2.12.5.jar"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
CLASSPATHEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# ------------------------------------------------------------------
# Prepare Environment
# ------------------------------------------------------------------

# Ensure Eclipse is ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize Eclipse
focus_eclipse_window
sleep 2

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab

# Force Eclipse to recognize the new project
# Since we created it in the workspace folder, a refresh or import is often needed.
# For reliability, we'll try to trigger a refresh via xdotool F5 if possible,
# but often restarting Eclipse or relying on auto-refresh is standard.
# Here, we assume Eclipse is monitoring the workspace or the agent will File > Open.
# However, to be helpful, we simulate an Import > Existing Projects flow or just let it be.
# The most robust way for the AGENT is to see it. If it's in ~/eclipse-workspace, 
# Eclipse usually picks it up on restart or refresh. 
# We'll leave it in the workspace folder. The agent sees "DateUtilsLegacy" in the folder structure.

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project created at: $PROJECT_DIR"