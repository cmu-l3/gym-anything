package com.example.hr;

import com.example.hr.model.Employee;
import com.example.hr.model.Department;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * In-memory directory of employees and departments.
 *
 * LEGACY ISSUE: All collections use raw types (no generic parameters).
 * Every List and Map should have explicit type parameters.
 * Also: string manipulation uses StringBuffer — should use StringBuilder.
 */
public class EmployeeDirectory {

    // LEGACY: raw type, no type parameter specified
    private Map employees = new HashMap();
    // LEGACY: raw type, no type parameter specified
    private Map departments = new HashMap();
    private int nextEmpId = 1;
    private int nextDeptId = 1;

    public Employee addEmployee(Employee employee) {
        employee.setId(nextEmpId++);
        employees.put(employee.getId(), employee);
        return employee;
    }

    public Department addDepartment(Department department) {
        department.setId(nextDeptId++);
        departments.put(department.getId(), department);
        return department;
    }

    public Employee getEmployee(int id) {
        return (Employee) employees.get(id);
    }

    public Department getDepartment(int id) {
        return (Department) departments.get(id);
    }

    /**
     * Get all employees in a department by name.
     * LEGACY: returns raw, unparameterized List type
     */
    public List getEmployeesByDepartment(String departmentName) {
        List result = new ArrayList();
        for (Object obj : employees.values()) {
            Employee emp = (Employee) obj;
            if (departmentName.equals(emp.getDepartment())) {
                result.add(emp);
            }
        }
        return result;
    }

    /**
     * Search employees by name fragment.
     * LEGACY: Returns raw List, uses StringBuffer instead of StringBuilder.
     */
    public List searchByName(String query) {
        List results = new ArrayList();
        for (Object obj : employees.values()) {
            Employee emp = (Employee) obj;
            // LEGACY: Should use StringBuilder (not synchronized StringBuffer)
            StringBuffer fullName = new StringBuffer();
            fullName.append(emp.getFirstName()).append(" ").append(emp.getLastName());
            if (fullName.toString().toLowerCase().contains(query.toLowerCase())) {
                results.add(emp);
            }
        }
        return results;
    }

    /**
     * Generate a formatted employee summary string.
     * LEGACY: Uses StringBuffer — migrate to StringBuilder.
     */
    public String generateSummary(Employee employee) {
        // LEGACY: StringBuffer is synchronized — use StringBuilder
        StringBuffer sb = new StringBuffer();
        sb.append("Employee: ").append(employee.getFirstName())
          .append(" ").append(employee.getLastName());
        sb.append(" | Dept: ").append(employee.getDepartment());
        sb.append(" | Title: ").append(employee.getJobTitle());
        sb.append(" | Salary: $").append(employee.getSalary());
        return sb.toString();
    }

    public int getEmployeeCount() {
        return employees.size();
    }

    public int getDepartmentCount() {
        return departments.size();
    }
}
