package com.example.hr.model;

import java.util.Date;

/**
 * Employee entity representing a company employee.
 *
 * LEGACY ISSUE: Uses java.util.Date for hire and birth dates.
 * java.util.Date is mutable, poorly designed, and deprecated for new code.
 * Consider replacing all date fields with modern java.time alternatives.
 */
public class Employee {

    private int id;
    private String firstName;
    private String lastName;
    private String email;
    private String department;
    private String jobTitle;

    // LEGACY: should be replaced with modern date type
    private Date hireDate;
    private Date dateOfBirth;
    // LEGACY: should be replaced with modern date-time type
    private Date lastModified;

    private double salary;
    private boolean active;

    public Employee() {}

    public Employee(int id, String firstName, String lastName, String email,
                    String department, String jobTitle, Date hireDate,
                    Date dateOfBirth, double salary) {
        this.id = id;
        this.firstName = firstName;
        this.lastName = lastName;
        this.email = email;
        this.department = department;
        this.jobTitle = jobTitle;
        this.hireDate = hireDate;
        this.dateOfBirth = dateOfBirth;
        this.salary = salary;
        this.active = true;
        this.lastModified = new Date();
    }

    // Getters and setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }
    public String getFirstName() { return firstName; }
    public void setFirstName(String firstName) { this.firstName = firstName; }
    public String getLastName() { return lastName; }
    public void setLastName(String lastName) { this.lastName = lastName; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getDepartment() { return department; }
    public void setDepartment(String department) { this.department = department; }
    public String getJobTitle() { return jobTitle; }
    public void setJobTitle(String jobTitle) { this.jobTitle = jobTitle; }
    public Date getHireDate() { return hireDate; }
    public void setHireDate(Date hireDate) { this.hireDate = hireDate; }
    public Date getDateOfBirth() { return dateOfBirth; }
    public void setDateOfBirth(Date dateOfBirth) { this.dateOfBirth = dateOfBirth; }
    public Date getLastModified() { return lastModified; }
    public void setLastModified(Date lastModified) { this.lastModified = lastModified; }
    public double getSalary() { return salary; }
    public void setSalary(double salary) { this.salary = salary; }
    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }
}
