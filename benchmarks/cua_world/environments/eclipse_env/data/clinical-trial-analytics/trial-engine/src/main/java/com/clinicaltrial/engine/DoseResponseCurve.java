package com.clinicaltrial.engine;

/**
 * Fits a four-parameter log-logistic (Hill equation) dose-response model
 * to normalized clinical response data.
 *
 * Model: response = bottom + (top - bottom) / (1 + (EC50/dose)^hillSlope)
 */
public class DoseResponseCurve {

    private double ec50;
    private double hillSlope;
    private double bottom;
    private double top;
    private boolean fitted = false;

    /**
     * Fits the dose-response curve to the given data points using a
     * simple least-squares grid search over the EC50 parameter space.
     *
     * @param doses    array of dose levels (mg)
     * @param responses array of normalized mean response values per dose
     */
    public void fit(double[] doses, double[] responses) {
        if (doses.length != responses.length || doses.length < 3) {
            throw new IllegalArgumentException("Need at least 3 matched dose-response pairs");
        }

        bottom = responses[0];
        top = responses[responses.length - 1];
        hillSlope = 1.0;

        double bestError = Double.MAX_VALUE;
        double bestEc50 = doses[doses.length / 2];

        double doseMin = doses[0] > 0 ? doses[0] : 0.001;
        double doseMax = doses[doses.length - 1];

        for (double candidateEc50 = doseMin; candidateEc50 <= doseMax; candidateEc50 += 0.5) {
            double error = 0.0;
            for (int i = 0; i < doses.length; i++) {
                double predicted = predict(doses[i], candidateEc50);
                error += Math.pow(predicted - responses[i], 2);
            }
            if (error < bestError) {
                bestError = error;
                bestEc50 = candidateEc50;
            }
        }

        this.ec50 = bestEc50;
        this.fitted = true;
    }

    private double predict(double dose, double ec50) {
        if (dose <= 0) dose = 0.001;
        return bottom + (top - bottom) / (1.0 + Math.pow(ec50 / dose, hillSlope));
    }

    public double predict(double dose) {
        if (!fitted) throw new IllegalStateException("Model not fitted yet");
        return predict(dose, this.ec50);
    }

    public double getEc50() {
        if (!fitted) throw new IllegalStateException("Model not fitted yet");
        return ec50;
    }

    public boolean isFitted() { return fitted; }
}
