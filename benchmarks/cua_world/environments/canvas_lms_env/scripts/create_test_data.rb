# Canvas LMS Test Data Creation Script
# This script creates test users, courses, and enrollments for the Canvas environment

account = Account.default

# Create test students
students = [
  {name: "Jane Smith", email: "jsmith@example.com", login: "jsmith"},
  {name: "Michael Jones", email: "mjones@example.com", login: "mjones"},
  {name: "Alice Wilson", email: "awilson@example.com", login: "awilson"},
  {name: "Bob Brown", email: "bbrown@example.com", login: "bbrown"},
  {name: "Carlos Garcia", email: "cgarcia@example.com", login: "cgarcia"},
  {name: "Diana Lee", email: "dlee@example.com", login: "dlee"},
  {name: "Emily Patel", email: "epatel@example.com", login: "epatel"},
  {name: "Frank Kim", email: "fkim@example.com", login: "fkim"},
]

# Create test teachers
teachers = [
  {name: "Professor Anderson", email: "teacher1@example.com", login: "teacher1"},
  {name: "Dr. Martinez", email: "teacher2@example.com", login: "teacher2"},
]

puts "Creating students..."
students.each do |s|
  begin
    user = User.create!(name: s[:name])
    user.accept_terms
    user.register!
    pseudonym = user.pseudonyms.create!(
      unique_id: s[:login],
      password: "Student1234!",
      password_confirmation: "Student1234!",
      account: account
    )
    user.communication_channels.create!(path: s[:email], path_type: "email") { |cc| cc.workflow_state = "active" }
    puts "  Created student: #{s[:login]}"
  rescue => e
    puts "  Student #{s[:login]} may already exist: #{e.message}"
  end
end

puts "Creating teachers..."
teachers.each do |t|
  begin
    user = User.create!(name: t[:name])
    user.accept_terms
    user.register!
    pseudonym = user.pseudonyms.create!(
      unique_id: t[:login],
      password: "Teacher1234!",
      password_confirmation: "Teacher1234!",
      account: account
    )
    user.communication_channels.create!(path: t[:email], path_type: "email") { |cc| cc.workflow_state = "active" }
    puts "  Created teacher: #{t[:login]}"
  rescue => e
    puts "  Teacher #{t[:login]} may already exist: #{e.message}"
  end
end

# Create sample courses
courses = [
  {name: "Introduction to Biology", code: "BIO101"},
  {name: "World History", code: "HIST201"},
  {name: "Computer Science Fundamentals", code: "CS110"},
  {name: "Introduction to Chemistry", code: "CHEM101"},
  {name: "English Composition", code: "ENG101"},
]

puts "Creating courses..."
courses.each do |c|
  begin
    course = account.courses.create!(
      name: c[:name],
      course_code: c[:code],
      workflow_state: "available",
      is_public: true
    )
    puts "  Created course: #{c[:code]} - #{c[:name]}"
  rescue => e
    puts "  Course #{c[:code]} may already exist: #{e.message}"
  end
end

# Enroll teachers and students
puts "Enrolling users in courses..."

# Get courses
bio = Course.find_by(course_code: "BIO101")
hist = Course.find_by(course_code: "HIST201")
cs = Course.find_by(course_code: "CS110")

# Get teachers
teacher1 = Pseudonym.find_by(unique_id: "teacher1")&.user
teacher2 = Pseudonym.find_by(unique_id: "teacher2")&.user

# Get students
student_logins = ["jsmith", "mjones", "awilson", "bbrown", "cgarcia", "dlee"]
students_found = student_logins.map { |login| Pseudonym.find_by(unique_id: login)&.user }.compact

# Enroll teacher1 in BIO101 and CS110
if teacher1 && bio
  begin
    bio.enroll_teacher(teacher1)
    puts "  Enrolled teacher1 in BIO101"
  rescue => e
    puts "  teacher1 BIO101 enrollment: #{e.message}"
  end
end

if teacher1 && cs
  begin
    cs.enroll_teacher(teacher1)
    puts "  Enrolled teacher1 in CS110"
  rescue => e
    puts "  teacher1 CS110 enrollment: #{e.message}"
  end
end

# Enroll teacher2 in HIST201
if teacher2 && hist
  begin
    hist.enroll_teacher(teacher2)
    puts "  Enrolled teacher2 in HIST201"
  rescue => e
    puts "  teacher2 HIST201 enrollment: #{e.message}"
  end
end

# Enroll first 3 students in BIO101
students_found[0..2].each do |student|
  if student && bio
    begin
      bio.enroll_student(student)
      puts "  Enrolled #{student.name} in BIO101"
    rescue => e
      puts "  #{student.name} BIO101: #{e.message}"
    end
  end
end

# Enroll next 3 students in HIST201
students_found[3..5].each do |student|
  if student && hist
    begin
      hist.enroll_student(student)
      puts "  Enrolled #{student.name} in HIST201"
    rescue => e
      puts "  #{student.name} HIST201: #{e.message}"
    end
  end
end

puts "Test data creation complete!"
puts "  Users: #{User.count}"
puts "  Courses: #{Course.where(workflow_state: 'available').count}"
puts "  Enrollments: #{Enrollment.where(workflow_state: 'active').count}"
