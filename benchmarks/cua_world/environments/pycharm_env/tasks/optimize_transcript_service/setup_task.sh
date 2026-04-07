#!/bin/bash
set -e
echo "=== Setting up optimize_transcript_service ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="optimize_transcript_service"
PROJECT_DIR="/home/ga/PycharmProjects/transcript_engine"

# Clean up any previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_* 2>/dev/null || true

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/services $PROJECT_DIR/tests $PROJECT_DIR/data $PROJECT_DIR/models"

# Record start timestamp
date +%s > /tmp/task_start_time.txt

# --- 1. Create Data Generator and Schema ---
cat > "$PROJECT_DIR/create_db.py" << 'PYEOF'
import os
import random
from sqlalchemy import create_engine, Column, Integer, String, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, relationship

Base = declarative_base()

class Department(Base):
    __tablename__ = 'departments'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    code = Column(String)
    courses = relationship("Course", back_populates="department")
    instructors = relationship("Instructor", back_populates="department")

class Instructor(Base):
    __tablename__ = 'instructors'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    department_id = Column(Integer, ForeignKey('departments.id'))
    department = relationship("Department", back_populates="instructors")

class Course(Base):
    __tablename__ = 'courses'
    id = Column(Integer, primary_key=True)
    title = Column(String)
    code = Column(String)
    credits = Column(Integer)
    department_id = Column(Integer, ForeignKey('departments.id'))
    department = relationship("Department", back_populates="courses")

class Student(Base):
    __tablename__ = 'students'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    email = Column(String)
    enrollments = relationship("Enrollment", back_populates="student")

class Enrollment(Base):
    __tablename__ = 'enrollments'
    id = Column(Integer, primary_key=True)
    student_id = Column(Integer, ForeignKey('students.id'))
    course_id = Column(Integer, ForeignKey('courses.id'))
    instructor_id = Column(Integer, ForeignKey('instructors.id'))
    semester = Column(String)
    grade = Column(String)
    
    student = relationship("Student", back_populates="enrollments")
    course = relationship("Course")
    instructor = relationship("Instructor")

def init_db():
    db_path = os.path.join(os.path.dirname(__file__), 'data', 'university.db')
    engine = create_engine(f'sqlite:///{db_path}')
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    # Create Departments
    depts = [
        Department(name="Computer Science", code="CS"),
        Department(name="Mathematics", code="MATH"),
        Department(name="Physics", code="PHYS"),
        Department(name="History", code="HIST"),
        Department(name="Literature", code="LIT")
    ]
    session.add_all(depts)
    session.commit()

    # Create Instructors
    instructors = []
    first_names = ["Alice", "Bob", "Charlie", "Diana", "Evan", "Fiona", "George"]
    last_names = ["Smith", "Johnson", "Williams", "Jones", "Brown", "Davis"]
    for i in range(20):
        dept = random.choice(depts)
        inst = Instructor(name=f"{random.choice(first_names)} {random.choice(last_names)}", department=dept)
        instructors.append(inst)
    session.add_all(instructors)
    session.commit()

    # Create Courses
    courses = []
    titles = ["Intro to", "Advanced", "Principles of", "Foundations of", "Applied"]
    for i in range(50):
        dept = random.choice(depts)
        title = f"{random.choice(titles)} {dept.name} {i+100}"
        course = Course(title=title, code=f"{dept.code}{i+100}", credits=3, department=dept)
        courses.append(course)
    session.add_all(courses)
    session.commit()

    # Create Students and Enrollments
    students = []
    for i in range(10): # Create 10 students
        student = Student(name=f"Student_{i}", email=f"student{i}@uni.edu")
        students.append(student)
        session.add(student)
        session.flush() # get ID
        
        # Target Student (ID 1) gets lots of enrollments to trigger N+1
        num_courses = 40 if i == 0 else 5
        
        enrolled_courses = random.sample(courses, num_courses)
        for course in enrolled_courses:
            # Find an instructor for this department (or random if none)
            dept_instructors = [inst for inst in instructors if inst.department_id == course.department_id]
            instructor = random.choice(dept_instructors) if dept_instructors else random.choice(instructors)
            
            enrollment = Enrollment(
                student=student,
                course=course,
                instructor=instructor,
                semester="Fall 2023",
                grade=random.choice(["A", "B", "C", "A-", "B+"])
            )
            session.add(enrollment)
            
    session.commit()
    print("Database initialized.")

if __name__ == "__main__":
    init_db()
PYEOF

# --- 2. Define Models File (Shared) ---
cat > "$PROJECT_DIR/models/__init__.py" << 'PYEOF'
from sqlalchemy import Column, Integer, String, ForeignKey, create_engine
from sqlalchemy.orm import declarative_base, relationship, sessionmaker
import os

Base = declarative_base()

class Department(Base):
    __tablename__ = 'departments'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    code = Column(String)
    courses = relationship("Course", back_populates="department")
    instructors = relationship("Instructor", back_populates="department")

class Instructor(Base):
    __tablename__ = 'instructors'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    department_id = Column(Integer, ForeignKey('departments.id'))
    department = relationship("Department", back_populates="instructors")

class Course(Base):
    __tablename__ = 'courses'
    id = Column(Integer, primary_key=True)
    title = Column(String)
    code = Column(String)
    credits = Column(Integer)
    department_id = Column(Integer, ForeignKey('departments.id'))
    department = relationship("Department", back_populates="courses")

class Student(Base):
    __tablename__ = 'students'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    email = Column(String)
    # Lazy loading by default (triggers N+1 if accessed in loop without eager load)
    enrollments = relationship("Enrollment", back_populates="student")

class Enrollment(Base):
    __tablename__ = 'enrollments'
    id = Column(Integer, primary_key=True)
    student_id = Column(Integer, ForeignKey('students.id'))
    course_id = Column(Integer, ForeignKey('courses.id'))
    instructor_id = Column(Integer, ForeignKey('instructors.id'))
    semester = Column(String)
    grade = Column(String)
    
    student = relationship("Student", back_populates="enrollments")
    course = relationship("Course")
    instructor = relationship("Instructor")

def get_session():
    db_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'university.db')
    engine = create_engine(f'sqlite:///{db_path}')
    Session = sessionmaker(bind=engine)
    return Session()
PYEOF

# --- 3. Create Inefficient Service (The Task) ---
cat > "$PROJECT_DIR/services/transcript.py" << 'PYEOF'
from models import Student, get_session

def generate_student_transcript(student_id):
    """
    Generates a transcript for a student.
    TODO: Optimize this function! It currently performs too many database queries.
    """
    session = get_session()
    try:
        student = session.query(Student).get(student_id)
        if not student:
            return None
            
        transcript_data = {
            "student_name": student.name,
            "email": student.email,
            "courses": []
        }
        
        # PROBLEM AREA: N+1 Queries
        # 1 query to get enrollments
        enrollments = student.enrollments 
        
        for enrollment in enrollments:
            # +1 query per enrollment to get Course
            course = enrollment.course
            # +1 query per enrollment to get Department
            dept = course.department
            # +1 query per enrollment to get Instructor
            instructor = enrollment.instructor
            
            transcript_data["courses"].append({
                "code": course.code,
                "title": course.title,
                "dept_code": dept.code,
                "instructor": instructor.name,
                "grade": enrollment.grade,
                "semester": enrollment.semester
            })
            
        return transcript_data
    finally:
        session.close()
PYEOF

cat > "$PROJECT_DIR/services/__init__.py" << 'PYEOF'
# Service package
PYEOF

# --- 4. Create Test Suite (Verification) ---
cat > "$PROJECT_DIR/tests/test_transcript.py" << 'PYEOF'
import pytest
import json
from sqlalchemy import event
from models import get_session
from services.transcript import generate_student_transcript

# Global query counter
query_count = 0

def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    global query_count
    query_count += 1

@pytest.fixture
def db_session_with_counter():
    session = get_session()
    # Attach event listener to the engine
    event.listen(session.get_bind(), "before_cursor_execute", before_cursor_execute)
    global query_count
    query_count = 0
    yield session
    event.remove(session.get_bind(), "before_cursor_execute", before_cursor_execute)
    session.close()

def test_transcript_correctness():
    """Verify that the data returned is structurally correct."""
    # We rely on the populated data. Student 1 exists and has enrollments.
    result = generate_student_transcript(1)
    
    assert result is not None
    assert result['student_name'] == "Student_0"
    assert len(result['courses']) >= 20 # We seeded 40, random sampling might vary slightly but logic sets 40
    
    first_course = result['courses'][0]
    required_keys = {"code", "title", "dept_code", "instructor", "grade", "semester"}
    assert required_keys.issubset(first_course.keys())

def test_query_count(db_session_with_counter):
    """Verify that the function uses efficient querying (< 10 queries)."""
    global query_count
    query_count = 0 # Reset
    
    generate_student_transcript(1)
    
    print(f"\nTotal SQL Queries Executed: {query_count}")
    
    # Initial naive implementation is ~120+ queries (1 + 1 + 40*3)
    # Optimized should be 1-3 queries
    assert query_count < 10, f"Too many database queries! Executed {query_count}, expected < 10."

PYEOF

cat > "$PROJECT_DIR/requirements.txt" << 'PYEOF'
sqlalchemy
pytest
PYEOF

# --- 5. Initialize DB and Environment ---
echo "Initializing database..."
su - ga -c "cd $PROJECT_DIR && python3 create_db.py"

# Open PyCharm
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR" "transcript_engine"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="