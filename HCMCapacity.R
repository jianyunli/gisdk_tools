# R script to calculate network speeds and capacities

# Load packages
library(dplyr)
library(tidyr)
library(readr)
library(hcmr)
library(tcadr)

# The script is called from the command line
# by the model. Collect arguments passed.
args <- commandArgs(trailingOnly = TRUE)
hwyBIN <- args[1]
output_dir <- args[2]

# read the network bin file into a data frame
df <- read_tcad(hwyBIN)

# Change any NAs to zero
df[is.na(df)] <- 0

# Calculate Capacities
df <- df %>%
  mutate(
    ABHourlyCapD = hcm_calculate(
      LOS = "D",
      ft = HCMType,
      sl = PostedSpeed,
      at = AreaType,
      med = HCMMedian,
      lanes = ABLanes,
      terrain = Terrain
    ),
    BAHourlyCapD = hcm_calculate(
      LOS = "D",
      ft = HCMType,
      sl = PostedSpeed,
      at = AreaType,
      med = HCMMedian,
      lanes = BALanes,
      terrain = Terrain
    ),
    ABHourlyCapE = hcm_calculate(
      LOS = "E",
      ft = HCMType,
      sl = PostedSpeed,
      at = AreaType,
      med = HCMMedian,
      lanes = ABLanes,
      terrain = Terrain
    ),
    BAHourlyCapE = hcm_calculate(
      LOS = "E",
      ft = HCMType,
      sl = PostedSpeed,
      at = AreaType,
      med = HCMMedian,
      lanes = BALanes,
      terrain = Terrain
    ),
    maxLanes = pmax(ABLanes,BALanes)
  )

# Change any NAs to zero
df[is.na(df)] <- 0

# Set CC capacity
df <- df %>%
  mutate(
    ABHourlyCapD = ifelse(
      HCMType == "CC",9999,ABHourlyCapD
    ),
    BAHourlyCapD = ifelse(
      HCMType == "CC",9999,BAHourlyCapD
    ),
    ABHourlyCapE = ifelse(
      HCMType == "CC",9999,ABHourlyCapE
    ),
    BAHourlyCapE = ifelse(
      HCMType == "CC",9999,BAHourlyCapE
    )
  )

# If a freeway link has only one lane (ramps), divide the hourly capacities
# by two (freeway calculation assumes minimum of two lanes).
df <- df %>%
  mutate(
    ABHourlyCapD = ifelse(HCMType == "Freeway" & ABLanes == 1, ABHourlyCapD / 2, ABHourlyCapD),
    BAHourlyCapD = ifelse(HCMType == "Freeway" & BALanes == 1, BAHourlyCapD / 2, BAHourlyCapD),
    ABHourlyCapE = ifelse(HCMType == "Freeway" & ABLanes == 1, ABHourlyCapE / 2, ABHourlyCapE),
    BAHourlyCapE = ifelse(HCMType == "Freeway" & BALanes == 1, BAHourlyCapE / 2, BAHourlyCapE)
  )

# Write the capacities out to a CSV
# Implement the write_bin procedure when available
write_csv(df, paste0(output_dir, "/HourlyCapacities.csv"))
