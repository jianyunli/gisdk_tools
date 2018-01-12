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
taz_field <- args[2]
seedTbl <- args[3]
output_dir <- args[4]

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

se_tbl <- se_tbl %>%
  rename(geo_taz = !!taz_field)

# Create a marginal table from se table
margTbl <- se_tbl %>%
  select(geo_taz, one_of(marg_cats))

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
