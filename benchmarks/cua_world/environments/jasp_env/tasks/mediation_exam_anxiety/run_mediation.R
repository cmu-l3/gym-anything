library(lavaan)

data <- read.csv("/tmp/ExamAnxiety.csv")

model <- '
  Revise ~ a * Anxiety
  Exam ~ b * Revise + c * Anxiety
  indirect := a * b
  direct := c
  total := c + (a * b)
'

fit <- sem(model, data = data)
summary(fit)
