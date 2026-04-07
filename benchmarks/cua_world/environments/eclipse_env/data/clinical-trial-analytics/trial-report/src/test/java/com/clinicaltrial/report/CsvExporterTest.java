package com.clinicaltrial.report;

import com.clinicaltrial.model.TrialSummary;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class CsvExporterTest {

    @Test
    void testExportHeaders() {
        CsvExporter exporter = new CsvExporter();
        String header = exporter.getCsvHeader();

        assertTrue(header.contains("trial_id"));
        assertTrue(header.contains("sample_size"));
        assertTrue(header.contains("mean_efficacy"));
        assertTrue(header.contains("ci_lower"));
        assertTrue(header.contains("ci_upper"));
    }
}
