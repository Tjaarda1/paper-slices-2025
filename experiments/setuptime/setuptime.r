library(tidyverse)

# Suppose you collected 40 timed runs per method
set.seed(2025)
n_runs <- 40
results <- tibble(
  method = rep(c("Submariner", "L2S-M+"), each = n_runs),
  seconds = c(
    rnorm(n_runs, mean = 183,  sd = 19),   
    rnorm(n_runs, mean = 75,  sd = 6)
  )
)

ggplot(results, aes(method, seconds, fill = method)) +
  geom_boxplot(outlier.shape = NA, width = .6, alpha = .4) +   # main boxes
  geom_jitter(width = .15, alpha = .25, size = 1) +            # raw points
  stat_summary(fun = median, geom = "text", colour = "black",
               vjust = -.7, aes(label = round(..y.., 1))) +    # show medians
  scale_y_continuous("Deployment time (ms)") +
  scale_x_discrete("") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

