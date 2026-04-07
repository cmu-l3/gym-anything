library(lavaan)

data <- read.csv("/tmp/ExamAnxiety.csv")

model <- '
  Anxiety ~ a * Revise
  Exam ~ b * Anxiety + c * Revise
  indirect := a * b
  direct := c
  total := c + (a * b)
'

fit <- sem(model, data = data)
summary(fit)
