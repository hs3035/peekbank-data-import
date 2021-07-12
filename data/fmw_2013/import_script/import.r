library(here)
library(janitor)
library(tidyverse)
library(readxl)
library(peekds)
library(osfr)

#TODO: check
sampling_rate_hz <- 30
sampling_rate_ms <- 1000/30

dataset_name <- "fmw_2013"
read_path <- here("data",dataset_name,"raw_data")
write_path <- here("data",dataset_name, "processed_data")

dataset_table_filename <- "datasets.csv"
aoi_table_filename <- "aoi_timepoints.csv"
subject_table_filename <- "subjects.csv"
administrations_table_filename <- "administrations.csv"
stimuli_table_filename <- "stimuli.csv"
trial_types_table_filename <- "trial_types.csv"
trials_table_filename <- "trials.csv"
aoi_regions_table_filename <-  "aoi_region_sets.csv"
xy_table_filename <-  "xy_timepoints.csv"

osf_token <- read_lines(here("osf_token.txt"))

# peekds::get_raw_data(dataset_name, path = read_path)

remove_repeat_headers <- function(d, idx_var) {
  d[d[,idx_var] != idx_var,]
}

# read icoder files
d_raw_1_18 <- read_delim(fs::path(read_path,"FMW2013_English_18mos_n50toMF.txt"),
                       delim = "\t",
                       col_types = cols(.default = "c"))

d_raw_2_18 <- read_excel(here::here(read_path,"FMW2013_English_18mos_n28toMF.xls"),
                         col_types = "text") 
  
d_raw_1_24 <- read_delim(fs::path(read_path,"FMW2013_English_24mos_n33toMF.txt"),
                       delim = "\t",
                       col_types = cols(.default = "c")) %>%
  select(-c(X255:X4372))

d_raw_2_24 <- read_excel(here::here(read_path,"FMW2013_English_24m_n21toMF.xls"),
                         col_types = "text")

#### FUNCTIONS FOR PREPROCESSING ####

preprocess_raw_data <- function(dataset){
  ## filters out NAs and cleans up column names for further processing
  
  d_filtered <- dataset %>%
    select_if(~sum(!is.na(.)) > 0) %>%
    filter(!is.na(`Sub Num`))
  d_processed <-  d_filtered %>%
    clean_names()
  return(d_processed)
}

extract_col_types <- function(dataset,col_pattern="xf") {
  
  old_names <- colnames(dataset)
  
  if (col_pattern == "xf") { # d_raw_1_18 && d_raw_1_24
    metadata_names <- old_names[!str_detect(old_names,"x\\d|f\\d")]
    pre_dis_names <- old_names[str_detect(old_names, "x\\d")]
    post_dis_names  <- old_names[str_detect(old_names, "f\\d")]
  } else if (col_pattern == "xfx") { # d_raw_2_24
    metadata_names <- old_names[!str_detect(old_names,"x\\d|f\\d")]
    pre_dis_min_index <- which.max(str_detect(old_names, "x\\d"))
    pre_dis_max_index <- which.min(match(str_detect(old_names, "f\\d"), TRUE))-1
    pre_dis_names <- old_names[pre_dis_min_index:pre_dis_max_index]
    post_dis_names  <- old_names[!(old_names %in% c(metadata_names,pre_dis_names))]
  } else if (col_pattern == "x") { # d_raw_2_18
    metadata_names <- old_names[!str_detect(old_names, "x\\d|onset|second")]
    pre_dis_min_index <- which.max(str_detect(old_names, "x\\d"))
    pre_dis_max_index <- which.min(match(str_detect(old_names, "onset"), TRUE))-1
    pre_dis_names <- old_names[pre_dis_min_index:pre_dis_max_index]
    post_dis_names  <- old_names[!(old_names %in% c(metadata_names,pre_dis_names))]
  }
  ### TO DO: HANDLE THIRD COLUMN STRUCTURE
  
  dataset_col_types <- list(metadata_names,pre_dis_names,post_dis_names)
  names(dataset_col_types) <- c("metadata_names","pre_dis_names","post_dis_names")
  return(dataset_col_types)
}

relabel_time_cols <-  function(dataset, metadata_names, pre_dis_names, post_dis_names, truncation_point = length(colnames(dataset)),sampling_rate=sampling_rate_ms) {
  ## relabels the time columns in the dataset to ms values (to prepare for pivoting to long format == 1 timepoint per row)
  dataset_processed <- dataset
  
  pre_dis_names_clean <- round(seq(from = length(pre_dis_names) * sampling_rate,
                                   to = sampling_rate,
                                   by = -sampling_rate) * -1,digits=0)
  
  post_dis_names_clean <- round(seq(from = 0,
                                    to = length(post_dis_names) * sampling_rate-1,
                                    by = sampling_rate),digits=0)
  
  colnames(dataset_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names_clean)
  
  ### truncate columns 
  ## default is to keep all columns/ timepoints; specify a truncation_point to remove unneeded timepoints
  if (truncation_point < length(colnames(dataset))) {
    #remove
    dataset_processed <- dataset_processed %>%
      select(-all_of(truncation_point:length(colnames(dataset_processed))))
  }
  
  return(dataset_processed)
}

#### Process individual datasets

## Temporary: examples of how to process individual datasets

## TODO make function which looks at if over half of values in a column are NA and if they are, make truncate
## point occur at that column

truncation_point_calc <- function(dataset, col_pattern="xf") {
  old_names <- colnames(dataset)
  if (col_pattern == "x"){
    post_dis_min_index <- which.min(match(str_detect(old_names, "Onset"), TRUE))
  } 
  else {
    post_dis_min_index <- which.min(match(str_detect(old_names, "F\\d"), TRUE))
  }
 
  ratios_of_na <- colMeans(is.na(dataset))
  truncation_point <- length(ratios_of_na)
  for(i in 1:length(ratios_of_na)){
    if(ratios_of_na[[i]] > 0.95 && i > post_dis_min_index){
      truncation_point <- i
      return(truncation_point)
    }
  }
  # ratios <- dataset_col_not_na_ratio[1,]
  #truncation_point <- which.max(match(ratios > 0.1,TRUE)) + 1
  
  return(truncation_point)
}

temp_1_18 <- d_raw_1_18 %>%
  preprocess_raw_data() %>%
  relabel_time_cols(
    metadata_names = extract_col_types(.)[["metadata_names"]],
    pre_dis_names = extract_col_types(.)[["pre_dis_names"]],
    post_dis_names = extract_col_types(.)[["post_dis_names"]],
    truncation_point = truncation_point_calc(d_raw_1_18) # 175
  )

temp_1_24 <- d_raw_1_24 %>%
  preprocess_raw_data() %>%
  relabel_time_cols(
    metadata_names = extract_col_types(.)[["metadata_names"]],
    pre_dis_names = extract_col_types(.)[["pre_dis_names"]],
    post_dis_names = extract_col_types(.)[["post_dis_names"]],
    truncation_point = truncation_point_calc(d_raw_1_24) #152
  )

temp_2_24 <- d_raw_2_24 %>%
  preprocess_raw_data() %>%
  relabel_time_cols(
    metadata_names = extract_col_types(., col_pattern="xfx")[["metadata_names"]],
    pre_dis_names = extract_col_types(., col_pattern="xfx")[["pre_dis_names"]],
    post_dis_names = extract_col_types(., col_pattern="xfx")[["post_dis_names"]],
    truncation_point = truncation_point_calc(d_raw_2_24) #146
  )

temp_2_18 <- d_raw_2_18 %>%
  preprocess_raw_data() %>%
  relabel_time_cols(
    metadata_names = extract_col_types(., col_pattern="x")[["metadata_names"]],
    pre_dis_names = extract_col_types(., col_pattern="x")[["pre_dis_names"]],
    post_dis_names = extract_col_types(., col_pattern="x")[["post_dis_names"]],
    truncation_point = truncation_point_calc(d_raw_2_18, col_pattern="x") #149
  )
  


# 
# 
# 
# relabel_cols_2_18 <- function(d.raw){
#   d_processed <- filter_na(d.raw)
#   old_names <- colnames(d_processed)
#   metadata_names <- old_names[1:16]
#   pre_dis_names <- old_names[17:35]
#   post_dis_names  <- old_names[36:length(old_names)]
#   
#   pre_dis_names_clean <- round(seq(from = length(pre_dis_names) * sampling_rate_ms,
#                                    to = sampling_rate_ms,
#                                    by = -sampling_rate_ms) * -1,0)
#   
#   pre_dis_names_clean <- pre_dis_names %>% str_remove("...")
#   
#   colnames(d_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names)
#   
#   return(d_processed)
# }
# 
# relabel_cols_2_24 <- function(d.raw){
#   d_processed <- filter_na(d.raw)
#   
#   old_names <- colnames(d_processed)
#   metadata_names <- old_names[1:16]
#   pre_dis_names <- old_names[17:44]
#   post_dis_names  <- old_names[str_detect(old_names, "f\\d")]
#   
#   pre_dis_names <- pre_dis_names %>% str_remove("...") 
#   pre_dis_names_clean <- round(seq(from = length(pre_dis_names) * sampling_rate_ms,
#                                    to = sampling_rate_ms,
#                                    by = -sampling_rate_ms) * -1,0)
#   
#   post_dis_names_clean <-  post_dis_names %>% str_remove("f")
#   
#   colnames(d_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names_clean)
#   
#   return(d_processed)
# }
# 
# #write relabeling functions
# relabel_cols_1 <- function(d.raw){
#   
#   d_processed <- filter_na(d.raw)
#   d_processed <- d_processed %>% remove_repeat_headers(idx_var = "Months")
#   
#   
#   # Relabel time bins --------------------------------------------------
#   old_names <- colnames(d_processed)
#   metadata_names <- old_names[!str_detect(old_names,"x\\d|f\\d")]
#   pre_dis_names <- old_names[str_detect(old_names, "x\\d")]
#   post_dis_names  <- old_names[str_detect(old_names, "f\\d")]
#   
#   pre_dis_names_clean <- round(seq(from = length(pre_dis_names) * sampling_rate_ms,
#                                    to = sampling_rate_ms,
#                                    by = -sampling_rate_ms) * -1,0)
#   
#   
#   post_dis_names_clean <- post_dis_names %>% str_remove("f")
#   
#   colnames(d_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names_clean)
#   
#   
#   ### truncate columns at F3833, since trials are almost never coded later than this timepoint
#   ## TO DO: check in about this decision
#   post_dis_names_clean_cols_to_remove <- post_dis_names_clean[117:length(post_dis_names_clean)]
#   #remove
#   d_processed <- d_processed %>%
#     select(-all_of(post_dis_names_clean_cols_to_remove))
#   
#   return(d_processed)
# }
# 
# #combine
# d_processed <- bind_rows( relabel_cols_1(d_raw_1_24),
#                           relabel_cols_1(d_raw_1_18), 
#                           relabel_cols_2_18(d_raw_2_18),
#                           relabel_cols_2_24(d_raw_2_24),
#                         )

## combine datasets
## TO DO: BIND TOGETHER DATASETS POST PROCESSING

d_processed <- bind_rows(temp_1_18, temp_1_24, temp_2_18, temp_2_24)

#create trial_order variable by modifiying the tr_num variable
d_processed <- d_processed  %>%
  mutate(tr_num=as.numeric(as.character(tr_num))) %>%
  arrange(sub_num,months,order,tr_num) %>% 
  group_by(sub_num, months,condition,order) %>%
  mutate(trial_order = seq(1, length(tr_num))) %>%
  relocate(trial_order, .after=tr_num) %>%
  ungroup()

d_tidy <- d_processed #%>%
  # pivot_longer(names_to = "t", cols = `-600`:`3833`, values_to = "aoi") %>%
  # select(-c("-1333":"-633"))
# recode 0, 1, ., - as distracter, target, other, NA [check in about this]
# this leaves NA as NA
d_tidy <- d_tidy %>%
  rename(aoi_old = aoi) %>%
  mutate(aoi = case_when(
    aoi_old == "0" ~ "distractor",
    aoi_old == "1" ~ "target",
    aoi_old == "0.5" ~ "other",
    aoi_old == "." ~ "missing",
    aoi_old == "-" ~ "missing",
    is.na(aoi_old) ~ "missing"
  )) %>%
  mutate(t = as.numeric(t)) # ensure time is an integer/ numeric


# Clean up column names and add stimulus information based on existing columnns  ----------------------------------------

d_tidy <- d_tidy %>%
  filter(!is.na(sub_num)) %>%
  select(-prescreen_notes, -c_image,-response,-condition, -first_shift_gap,-rt) %>%
  #left-right is from the coder's perspective - flip to participant's perspective
  mutate(target_side = factor(target_side, levels = c('l','r'), labels = c('right','left'))) %>%
  rename(left_image = r_image, right_image=l_image) %>%
  mutate(target_label = target_image) %>%
  rename(target_image_old = target_image) %>% # since target image doesn't seem to be the specific image identifier
  mutate(target_image = case_when(target_side == "right" ~ right_image,
                                  TRUE ~ left_image)) %>%
  mutate(distractor_image = case_when(target_side == "right" ~ left_image,
                                      TRUE ~ right_image))


#create stimulus table
stimulus_table <- d_tidy %>%
  distinct(target_image,target_label) %>%
  filter(!is.na(target_image)) %>%
  mutate(dataset_id = 0,
         stimulus_novelty = "familiar",
         original_stimulus_label = target_label,
         english_stimulus_label = target_label,
         stimulus_image_path = paste0(target_image, ".pct"), # TO DO - update once images are shared/ image file path known
         image_description = target_label,
         image_description_source = "image path",
         lab_stimulus_id = target_image
  ) %>%
  mutate(stimulus_id = seq(0, length(.$lab_stimulus_id) - 1))


## add target_id  and distractor_id to d_tidy by re-joining with stimulus table on distactor image
d_tidy <- d_tidy %>%
  left_join(stimulus_table %>% select(lab_stimulus_id, stimulus_id), by=c('target_image' = 'lab_stimulus_id')) %>%
  mutate(target_id = stimulus_id) %>%
  select(-stimulus_id) %>%
  left_join(stimulus_table %>% select(lab_stimulus_id, stimulus_id), by=c('distractor_image' = 'lab_stimulus_id')) %>%
  mutate(distractor_id = stimulus_id) %>%
  select(-stimulus_id)

# get zero-indexed subject ids 
d_subject_ids <- d_tidy %>%
  distinct(sub_num) %>%
  mutate(subject_id = seq(0, length(.$sub_num) - 1))
#join
d_tidy <- d_tidy %>%
  left_join(d_subject_ids, by = "sub_num")

#get zero-indexed administration ids
d_administration_ids <- d_tidy %>%
  distinct(subject_id, sub_num, months, order) %>%
  arrange(subject_id, sub_num, months, order) %>%
  mutate(administration_id = seq(0, length(.$order) - 1)) 

# create zero-indexed ids for trial_types
d_trial_type_ids <- d_tidy %>%
  #order just flips the target side, so redundant with the combination of target_id, distractor_id, target_side
  #potentially make distinct based on condition if that is relevant to the study design (no condition manipulation here)
  distinct(trial_order, target_id, distractor_id, target_side) %>% # outdated values, could use some help here
  mutate(full_phrase = NA) %>% #unknown
  mutate(trial_type_id = seq(0, length(trial_order) - 1)) 

# joins
d_tidy_semifinal <- d_tidy %>%
  left_join(d_administration_ids) %>%
  left_join(d_trial_type_ids) 

#get zero-indexed trial ids for the trials table
d_trial_ids <- d_tidy_semifinal %>%
  distinct(trial_order,trial_type_id) %>%
  mutate(trial_id = seq(0, length(.$trial_type_id) - 1)) 

#join
d_tidy_semifinal <- d_tidy_semifinal %>%
  left_join(d_trial_ids)

# add some more variables to match schema
d_tidy_final <- d_tidy_semifinal %>%
  mutate(dataset_id = 0, # dataset id is always zero indexed since there's only one dataset
         lab_trial_id = paste(order, tr_num, sep = "-"),
         aoi_region_set_id = NA, # not applicable
         monitor_size_x = NA, #unknown TO DO
         monitor_size_y = NA, #unknown TO DO
         lab_age_units = "months",
         age = as.numeric(months), # months 
         point_of_disambiguation = 0, #data is re-centered to zero based on critonset in datawiz
         tracker = "video_camera",
         sample_rate = sampling_rate_hz) %>% 
  rename(lab_subject_id = sub_num,
         lab_age = months
  )


##### AOI TABLE ####
d_tidy_final %>%
  rename(t_norm = t) %>% # original data centered at point of disambiguation
  select(t_norm, aoi, trial_id, administration_id,lab_subject_id) %>%
  #resample timepoints
  resample_times(table_type="aoi_timepoints") %>%
  mutate(aoi_timepoint_id = seq(0, nrow(.) - 1)) %>%
  write_csv(fs::path(write_path, aoi_table_filename))

##### SUBJECTS TABLE ####
subjects <- d_tidy_final %>% 
  distinct(subject_id, lab_subject_id,sex) %>%
  filter(!(lab_subject_id == "12608"&sex=="M")) %>% #one participant has different entries for sex - 12608 is female via V Marchman
  mutate(
    sex = factor(sex, levels = c('M','F'), labels = c('male','female')),
    native_language="eng") %>%
  write_csv(fs::path(write_path, subject_table_filename))


##### ADMINISTRATIONS TABLE ####
d_tidy_final %>%
  distinct(administration_id,
           dataset_id,
           subject_id,
           age,
           lab_age,
           lab_age_units,
           monitor_size_x,
           monitor_size_y,
           sample_rate,
           tracker) %>%
  mutate(coding_method = "manual gaze coding") %>%
  write_csv(fs::path(write_path, administrations_table_filename))

##### STIMULUS TABLE ####
stimulus_table %>%
  select(-target_label, -target_image) %>%
  write_csv(fs::path(write_path, stimuli_table_filename))

#### TRIALS TABLE ####
d_tidy_final %>%
  distinct(trial_id,
           trial_order,
           trial_type_id) %>%
  write_csv(fs::path(write_path, trials_table_filename))

##### TRIAL TYPES TABLE ####
d_tidy_final %>%
  distinct(trial_type_id,
           full_phrase,
           point_of_disambiguation,
           target_side,
           lab_trial_id,
           aoi_region_set_id,
           dataset_id,
           target_id,
           distractor_id) %>%
  mutate(full_phrase_language = "eng",
         condition = "") %>% #no condition manipulation based on current documentation
  write_csv(fs::path(write_path, trial_types_table_filename))

##### AOI REGIONS TABLE ####
# create empty other files aoi_region_sets.csv and xy_timepoints
# don't need 
# tibble(administration_id = d_tidy_final$administration_id[1],
#       aoi_region_set_id=NA,
#        l_x_max=NA ,
#        l_x_min=NA ,
#        l_y_max=NA ,
#        l_y_min=NA ,
#        r_x_max=NA ,
#        r_x_min=NA ,
#        r_y_max=NA ,
#        r_y_min=NA ) %>%
#   write_csv(fs::path(write_path, aoi_regions_table_filename))

##### XY TIMEPOINTS TABLE ####
# d_tidy_final %>% distinct(trial_id, administration_id) %>%
#   mutate(x = NA,
#          y = NA,
#          t = NA,
#          xy_timepoint_id = 0:(n()-1)) %>%
#   write_csv(fs::path(write_path, xy_table_filename))

##### DATASETS TABLE ####
# write Dataset table
data_tab <- tibble(
  dataset_id = 0, # make zero 0 for all
  dataset_name = dataset_name,
  lab_dataset_id = dataset_name, # internal name from the lab (if known)
  cite = "Fernald, A., Marchman, V. A., & Weisleder, A. (2013). SES differences in language processing skill and vocabulary are evident at 18 months. Developmental Science, 16(2), 234-248",
  shortcite = "Fernald et al. (2013)"
) %>%
  write_csv(fs::path(write_path, dataset_table_filename))



# validation check ----------------------------------------------------------
validate_for_db_import(dir_csv = write_path)

