#!/usr/bin/env Rscript
# podstcpdump.r — Packets/sec (first 20 s) as ridgelines; PNG + PDF; optional --filter

duration_sec <- 20L
bin_sec <- 1L

# ---- Args ----
args <- commandArgs(trailingOnly = TRUE)
display_filter <- NULL
if (length(args) >= 2) {
  i <- which(args == "--filter")
  if (length(i) == 1 && i < length(args)) {
    display_filter <- args[i + 1]
    args <- args[-c(i, i + 1)]
  }
}
if (length(args) == 0) args <- c(Sys.glob("*.pcap"), Sys.glob("*.pcapng"))
if (length(args) == 0) stop("No pcap files. Usage: Rscript podstcpdump.r [--filter 'arp'] a.pcap ...")

# ---- Check deps ----
if (!requireNamespace("ggplot2", quietly = TRUE) || !requireNamespace("ggridges", quietly = TRUE)) {
  stop("Please install ggplot2 and ggridges: install.packages(c('ggplot2','ggridges'))")
}
ts_ok <- tryCatch({ system2("tshark", "-v", stdout = FALSE, stderr = FALSE) == 0L }, error = function(e) FALSE)
if (!ts_ok) stop("tshark not found on PATH")

# ---- Helpers ----
read_times <- function(path, filt = display_filter) {
  ts_args <- c("-r", path, "-T", "fields", "-e", "frame.time_epoch")
  if (!is.null(filt) && nzchar(filt)) ts_args <- c(ts_args, "-Y", filt)  # display filter when reading
  lines <- suppressWarnings(system2("tshark", args = ts_args, stdout = TRUE))
  as.numeric(lines[nzchar(lines)])
}

counts_20s <- function(path, duration = duration_sec, bin = bin_sec) {
  ts <- read_times(path)
  lvl <- 0:(duration - 1)
  if (!length(ts) || all(is.na(ts))) {
    return(data.frame(file = basename(path), second = lvl, packets = 0L))
  }
  t0 <- min(ts, na.rm = TRUE)
  rel <- floor((ts - t0 + 1e-9) / bin)
  rel <- rel[rel >= 0L & rel < duration]
  tab <- table(factor(rel, levels = lvl))
  data.frame(file = basename(path), second = lvl, packets = as.integer(tab))
}

# ---- Process ----
dfs <- lapply(args, counts_20s)
out <- do.call(rbind, dfs)
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_csv <- paste0("pps_20s", if (!is.null(display_filter)) "_filtered", "_", stamp, ".csv")
write.csv(out, out_csv, row.names = FALSE)
cat("Saved CSV:", out_csv, "\n")

# ---- Build ridgeline-friendly y positions (one ridge per file) ----
files <- sort(unique(out$file))
out$ypos <- as.numeric(factor(out$file, levels = rev(files)))  # top-to-bottom order

# Axis helpers for annotation/ticks
y_max <- max(out$packets, na.rm = TRUE); if (!is.finite(y_max) || y_max <= 0) y_max <- 1L
y_step <- max(1L, ceiling(y_max / 6))
library(ggplot2); library(ggridges)

# Optional: highlight your ping window (t=5..15) if you used that timing
ping_start <- 5; ping_end <- 15

# ---- Ridgeline plot ----
p <- ggplot(out, aes(x = second, y = ypos, height = packets, group = file, fill = file)) +
  # Light band for ping window
  annotate("rect", xmin = ping_start, xmax = ping_end, ymin = -Inf, ymax = Inf, alpha = 0.08) +
  geom_ridgeline(scale = 1, alpha = 0.6, size = 0.25) +  # scale=1 keeps packets = true ridge height
  # An outline line for readability
  geom_line(aes(y = ypos + 0, color = file), linewidth = 0.3, show.legend = FALSE) +
  scale_x_continuous(breaks = 0:(duration_sec - 1), limits = c(0, duration_sec - 1), expand = expansion(mult = c(0, 0.01))) +
  # Map numeric positions back to file labels
  scale_y_continuous(
    breaks = seq_along(rev(files)),
    labels = rev(files),
    expand = expansion(mult = c(0.05, 0.15))
  ) +
  labs(
    title = "Packets per second (ridgelines, first 20 s)",
    subtitle = if (!is.null(display_filter)) paste("Display filter:", display_filter) else NULL,
    x = "Seconds since first packet",
    y = "pcap file",
    fill = "File"
  ) +
  theme_ridges() +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank()
  )

# ---- Save PNG + PDF ----
png_path <- paste0("pps_20s_ridgelines_", stamp, ".png")
pdf_path <- paste0("pps_20s_ridgelines_", stamp, ".pdf")
ggsave(png_path, p, width = 10, height = max(3, 1.2 + 0.6 * length(files)), dpi = 144)
ggsave(pdf_path, p, width = 10, height = max(3, 1.2 + 0.6 * length(files)))
cat("Saved plots:", png_path, "and", pdf_path, "\n")

# Also print the table
print(out[, c("file", "second", "packets")], row.names = FALSE)
