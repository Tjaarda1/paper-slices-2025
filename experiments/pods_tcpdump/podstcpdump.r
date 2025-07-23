remotes::install_github("hrbrmstr/crafter")  # needs libpcap + libcrafter

library(crafter)
library(dplyr)
library(ggplot2)

pc <- read_pcap("pod-a.pcap")           # binary read
info <- pc$packet_info()                # tidy tibble
traffic <- info %>% 
  mutate(ts  = as.POSIXct(time, origin = "1970-01-01", tz = "UTC"),
         bin = cut(ts, "1 sec")) %>% 
  count(bin)

ggplot(traffic, aes(as.POSIXct(bin), n)) +
  geom_line() +
  labs(title = "packets per second (crafter)",
       y = "pkts/s")
