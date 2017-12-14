# R script to calculate joint distributions used in trip production model

# Load packages
library(dplyr)
library(tidyr)
library(readr)
library(ipfr)
library(tcadr)

# The script is called from the command line
# by the model. Collect arguments passed.
args <- commandArgs(trailingOnly = TRUE)
se_bin <- args[1]
seedTbl <- args[2]
output_dir <- args[3]

# for testing
# se_bin <- "/Users/kyleward/projects/NRV/repo/scenarios/Base_2016/outputs/sedata/ScenarioSE.bin"
# seedTbl <- "/Users/kyleward/projects/NRV/repo/scenarios/Base_2016/inputs/generation/disagg_hh_joint.csv"
# output_dir <- "/Useres/kyleward/projects/NRV/repo/scenarios/Base_2016/outputs/generation"

# Read in the seed table and use it to determine marginals
seedTbl <- read_csv(seedTbl)
margNames <- colnames(select(seedTbl, -weight))
marg_cats <- c()
for (name in margNames){
  marg_cats <- append(marg_cats, paste0(name, unique(seedTbl[[name]])))
}

# read the se bin file into a data frame
se_tbl <- read_tcad(se_bin)
# Change any NAs to zero
se_tbl[is.na(se_tbl)] <- 0

# Create a marginal table from se table
margTbl <- se_tbl %>%
  select(geo_taz = ID, one_of(marg_cats))

# Break the marginal table up into a list of data frames for ipf()
targets <- list()
for (name in margNames) {
  temp <- margTbl %>%
    select(geo_taz, starts_with(name))
  colnames(temp) <- gsub(name, "", colnames(temp))
  targets[[name]] <- temp
}

# repeat the seed table for each TAZ
tazs <- se_tbl %>%
  filter(InternalZone == "Internal") %>%
  .$ID
seed_long <- merge(tazs, seedTbl) %>%
  dplyr::rename(geo_taz = x) %>%
  dplyr::arrange(geo_taz) %>%
  mutate(pid = seq(1, nrow(.), 1))

# Perform IPF using the ipfr package
cat("\n Performing IPF to match TAZ marginals to seed distribution\n")
final <- ipu(seed_long, targets, verbose = TRUE)

# Sleep for 10 seconds to allow user to see the output if desired
cat("\n Waiting 10 seconds")
Sys.sleep(10)

# write out the full, disagg table
write_csv(final$weight_tbl, paste0(output_dir, "/HHDisaggregation.csv"))

# Create wrk x veh table for work trips
work_tbl <- final$weight_tbl %>%
  group_by(ID = geo_taz, wrk, veh) %>%
  summarize(HH = sum(weight))
write_csv(work_tbl, paste0(output_dir, "/wrk_by_veh.csv"))

# Create siz x veh table for non-work trips
nonwork_tbl <- final$weight_tbl %>%
  group_by(ID = geo_taz, siz, veh) %>%
  summarize(HH = sum(weight))
write_csv(nonwork_tbl, paste0(output_dir, "/siz_by_veh.csv"))
