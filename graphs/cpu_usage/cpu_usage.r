# ------------------------------------------------------------
# cpu_mem_timeseries.R   –  PERCENTAGE VERSION
# ------------------------------------------------------------
library(tidyverse)
library(glue)

# ─────────────────────────────────────────────────────────────
#  User-tunable capacities (per node or slice)  ↓↓↓
# ─────────────────────────────────────────────────────────────
cpu_capacity_mcores <- 1000   # 1 vCPU  = 1000 mcores
mem_capacity_mib    <- 1024   # 1 GiB   = 1024 MiB

# ─────────────────────────────────────────────────────────────
# 1.  Read real data OR build a stub for styling
#     Expected columns in real CSV:
#       method, time_s, cpu_mcores, mem_mib
# ─────────────────────────────────────────────────────────────
csv_path <- "cpu_mem_timeseries.csv"

if (!file.exists(csv_path)) {
  message("⚠️  ", csv_path, " not found – generating placeholder data…")
  
  set.seed(42)
  methods  <- c("Submariner", "L2S-M+")
  t        <- 0:180
  rows     <- list()
  
  for (m in methods) {
    prm <- if (m == "Submariner") {
      list(cpu_peak = 800, cpu_mu = 50, cpu_sig = 12,
           mem_base = 350, mem_inc = 220)
    } else {  # L2S-M+
      list(cpu_peak = 550, cpu_mu = 30, cpu_sig = 10,
           mem_base = 280, mem_inc = 130)
    }
    for (ti in t) {
      cpu <- 50 + prm$cpu_peak * exp(-0.5 * ((ti - prm$cpu_mu) /
                                             prm$cpu_sig)^2) +
             rnorm(1, sd = 10)
      mem <- prm$mem_base +
             prm$mem_inc / (1 + exp(-(ti - 40) / 6)) +
             rnorm(1, sd = 5)
      rows[[length(rows) + 1]] <-
        list(method = m, time_s = ti,
             cpu_mcores = max(cpu, 0),
             mem_mib    = max(mem, 0))
    }
  }
  write_csv(bind_rows(rows), csv_path)
  message(glue("   → Wrote placeholder data to {csv_path}"))
}

# ─────────────────────────────────────────────────────────────
# 2.  Load & convert to % of capacity
# ─────────────────────────────────────────────────────────────
df <- read_csv(csv_path,
               col_types = cols(
                 method     = col_character(),
                 time_s     = col_double(),
                 cpu_mcores = col_double(),
                 mem_mib    = col_double()
               )) |>
  mutate(cpu_pct = 100 * cpu_mcores / cpu_capacity_mcores,
         mem_pct = 100 * mem_mib    / mem_capacity_mib)

plot_df <- df |>
  select(method, time_s, cpu_pct, mem_pct) |>
  pivot_longer(c(cpu_pct, mem_pct),
               names_to  = "metric",
               values_to = "value") |>
  mutate(metric = recode(metric,
                         cpu_pct = "CPU (%)",
                         mem_pct = "Memory (%)"))

# ─────────────────────────────────────────────────────────────
# 3.  Draw the figure
# ─────────────────────────────────────────────────────────────
p <- ggplot(plot_df,
            aes(x = time_s, y = value, colour = metric)) +
  geom_line(linewidth = 1) +                                         # <─ linewidth
  scale_colour_manual(values = c("CPU (%)"    = "#0072B2",           # blue
                                 "Memory (%)" = "#E69F00")) +        # orange
  facet_wrap(~method, ncol = 1) +                                    # <─ the missing '+'
  labs(title   = "CPU & Memory usage (% of capacity) over time",
       x       = "Time since deploy start (s)",
       y       = "Percentage of capacity",
       colour  = NULL) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.5) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "top",
        strip.text = element_text(face = "bold"))

print(p)

ggsave("cpu_mem_over_time.png", p, width = 8, height = 6, dpi = 300)
ggsave("cpu_mem_over_time.pdf", p, width = 8, height = 6, device = cairo_pdf)

message("✅  Saved cpu_mem_over_time.{png,pdf}")

message("✅  Saved cpu_mem_over_time.{png,pdf}")
