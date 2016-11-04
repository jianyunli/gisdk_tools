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
outputDir <- args[2]

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

# Write the capacities out to a CSV
# Implement the write_bin procedure when available
write_csv(df, paste0(outputDir, "/HourlyCapacities.csv"))
