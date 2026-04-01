# =============================================================================
# Script:  clean_tracker.R
# Author:  Sören Harrs
# Date:    2026-04-01
#
# Purpose: Parse and clean tracker JSON and key log data from the raw Qualtrics
#          export. Produces page-level behavioural indicators (time on page,
#          mouse activity, paste events) and keystroke-level statistics (typing
#          speed, input jumps, text reconstruction).
#
# Run BEFORE main.R / main.do
#
# Sections:
#   0. Settings and dependencies
#   1. Import data
#   2. Parse tracker JSON
#   3. Parse key log JSON
#   4. Reconstruct typed text from keystrokes
#   5. Export
#   6. Tracker Cleaning Report
#
# Outputs:
#   data/tracker.xlsx
#   output/qualtrics_variable_list.txt (from code/qsf_extract.R)
#   code/qid_map.R (from code/qsf_extract.R)
#   output/tracker_cleaning_report.txt
# 
# =============================================================================


# =============================================================================
# 0.  SETTINGS AND DEPENDENCIES
# =============================================================================

packages <- c("readxl", "dplyr", "jsonlite", "stringr", "writexl", "stringdist")
installed <- packages %in% rownames(installed.packages())
if (any(!installed)) install.packages(packages[!installed])

library(readxl)
library(dplyr)
library(jsonlite)
library(stringr)
library(writexl)
library(stringdist)

# --------------------------------------------------------------------------- #
# CHANGE THESE SETTINGS TO MATCH YOUR DATA
# [UPDATE] Adjust always. 
# [VERIFY] Check that these match your data before running the script.
# [] Others are default settings. Change only if needed.
# --------------------------------------------------------------------------- #

# [1] [UPDATE] Working directory
setwd("C:/Users/sharrs/Dropbox/Project Bot Catching/Github/mission-possible-code")

# [2] [UPDATE] Raw Qualtrics Excel export
input_raw <- "data raw/Mission_Possible_Survey_V1_TESTDATA.xlsx"

# [3] [UPDATE] Match tracker data to Qualtrics question labels
#
# Choose ONE of options A, B, or C below
#
# Tracker data is stored using the Qualtrics question ids (QIDs) shown on that page. 
# You need to map the Qualtrics question IDs (QIDs) to the variable names in your raw Qualtrics Excel export.
#
# OPTION A: Auto-generate from your .qsf file (recommended, default)
# This ensures the mapping is correct for your specific survey and reduces manual work.
#       1. Set qsf_path [A1].
#       2. Run code in [A1], [A2], and [A3].

# [A1] [UPDATE] Path to the Qualtrics .qsf file
qsf_path  <- "qualtrics survey file/Mission_Possible_Survey_V1.qsf"

# [A2] Set output paths
qid_table_path <- "output/qualtrics_variable_list.txt"    
qid_map_path   <- "code/qid_map.R"                        

# [A3] Generate the mapping from the .qsf file 
source("code/qsf_extract.R")    # auto-generates the QID-to-label mapping
source(qid_map_path)            # then loads it into memory

# You can now inspect output/qualtrics_variable_list.txt to see the QID-to-label mapping. Adjust qid_map.R only if needed.

# OPTION B: Hard-code labels
# List requires one QID from each survey page. 
#     
# qid_map <- c(
#   QID42 = "idpage",
#   QID19 = "consent",
#   QID45 = "consent",
#   ... ,
# )

# OPTION C: Skip labelling 
# Tracker entries get fallback labels like "unknown_QID42_QID99". 
#
# qid_map <- c()


# [4] [VERIFY] List of key log trackers
#     Requires one entry per key log and corresponding open-text question.
#     col:      column name of the key log tracker in the Qualtrics export
#     text_var: column name of the corresponding open-text answer
#     You can identify text_var in output/qualtrics_variable_list.txt or qid_map.R 
keylogs <- list(
  list(col = "key_log", text_var = "text")
  # , list(col = "key_log2", text_var = "video")  # uncomment to add further key logs
)

# [5] Output file written by this script
output_path <- "data/tracker.xlsx"



# =============================================================================
# =============================================================================
# 1.  IMPORT DATA
# =============================================================================
# =============================================================================

raw <- read_excel(input_raw, sheet = "Sheet0")

# Drop the extra Qualtrics header row (row 1 of data)
raw <- raw[-1, ]

# Derive column lists from the keylogs config
keylog_cols   <- sapply(keylogs, `[[`, "col")
text_var_cols <- unique(sapply(keylogs, `[[`, "text_var"))

# Verify all columns referenced in settings exist in the imported data
required_cols <- c("ResponseId", "tracking_json", keylog_cols, text_var_cols)
missing_cols  <- setdiff(required_cols, names(raw))

if (length(missing_cols) > 0) {
  stop(sprintf(
    "Column(s) not found in the imported data:\n  %s\nCheck settings [4] and verify the variable names match your Qualtrics export.",
    paste(missing_cols, collapse = ", ")
  ))
}

# Keep only the columns needed for tracker cleaning
raw <- raw %>%
  rename(responseid = ResponseId) %>%
  select(responseid, tracking_json, all_of(keylog_cols), all_of(text_var_cols))

total_rows <- nrow(raw)



# =============================================================================
# =============================================================================
# 2.  PARSE TRACKER JSON
# =============================================================================
# =============================================================================

# ============================================================================ #
# 2a.  Helper functions
# ============================================================================ #

# Returns the survey question label for a set of QIDs using qid_map. Falls back
# to a tag built from the raw QIDs so unrecognised pages get their own uniquely
# named columns rather than silently collapsing into NA.* columns.
nameQuestion <- function(qList) {

  qList   <- unlist(qList)
  matches <- qid_map[qList[qList %in% names(qid_map)]]
  matches <- matches[!is.na(matches)]

  if (length(matches) == 0) {
    tag <- paste0("unknown_", paste(sort(qList), collapse = "_"))
    warning(sprintf("No QID match found for: %s  ->  assigned tag '%s'",
                    paste(qList, collapse = ", "), tag))
    return(tag)
  }

  return(unname(matches[1]))

}

# Adds a value to a list-column cell, creating the column if it does not yet
# exist. Used to accumulate multiple page visits into the same cell before
# aggregation in section 2c.
appendOrCreate <- function(df, row, col, value) {

  if (!col %in% names(df)) {
    df[[col]] <- vector("list", nrow(df))
  }

  if (is.null(df[[col]][[row]])) {
    df[[col]][[row]] <- list(value)
  } else {
    df[[col]][[row]] <- c(df[[col]][[row]], list(value))
  }

  return(df)

}

# Repairs a truncated JSON array by trimming everything after the last complete
# object (}) and closing the array. Applied before parsing when the raw JSON
# string starts with "[" but does not end with "]".
salvage <- function(json_string) {

  brace_positions <- gregexpr(pattern = '}', json_string)[[1]]

  if (brace_positions[1] > 0) {
    last_brace_pos <- max(brace_positions)
    salvaged_part  <- substr(json_string, 1, last_brace_pos)
    repaired_json  <- paste0(salvaged_part, "]")
    return(repaired_json)
  } else {
    return("[]")
  }

}

# Extracts the eight per-page metrics from one row of a parsed tracker JSON.
# Returns a named list whose names become the column-name suffixes when combined
# with the page label in section 2b (e.g. "dictator_duration", "dictator_paste").
# The "page" field stores the Qualtrics page index and gets the "_page" suffix,
# which is used by aggregate_list_cols() to apply the correct aggregation rule.
parse_tracker_entry <- function(json_row) {
  list(
    page           = json_row$page,
    duration       = json_row$time_on_page,
    paste          = json_row$paste_detected,
    copy           = json_row$copy_detected,
    tab            = json_row$tab_hidden,
    blur           = json_row$window_blurred,
    mouseMoveCount = json_row$mouse_move_count,
    clickCount     = json_row$click_count
  )
}

# Aggregates the list-columns produced by section 2b into scalar values.
# Columns ending in "_page" store visit-index integers and are joined as
# "1|2|..." strings. All other list-columns are numeric or logical and are
# summarised as sum (numeric) or any (logical) across page visits.
aggregate_list_cols <- function(df) {

  df[] <- lapply(names(df), function(colname) {
    col <- df[[colname]]
    if (!is.list(col)) return(col)

    sapply(col, function(cell) {
      if (is.null(cell)) return(NA)
      vals <- unlist(cell, recursive = TRUE, use.names = FALSE)
      if (all(is.na(vals))) return(NA)

      # Page-index columns: concatenate visit indices as "1|2|..." strings
      if (grepl("_page$", colname)) return(paste(vals, collapse = "|"))

      # Numeric: sum across visits; logical: TRUE if event occurred in any visit
      if (is.numeric(vals))  return(sum(vals, na.rm = TRUE))
      if (is.logical(vals))  return(any(vals, na.rm = TRUE))
      paste(vals, collapse = "|")
    })
  })

  df

}


# ============================================================================ #
# 2b.  Extract per-page variables from tracker JSON
# ============================================================================ #

tracker_n_invalid    <- 0
tracker_n_salvaged   <- 0
tracker_unknown_qids <- character(0)

n_rows <- nrow(raw)
cat("\n[2/6] Parsing tracker JSON\n")
pb_tracker <- utils::txtProgressBar(min = 0, max = max(1, n_rows), style = 3, width = 30)

for (i in seq_len(n_rows)) {

  temp <- raw$tracking_json[i]

  # Attempt to repair truncated tracker JSONs before parsing
  if (!is.na(temp) && startsWith(temp, "[") && !endsWith(temp, "]")) {
    temp <- salvage(temp)
    tracker_n_salvaged <- tracker_n_salvaged + 1
  }

  json <- tryCatch(fromJSON(temp), error = function(e) NULL)

  if (is.null(json)) {
    cat("Row", i, "skipped -> INVALID tracker JSON\n")
    tracker_n_invalid <- tracker_n_invalid + 1
    next
  }

  for (index in seq_len(nrow(json))) {

    page_label <- withCallingHandlers(
      nameQuestion(json[index, ]$question_ids),
      warning = function(w) {
        tracker_unknown_qids <<- c(tracker_unknown_qids, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )

    entry <- parse_tracker_entry(json[index, ])
    for (nm in names(entry)) {
      raw <- appendOrCreate(raw, i, paste0(page_label, "_", nm), entry[[nm]])
    }

  }

  utils::setTxtProgressBar(pb_tracker, i)

}

close(pb_tracker)
cat("\n")


# ============================================================================ #
# 2c.  Aggregate across multiple visits to the same page
# ============================================================================ #

raw <- aggregate_list_cols(raw)



# =============================================================================
# =============================================================================
# 3.  PARSE KEY LOG JSON
# =============================================================================
# =============================================================================

# ============================================================================ #
# 3a.  Helper function
# ============================================================================ #

# Computes keystroke statistics and input-jump indicators from a parsed key log
# data frame (one row per key event). Returns a named list whose names match
# the output column suffixes used in section 3b.
compute_keylog_stats <- function(klog) {

  time_diff <- diff(klog$time)

  ij_vals <- if ("jump" %in% names(klog)) {
    klog$jump[klog$key == "INPUT_JUMP" & !is.na(klog$jump)]
  } else {
    numeric(0)
  }

  list(
    str             = paste(klog$key, collapse = "|"),
    num             = nrow(klog),
    mean            = mean(time_diff,   na.rm = TRUE),
    median          = median(time_diff, na.rm = TRUE),
    sd              = sd(time_diff,     na.rm = TRUE),
    inputjump       = as.integer(length(ij_vals) > 0),
    inputjump_count = length(ij_vals),
    inputjump_sum   = if (length(ij_vals) > 0) sum(ij_vals) else 0,
    inputjump_max   = if (length(ij_vals) > 0) max(ij_vals) else NA_real_
  )

}


# ============================================================================ #
# 3b.  Initialise output columns (one set per key log)
# ============================================================================ #

stat_names <- c("str", "num", "mean", "median", "sd",
                "inputjump", "inputjump_count", "inputjump_sum", "inputjump_max")

for (entry in keylogs) {
  for (nm in stat_names) {
    raw[[paste0(entry$col, "_", nm)]] <- NA
  }
}


# ============================================================================ #
# 3c.  Compute keystroke statistics (loops over all key logs in config)
# ============================================================================ #

kl_n_empty      <- setNames(rep(0L, length(keylogs)), keylog_cols)
kl_n_salvaged   <- setNames(rep(0L, length(keylogs)), keylog_cols)
kl_n_incomplete <- setNames(rep(0L, length(keylogs)), keylog_cols)

cat("\n[3/6] Parsing key log JSON\n")
pb_keylog <- utils::txtProgressBar(min = 0, max = max(1, n_rows), style = 3, width = 30)

for (i in seq_len(n_rows)) {

  for (entry in keylogs) {

    col_name <- entry$col
    cell_val <- raw[i, col_name][[1]]

    # Skip empty or missing key logs
    if (is.na(cell_val) || cell_val == "" || cell_val == "[]") {
      kl_n_empty[[col_name]] <- kl_n_empty[[col_name]] + 1
      next
    }

    # Attempt to repair truncated JSONs before parsing
    if (startsWith(cell_val, "[") && !endsWith(cell_val, "]")) {
      cell_val <- salvage(cell_val)
      kl_n_salvaged[[col_name]] <- kl_n_salvaged[[col_name]] + 1
    }

    klog <- tryCatch(fromJSON(cell_val), error = function(e) NULL)

    if (is.null(klog)) {
      cat("Row", i, "[", col_name, "] skipped -> INCOMPLETE keylog JSON\n")
      kl_n_incomplete[[col_name]] <- kl_n_incomplete[[col_name]] + 1
      next
    }

    stats <- compute_keylog_stats(klog)
    for (nm in names(stats)) {
      raw[[paste0(col_name, "_", nm)]][i] <- stats[[nm]]
    }

  }

  utils::setTxtProgressBar(pb_keylog, i)

}

close(pb_keylog)
cat("\n")


# ============================================================================ #
# 3d.  Word and character counts of submitted text (loops over all key logs)
# ============================================================================ #

for (entry in keylogs) {
  col_name <- entry$col
  text_var <- entry$text_var

  word_counts <- str_count(raw[[text_var]], "\\S+")
  raw[[paste0(col_name, "_wordCount")]] <- ifelse(is.na(word_counts), 0L, word_counts)

  char_counts <- nchar(raw[[text_var]])
  raw[[paste0(col_name, "_charCount")]] <- ifelse(is.na(char_counts), 0L, char_counts)
}



# =============================================================================
# =============================================================================
# 4.  RECONSTRUCT TYPED TEXT FROM KEYSTROKES
# =============================================================================
# =============================================================================

# Replays the keystroke sequence to reconstruct what the participant typed.
# Special keys (modifiers, arrows, etc.) and common shortcuts are ignored.
# Backspace removes the last character from the output buffer.
reconstruct_text <- function(keylog_str) {

  if (is.na(keylog_str) || keylog_str == "") return("")

  keys   <- unlist(strsplit(keylog_str, "\\|"))
  output <- character(0)

  skip_keys <- c(
    "Shift", "CapsLock", "INPUT_JUMP", "Control", "Alt", "Tab",
    "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
    "Up", "Down", "Left", "Right",
    "Home", "End", "PageUp", "PageDown",
    "Insert", "Delete", "Escape", "Enter",
    "Meta"
  )

  i <- 1
  while (i <= length(keys)) {
    k <- keys[i]

    # Skip modifier and special keys; also skip Control+c/v/a shortcuts
    if (k %in% skip_keys) {
      if (k == "Control" && i < length(keys)) {
        next_key <- keys[i + 1]
        if (next_key %in% c("c", "v", "a", "C", "V", "A")) {
          i <- i + 2
          next
        }
      }
      i <- i + 1
      next
    }

    # Backspace removes the last character from the output buffer
    if (k == "Backspace") {
      if (length(output) > 0) output <- output[-length(output)]
      i <- i + 1
      next
    }

    output <- c(output, k)
    i <- i + 1
  }

  sub("[[:space:]]+$", "", paste(output, collapse = ""))

}

# For each key log: reconstruct typed text and compute normalised Levenshtein
# similarity against the submitted answer (1 = perfect match, 0 = no overlap).
for (entry in keylogs) {

  col_name  <- entry$col
  text_var  <- entry$text_var
  recon_col <- paste0(col_name, "_reconstructedInput")
  sim_col   <- paste0(col_name, "_levenshtein")

  raw[[recon_col]] <- sapply(
    raw[[paste0(col_name, "_str")]], reconstruct_text, USE.NAMES = FALSE
  )

  raw[[sim_col]] <- mapply(function(original, reconstructed) {
    if (is.na(original))      original      <- ""
    if (is.na(reconstructed)) reconstructed <- ""
    original <- gsub("\r", "", original)
    lev   <- stringdist(reconstructed, original, method = "lv")
    denom <- max(nchar(original), nchar(reconstructed))
    if (denom == 0) 1 else 1 - lev / denom
  }, raw[[text_var]], raw[[recon_col]], USE.NAMES = FALSE)

}



# =============================================================================
# =============================================================================
# 5.  EXPORT
# =============================================================================
# =============================================================================

# Drop raw passthrough columns before export — these are already in the main
# dataset and would create merge conflicts if included in tracker.xlsx.
raw <- raw %>%
  select(-any_of(c("tracking_json", all_of(keylog_cols), all_of(text_var_cols))))

write_xlsx(raw, path = output_path)



# =============================================================================
# =============================================================================
# 6.  TRACKER CLEANING REPORT
# =============================================================================
# =============================================================================

report_path     <- "output/tracker_cleaning_report.txt"
tracker_n_valid <- total_rows - tracker_n_invalid - tracker_n_salvaged

sep  <- strrep("=", 65)
sep2 <- strrep("-", 65)

lines <- c(
  "",
  sep,
  "TRACKER CLEANING REPORT",
  sprintf("Script: clean_tracker_V2.R"),
  sprintf("File:   %s", input_raw),
  sprintf("Date:   %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  sprintf("Rows:   %d", total_rows),
  sep,
  "",
  "This report summarises how many tracker and key log JSON records were",
  "successfully parsed, salvaged (truncated but repaired), or could not be",
  "recovered. Use it to assess data completeness before running main.R / main.do.",
  "",
  "For the full list of survey questions and their Qualtrics export column",
  sprintf("names, see: %s", if (exists("qid_table_path")) qid_table_path else "qualtrics_variable_list.txt"),

  # --- Tracker JSON ---
  "",
  "TRACKER JSON",
  sep2,
  sprintf("  Valid:            %d", tracker_n_valid),
  sprintf("  Salvaged:         %d  (truncated; repaired before parsing)", tracker_n_salvaged),
  sprintf("  Invalid:          %d  (unparseable; tracker vars = NA for these rows)", tracker_n_invalid)
)

tracker_unknown_qids_unique <- unique(tracker_unknown_qids)
if (length(tracker_unknown_qids_unique) > 0) {
  lines <- c(lines,
    sprintf("  Unknown QIDs:     %d  (not in qid_map; check 'unknown_*' columns in tracker.xlsx)", length(tracker_unknown_qids_unique)),
    sprintf("    -> %s", tracker_unknown_qids_unique)
  )
} else {
  lines <- c(lines, "  Unknown QIDs:     0")
}

# --- Key log JSON (one block per key log) ---
for (entry in keylogs) {
  col_name <- entry$col
  text_var <- entry$text_var

  n_empty      <- kl_n_empty[[col_name]]
  n_salvaged   <- kl_n_salvaged[[col_name]]
  n_incomplete <- kl_n_incomplete[[col_name]]
  n_valid      <- total_rows - n_empty - n_incomplete

  lines <- c(lines,
    "",
    sprintf("KEY LOG: %s  (text variable: %s)", col_name, text_var),
    sep2,
    sprintf("  Valid:            %d", n_valid),
    sprintf("  Empty:            %d  (no keystrokes recorded)", n_empty),
    sprintf("  Salvaged:         %d  (truncated; repaired before parsing)", n_salvaged),
    sprintf("  Incomplete:       %d  (truncated; could not be repaired; stats = NA)", n_incomplete)
  )
}

# --- Issues ---
issues <- character(0)

if (tracker_n_invalid > 0)
  issues <- c(issues, sprintf("%d tracker row(s) unparseable -> NA tracker variables", tracker_n_invalid))

for (entry in keylogs) {
  n <- kl_n_incomplete[[entry$col]]
  if (n > 0)
    issues <- c(issues, sprintf("%d key log row(s) [%s] could not be repaired -> NA keystroke stats", n, entry$col))
}

if (length(tracker_unknown_qids_unique) > 0)
  issues <- c(issues, sprintf("%d unknown QID(s) -> fallback column names in tracker.xlsx", length(tracker_unknown_qids_unique)))

lines <- c(lines, "", "ISSUES", sep2)

if (length(issues) == 0) {
  lines <- c(lines, "  None.")
} else {
  lines <- c(lines, sprintf("  [!] %s", issues))
}

lines <- c(lines, sep, "")

writeLines(lines, report_path)
cat(sprintf("Report saved to: %s\n", report_path))
cat(paste(lines, collapse = "\n"), "\n", sep = "")
