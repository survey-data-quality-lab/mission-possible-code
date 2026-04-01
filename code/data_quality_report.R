# =============================================================================
# Script:  data_quality_report.R
# Author:  Sören Harrs
# Date:    2026-03-20
#
# Purpose: R equivalent of data_quality_report.do. Produces a plain-text
#          data quality report from all.RData (output of main.R).
#
# Run AFTER main.R — data/all.RData must exist before running this.
#
# Input:   data/all.RData
# Output:  output/data_quality_reportR.txt
# =============================================================================

if (!exists("report_out")) {
  report_out <- "output/data_quality_reportR.txt"
}

input_all <- "data/all.RData"
if (!exists("df")) {
  load(input_all)   # loads df
}


# =============================================================================
# Helper functions
# =============================================================================

n_where <- function(cond) sum(cond, na.rm = TRUE)

pct <- function(n, total) n / total * 100

# Format a flag-table row: label (left-aligned), failed count+%, passed count+%
fmt_row <- function(label, n_fail, n_total) {
  n_pass <- n_total - n_fail
  sprintf("  %-28s  %5d  (%4.1f%%)     %5d  (%5.1f%%)",
          label, n_fail, pct(n_fail, n_total), n_pass, pct(n_pass, n_total))
}

# Format an exclusion row: label (left-aligned in 44 chars), count, %
fmt_excl <- function(label, n, total) {
  sprintf("    %-44s %5d  (%4.1f%%)", label, n, pct(n, total))
}


# =============================================================================
# 1. Compute statistics
# =============================================================================

N      <- nrow(df)
n_incl <- n_where(df$exclusion == 0)
n_excl <- n_where(df$exclusion == 1)

n_incomplete <- n_where(df$Finished != "True")
n_preview    <- n_where(df$Status   != "IP Address")
n_dup_id     <- n_where(df$flag_id  == 1 & df$Finished == "True")

platform <- df$study[1]
date_min <- format(min(df$t, na.rm = TRUE), "%d %b %Y")
date_max <- format(max(df$t, na.rm = TRUE), "%d %b %Y")

# --- Attrition (real incomplete responses only) ---

df_drop <- df[df$Finished != "True" & df$Status == "IP Address", ]
n_drop  <- nrow(df_drop)

n_d0  <- n_where(df_drop$Progress == 0)
n_d1  <- n_where(df_drop$Progress >= 1  & df_drop$Progress < 25)
n_d25 <- n_where(df_drop$Progress >= 25 & df_drop$Progress < 50)
n_d50 <- n_where(df_drop$Progress >= 50 & df_drop$Progress < 75)
n_d75 <- n_where(df_drop$Progress >= 75)

pct_drop <- function(n) if (n_drop > 0) pct(n, n_drop) else 0

# --- Quality flags (analysis sample only) ---

df_a <- df[df$exclusion == 0, ]
N_a  <- nrow(df_a)

n_att    <- n_where(df_a$flag_attention == 1)
n_vid    <- n_where(df_a$flag_video     == 1)
n_typed  <- n_where(df_a$flag_typed     == 1)
n_ts     <- n_where(df_a$ok_typedspeed  == 0)
n_ip     <- n_where(df_a$flag_ip        == 1)
n_nokeys <- n_where(df_a$flag_nokeys    == 1)
n_paste  <- n_where(df_a$flag_paste     == 1)
n_jump   <- n_where(df_a$flag_inputjump == 1)
n_speed  <- n_where(df_a$flag_speed     == 1)

n_pass <- n_where(df_a$all_passed == 1)
n_fail <- N_a - n_pass


# =============================================================================
# 2. Build report lines
# =============================================================================

S1 <- strrep("=", 65)
S2 <- strrep("-", 65)
S3 <- paste0("  ", strrep("-", 58))

lines <- c(

  S1,
  "DATA QUALITY REPORT",
  S1,
  sprintf("Generated : %s", format(Sys.time(), "%d %b %Y  %H:%M:%S")),
  sprintf("Platform  : %s", platform),
  sprintf("Date range: %s \u2013 %s", date_min, date_max),
  sprintf("Input     : %s", input_all),
  "",

  # --- 1. Sample Overview ---
  S2,
  "1.  SAMPLE OVERVIEW",
  S2,
  "",
  sprintf("  %-46s %6d", "Total observations (raw)", N),
  "",
  "  Exclusion criteria (may overlap across rows):",
  fmt_excl("Incomplete survey  (Finished != True)",   n_incomplete, N),
  fmt_excl("Survey preview     (Status  != IP Addr)", n_preview,    N),
  fmt_excl("Duplicate platform ID (later entry)",     n_dup_id,     N),
  "",
  fmt_excl("Total excluded  (exclusion == 1)",        n_excl, N),
  fmt_excl("Analysis sample (exclusion == 0)",        n_incl, N),
  "",

  # --- 2. Survey Attrition ---
  S2,
  sprintf("2.  SURVEY ATTRITION  (N = %d incomplete real responses)", n_drop),
  S2,
  "",
  "  Progress at drop-off:",
  "",
  "    Range                          N    % of incomplete",
  "    ------------------------------------------------",
  sprintf("    0%%  (never left landing page) %5d  (%4.1f%%)", n_d0,  pct_drop(n_d0)),
  sprintf("    1  \u2013 24%%                      %5d  (%4.1f%%)", n_d1,  pct_drop(n_d1)),
  sprintf("    25 \u2013 49%%                      %5d  (%4.1f%%)", n_d25, pct_drop(n_d25)),
  sprintf("    50 \u2013 74%%                      %5d  (%4.1f%%)", n_d50, pct_drop(n_d50)),
  sprintf("    75 \u2013 99%%                      %5d  (%4.1f%%)", n_d75, pct_drop(n_d75)),
  "    ------------------------------------------------",
  sprintf("    Total                         %5d", n_drop),
  "",

  # --- 3. Main Data Quality Flags ---
  S2,
  sprintf("3.  MAIN DATA QUALITY FLAGS  (N = %d)", N_a),
  S2,
  "",
  "  Check                            Failed              Passed",
  S3,
  fmt_row("Attention check",           n_att,    N_a),
  fmt_row("Video check",               n_vid,    N_a),
  fmt_row("Typed text",                n_typed,  N_a),
  fmt_row("Typed with typical speed",  n_ts,     N_a),
  fmt_row("Unique IP address",         n_ip,     N_a),
  S3,
  "",
  fmt_row("Keystrokes > 0",            n_nokeys, N_a),
  fmt_row("No paste event",            n_paste,  N_a),
  fmt_row("No input jump >= 50 chars", n_jump,   N_a),
  fmt_row("Typing speed > 75 ms",      n_speed,  N_a),
  "",
  "  Note: Typed text = keystrokes > 0 AND no paste AND no input jump.",
  "        Typed with typical speed additionally requires speed > 75 ms.",
  "",

  # --- 4. Summary ---
  S2,
  "4.  SUMMARY",
  S2,
  "",
  sprintf("  %-44s %5d  (%4.1f%%)", "All main checks passed (all_passed == 1)", n_pass, pct(n_pass, N_a)),
  sprintf("  %-44s %5d  (%4.1f%%)", "At least one check failed",                n_fail, pct(n_fail, N_a)),
  "",
  S1

)

writeLines(lines, report_out, useBytes = FALSE)
cat(sprintf("Report written to: %s\n", report_out))
