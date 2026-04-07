library(lavaan)

data <- read.csv("/tmp/ExamAnxiety.csv")

model <- '
  Revise ~ a * Anxiety
  Exam ~ b * Revise + c * Anxiety
  indirect := a * b
  direct := c
  total := c + (a * b)
'

set.seed(123)
fit <- sem(model, data = data, se = "bootstrap", bootstrap = 1000)
summary(fit, ci = TRUE)
