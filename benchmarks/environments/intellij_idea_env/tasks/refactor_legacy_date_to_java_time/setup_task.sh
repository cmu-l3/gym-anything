#!/bin/bash
set -e
echo "=== Setting up task: refactor_legacy_date_to_java_time ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_NAME="flight-scheduler"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Generate Maven Project Structure
mkdir -p "$PROJECT_DIR/src/main/java/com/airlines/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/airlines/service"
mkdir -p "$PROJECT_DIR/src/test/java/com/airlines/service"

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.airlines</groupId>
  <artifactId>flight-scheduler</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
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
POM

# 3. Create Flight.java (Legacy Date)
cat > "$PROJECT_DIR/src/main/java/com/airlines/model/Flight.java" << 'JAVA'
package com.airlines.model;

import java.util.Date;

public class Flight {
    private String flightNumber;
    private Date departureTime;
    private Date arrivalTime;

    public Flight(String flightNumber, Date departureTime) {
        this.flightNumber = flightNumber;
        this.departureTime = departureTime;
    }

    public String getFlightNumber() {
        return flightNumber;
    }

    public Date getDepartureTime() {
        return departureTime;
    }

    public void setDepartureTime(Date departureTime) {
        this.departureTime = departureTime;
    }

    public Date getArrivalTime() {
        return arrivalTime;
    }

    public void setArrivalTime(Date arrivalTime) {
        this.arrivalTime = arrivalTime;
    }

    @Override
    public String toString() {
        return "Flight " + flightNumber + " departs at " + departureTime;
    }
}
JAVA

# 4. Create FlightScheduler.java (Legacy Calendar)
cat > "$PROJECT_DIR/src/main/java/com/airlines/service/FlightScheduler.java" << 'JAVA'
package com.airlines.service;

import com.airlines.model.Flight;
import java.util.Calendar;
import java.util.Date;

public class FlightScheduler {

    /**
     * Calculates the arrival time based on departure and duration in minutes.
     * Sets the arrival time on the flight object.
     */
    public void scheduleArrival(Flight flight, int durationMinutes) {
        if (flight.getDepartureTime() == null) {
            throw new IllegalArgumentException("Departure time cannot be null");
        }

        Date departure = flight.getDepartureTime();
        Calendar cal = Calendar.getInstance();
        cal.setTime(departure);
        cal.add(Calendar.MINUTE, durationMinutes);
        
        Date arrival = cal.getTime();
        flight.setArrivalTime(arrival);
    }
    
    /**
     * Checks if two flights have overlapping schedules.
     */
    public boolean isOverlapping(Flight f1, Flight f2) {
        if (f1.getArrivalTime() == null || f2.getArrivalTime() == null) {
            return false;
        }
        // Simple overlap logic: StartA < EndB && StartB < EndA
        return f1.getDepartureTime().before(f2.getArrivalTime()) && 
               f2.getDepartureTime().before(f1.getArrivalTime());
    }
}
JAVA

# 5. Create FlightSchedulerTest.java (Legacy Tests)
cat > "$PROJECT_DIR/src/test/java/com/airlines/service/FlightSchedulerTest.java" << 'JAVA'
package com.airlines.service;

import com.airlines.model.Flight;
import org.junit.Test;
import static org.junit.Assert.*;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;

public class FlightSchedulerTest {

    @Test
    public void testScheduleArrival() {
        FlightScheduler scheduler = new FlightScheduler();
        
        // Setup: 2023-10-01 14:00
        Calendar cal = new GregorianCalendar(2023, Calendar.OCTOBER, 1, 14, 0);
        Date departure = cal.getTime();
        
        Flight flight = new Flight("FA101", departure);
        
        // Action: 90 minute flight
        scheduler.scheduleArrival(flight, 90);
        
        // Verify: Should be 15:30
        assertNotNull(flight.getArrivalTime());
        
        Calendar arrivalCal = Calendar.getInstance();
        arrivalCal.setTime(flight.getArrivalTime());
        
        assertEquals(2023, arrivalCal.get(Calendar.YEAR));
        assertEquals(15, arrivalCal.get(Calendar.HOUR_OF_DAY));
        assertEquals(30, arrivalCal.get(Calendar.MINUTE));
    }
    
    @Test
    public void testOverlappingFlights() {
        FlightScheduler scheduler = new FlightScheduler();
        
        // Flight 1: 10:00 - 12:00
        Calendar c1 = new GregorianCalendar(2023, Calendar.OCTOBER, 1, 10, 0);
        Flight f1 = new Flight("F1", c1.getTime());
        scheduler.scheduleArrival(f1, 120);
        
        // Flight 2: 11:00 - 13:00 (Overlaps)
        Calendar c2 = new GregorianCalendar(2023, Calendar.OCTOBER, 1, 11, 0);
        Flight f2 = new Flight("F2", c2.getTime());
        scheduler.scheduleArrival(f2, 120);
        
        // Flight 3: 13:00 - 15:00 (No overlap)
        Calendar c3 = new GregorianCalendar(2023, Calendar.OCTOBER, 1, 13, 0);
        Flight f3 = new Flight("F3", c3.getTime());
        scheduler.scheduleArrival(f3, 120);
        
        assertTrue("F1 and F2 should overlap", scheduler.isOverlapping(f1, f2));
        assertFalse("F1 and F3 should not overlap", scheduler.isOverlapping(f1, f3));
    }
}
JAVA

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-compile to ensure everything starts in a working state (verifies setup is correct)
echo "Pre-compiling project..."
if su - ga -c "cd $PROJECT_DIR && mvn clean compile test -q"; then
    echo "Initial project compilation successful"
else
    echo "ERROR: Initial project setup failed compilation!"
    exit 1
fi

# Record initial file hashes for anti-gaming (to prove files were modified)
md5sum "$PROJECT_DIR/src/main/java/com/airlines/model/Flight.java" > /tmp/initial_flight_hash.txt
md5sum "$PROJECT_DIR/src/main/java/com/airlines/service/FlightScheduler.java" >> /tmp/initial_scheduler_hash.txt

# Launch IntelliJ
setup_intellij_project "$PROJECT_DIR" "flight-scheduler" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="