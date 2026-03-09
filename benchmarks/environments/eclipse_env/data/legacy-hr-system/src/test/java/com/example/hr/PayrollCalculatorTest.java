package com.example.hr;

import com.example.hr.model.Employee;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Calendar;
import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class PayrollCalculatorTest {

    private PayrollCalculator calculator;
    private Employee employee;

    @BeforeEach
    void setUp() {
        calculator = new PayrollCalculator();

        Calendar cal = Calendar.getInstance();
        cal.set(2010, Calendar.JANUARY, 15);
        Date hireDate = cal.getTime();
        cal.set(1980, Calendar.AUGUST, 5);
        Date dob = cal.getTime();

        employee = new Employee(1, "Alice", "Smith", "alice@example.com",
            "Engineering", "Developer", hireDate, dob, 80000.0);
    }

    @Test
    void calculateYearsOfService_returnsPositiveValue() {
        int years = calculator.calculateYearsOfService(employee);
        assertTrue(years > 0, "Years of service should be positive for a 2010 hire");
    }

    @Test
    void calculateAge_returnsReasonableAge() {
        int age = calculator.calculateAge(employee);
        assertTrue(age >= 40 && age <= 60, "Age should be between 40 and 60 for 1980-born employee");
    }

    @Test
    void calculateMonthlyGross_dividesByTwelve() {
        double monthly = calculator.calculateMonthlyGross(employee);
        assertEquals(80000.0 / 12.0, monthly, 0.01);
    }

    @Test
    @SuppressWarnings("unchecked")
    void getAnnualBonusHistory_returnsCorrectCount() {
        List bonuses = calculator.getAnnualBonusHistory(employee, 5);
        assertEquals(5, bonuses.size());
    }
}
