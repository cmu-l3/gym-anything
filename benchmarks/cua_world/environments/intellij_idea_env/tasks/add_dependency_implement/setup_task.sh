#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up add_dependency_implement task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing IntelliJ instances
pkill -f "idea" 2>/dev/null || true
sleep 2

PROJECT_DIR="/home/ga/IdeaProjects/student-records"

# Clean previous attempts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/export"
mkdir -p "$PROJECT_DIR/src/test/java/com/example/export"

# ========== pom.xml (NO Gson dependency) ==========
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>student-records</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <name>Student Records Manager</name>
    <description>A student records management system with JSON export capabilities</description>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- TODO: Add Google Gson dependency here for JSON serialization -->
        <!-- Hint: groupId=com.google.code.gson, artifactId=gson, version=2.10.1 -->

        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# ========== Student.java ==========
cat > "$PROJECT_DIR/src/main/java/com/example/model/Student.java" << 'JAVAEOF'
package com.example.model;

import java.util.Objects;

public class Student {
    private String studentId;
    private String firstName;
    private String lastName;
    private String email;
    private double gpa;

    public Student() {
    }

    public Student(String studentId, String firstName, String lastName, String email, double gpa) {
        this.studentId = studentId;
        this.firstName = firstName;
        this.lastName = lastName;
        this.email = email;
        this.gpa = gpa;
    }

    public String getStudentId() { return studentId; }
    public void setStudentId(String studentId) { this.studentId = studentId; }

    public String getFirstName() { return firstName; }
    public void setFirstName(String firstName) { this.firstName = firstName; }

    public String getLastName() { return lastName; }
    public void setLastName(String lastName) { this.lastName = lastName; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public double getGpa() { return gpa; }
    public void setGpa(double gpa) { this.gpa = gpa; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Student student = (Student) o;
        return Double.compare(student.gpa, gpa) == 0 &&
                Objects.equals(studentId, student.studentId) &&
                Objects.equals(firstName, student.firstName) &&
                Objects.equals(lastName, student.lastName) &&
                Objects.equals(email, student.email);
    }

    @Override
    public int hashCode() {
        return Objects.hash(studentId, firstName, lastName, email, gpa);
    }

    @Override
    public String toString() {
        return "Student{" +
                "studentId='" + studentId + '\'' +
                ", firstName='" + firstName + '\'' +
                ", lastName='" + lastName + '\'' +
                ", email='" + email + '\'' +
                ", gpa=" + gpa +
                '}';
    }
}
JAVAEOF

# ========== Course.java ==========
cat > "$PROJECT_DIR/src/main/java/com/example/model/Course.java" << 'JAVAEOF'
package com.example.model;

import java.util.Objects;

public class Course {
    private String courseId;
    private String courseName;
    private int credits;
    private String instructor;

    public Course() {
    }

    public Course(String courseId, String courseName, int credits, String instructor) {
        this.courseId = courseId;
        this.courseName = courseName;
        this.credits = credits;
        this.instructor = instructor;
    }

    public String getCourseId() { return courseId; }
    public void setCourseId(String courseId) { this.courseId = courseId; }

    public String getCourseName() { return courseName; }
    public void setCourseName(String courseName) { this.courseName = courseName; }

    public int getCredits() { return credits; }
    public void setCredits(int credits) { this.credits = credits; }

    public String getInstructor() { return instructor; }
    public void setInstructor(String instructor) { this.instructor = instructor; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Course course = (Course) o;
        return credits == course.credits &&
                Objects.equals(courseId, course.courseId) &&
                Objects.equals(courseName, course.courseName) &&
                Objects.equals(instructor, course.instructor);
    }

    @Override
    public int hashCode() {
        return Objects.hash(courseId, courseName, credits, instructor);
    }

    @Override
    public String toString() {
        return "Course{courseId='" + courseId + "', courseName='" + courseName +
                "', credits=" + credits + ", instructor='" + instructor + "'}";
    }
}
JAVAEOF

# ========== Enrollment.java ==========
cat > "$PROJECT_DIR/src/main/java/com/example/model/Enrollment.java" << 'JAVAEOF'
package com.example.model;

import java.util.Objects;

public class Enrollment {
    private Student student;
    private Course course;
    private String grade;
    private String semester;

    public Enrollment() {
    }

    public Enrollment(Student student, Course course, String grade, String semester) {
        this.student = student;
        this.course = course;
        this.grade = grade;
        this.semester = semester;
    }

    public Student getStudent() { return student; }
    public void setStudent(Student student) { this.student = student; }

    public Course getCourse() { return course; }
    public void setCourse(Course course) { this.course = course; }

    public String getGrade() { return grade; }
    public void setGrade(String grade) { this.grade = grade; }

    public String getSemester() { return semester; }
    public void setSemester(String semester) { this.semester = semester; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Enrollment that = (Enrollment) o;
        return Objects.equals(student, that.student) &&
                Objects.equals(course, that.course) &&
                Objects.equals(grade, that.grade) &&
                Objects.equals(semester, that.semester);
    }

    @Override
    public int hashCode() {
        return Objects.hash(student, course, grade, semester);
    }
}
JAVAEOF

# ========== RecordManager.java ==========
cat > "$PROJECT_DIR/src/main/java/com/example/service/RecordManager.java" << 'JAVAEOF'
package com.example.service;

import com.example.model.Course;
import com.example.model.Enrollment;
import com.example.model.Student;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

public class RecordManager {
    private final List<Student> students = new ArrayList<>();
    private final List<Course> courses = new ArrayList<>();
    private final List<Enrollment> enrollments = new ArrayList<>();

    public void addStudent(Student student) { students.add(student); }
    public void addCourse(Course course) { courses.add(course); }
    public void enrollStudent(Student student, Course course, String semester) {
        enrollments.add(new Enrollment(student, course, null, semester));
    }
    public Optional<Student> findStudentById(String studentId) {
        return students.stream().filter(s -> s.getStudentId().equals(studentId)).findFirst();
    }
    public List<Student> getAllStudents() { return new ArrayList<>(students); }
}
JAVAEOF

# ========== JsonExporter.java (SKELETON) ==========
cat > "$PROJECT_DIR/src/main/java/com/example/export/JsonExporter.java" << 'JAVAEOF'
package com.example.export;

import com.example.model.Student;

import java.io.IOException;
import java.util.List;

// TODO: Add the necessary import(s) for the Gson library

/**
 * Handles JSON serialization and deserialization of Student records.
 * 
 * This class uses the Google Gson library to convert between
 * Java objects and JSON format. Before implementing these methods,
 * ensure that the Gson dependency has been added to pom.xml:
 * 
 *   groupId: com.google.code.gson
 *   artifactId: gson
 *   version: 2.10.1
 */
public class JsonExporter {

    /**
     * Converts a list of Student objects to a JSON string.
     *
     * @param students the list of students to serialize
     * @return a JSON string representing the list of students
     */
    public String toJson(List<Student> students) {
        // TODO: Create a Gson instance and use it to serialize the students list to JSON
        throw new UnsupportedOperationException("Not implemented yet");
    }

    /**
     * Converts a JSON string back to a list of Student objects.
     *
     * @param json the JSON string to deserialize
     * @return a list of Student objects parsed from the JSON
     */
    public List<Student> fromJson(String json) {
        // TODO: Create a Gson instance and use it to deserialize the JSON string
        // Hint: You'll need to use TypeToken to handle the generic List<Student> type
        throw new UnsupportedOperationException("Not implemented yet");
    }

    /**
     * Exports a list of Student objects to a JSON file at the given path.
     *
     * @param students the list of students to export
     * @param filePath the path where the JSON file should be written
     * @throws IOException if an I/O error occurs while writing the file
     */
    public void exportToFile(List<Student> students, String filePath) throws IOException {
        // TODO: Convert students to JSON and write to the specified file
        throw new UnsupportedOperationException("Not implemented yet");
    }

    /**
     * Imports a list of Student objects from a JSON file at the given path.
     *
     * @param filePath the path to the JSON file to read
     * @return a list of Student objects read from the file
     * @throws IOException if an I/O error occurs while reading the file
     */
    public List<Student> importFromFile(String filePath) throws IOException {
        // TODO: Read JSON from the specified file and convert to a list of Students
        throw new UnsupportedOperationException("Not implemented yet");
    }
}
JAVAEOF

# ========== JsonExporterTest.java (Pre-written tests) ==========
cat > "$PROJECT_DIR/src/test/java/com/example/export/JsonExporterTest.java" << 'JAVAEOF'
package com.example.export;

import com.example.model.Student;
import org.junit.Before;
import org.junit.After;
import org.junit.Test;

import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.List;

import static org.junit.Assert.*;

public class JsonExporterTest {

    private JsonExporter exporter;
    private List<Student> testStudents;
    private static final String TEST_FILE = "/tmp/test_students_export.json";

    @Before
    public void setUp() {
        exporter = new JsonExporter();
        testStudents = Arrays.asList(
                new Student("S001", "Alice", "Johnson", "alice.johnson@university.edu", 3.85),
                new Student("S002", "Bob", "Smith", "bob.smith@university.edu", 3.42),
                new Student("S003", "Carol", "Williams", "carol.williams@university.edu", 3.91)
        );
    }

    @After
    public void tearDown() {
        File f = new File(TEST_FILE);
        if (f.exists()) f.delete();
    }

    @Test
    public void testToJson() {
        String json = exporter.toJson(testStudents);
        assertNotNull("JSON output should not be null", json);
        assertFalse("JSON output should not be empty", json.trim().isEmpty());
        assertTrue("JSON should contain Alice", json.contains("Alice"));
        assertTrue("JSON should contain Johnson", json.contains("Johnson"));
        assertTrue("JSON should contain S001", json.contains("S001"));
        assertTrue("JSON should contain Bob", json.contains("Bob"));
    }

    @Test
    public void testFromJson() {
        String json = exporter.toJson(testStudents);
        List<Student> deserialized = exporter.fromJson(json);
        assertNotNull("Deserialized list should not be null", deserialized);
        assertEquals("Deserialized list should have 3 students", 3, deserialized.size());
        
        Student alice = deserialized.stream().filter(s -> "S001".equals(s.getStudentId())).findFirst().orElse(null);
        assertNotNull("Should find student S001", alice);
        assertEquals("Alice", alice.getFirstName());
        assertEquals(3.85, alice.getGpa(), 0.001);
    }

    @Test
    public void testExportToFile() throws IOException {
        exporter.exportToFile(testStudents, TEST_FILE);
        File outputFile = new File(TEST_FILE);
        assertTrue("Output file should exist", outputFile.exists());
        assertTrue("Output file should not be empty", outputFile.length() > 0);
    }

    @Test
    public void testImportFromFile() throws IOException {
        exporter.exportToFile(testStudents, TEST_FILE);
        List<Student> imported = exporter.importFromFile(TEST_FILE);
        assertNotNull("Imported list should not be null", imported);
        assertEquals("Imported list should have 3 students", 3, imported.size());
        
        Student carol = imported.stream().filter(s -> "S003".equals(s.getStudentId())).findFirst().orElse(null);
        assertNotNull("Should find student S003", carol);
        assertEquals("Williams", carol.getLastName());
    }
}
JAVAEOF

chown -R ga:ga "$PROJECT_DIR"

# Pre-download Gson to Maven local repository
echo "Pre-downloading Gson..."
WARMUP_DIR=$(mktemp -d)
cat > "$WARMUP_DIR/pom.xml" << 'WPOM'
<project><modelVersion>4.0.0</modelVersion><groupId>tmp</groupId><artifactId>warmup</artifactId><version>1</version>
<dependencies><dependency><groupId>com.google.code.gson</groupId><artifactId>gson</artifactId><version>2.10.1</version></dependency></dependencies></project>
WPOM
cd "$WARMUP_DIR" && su - ga -c "cd $WARMUP_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn dependency:resolve -q" 2>/dev/null || true
rm -rf "$WARMUP_DIR"

# Record initial file states
md5sum "$PROJECT_DIR/pom.xml" > /tmp/initial_pom_sum.txt 2>/dev/null
md5sum "$PROJECT_DIR/src/main/java/com/example/export/JsonExporter.java" > /tmp/initial_impl_sum.txt 2>/dev/null

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "student-records" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="