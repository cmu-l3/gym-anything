package com.example.hr.model;

public class Department {
    private int id;
    private String name;
    private String costCenter;
    private int managerId;

    public Department() {}

    public Department(int id, String name, String costCenter, int managerId) {
        this.id = id;
        this.name = name;
        this.costCenter = costCenter;
        this.managerId = managerId;
    }

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getCostCenter() { return costCenter; }
    public void setCostCenter(String costCenter) { this.costCenter = costCenter; }
    public int getManagerId() { return managerId; }
    public void setManagerId(int managerId) { this.managerId = managerId; }
}
