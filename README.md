## Mission Possible: Clean Data Quality Trackers

This repository constructs data quality metrics from raw Qualtrics survey exports. 

The tracking data is cleaned, merged with the survey responses, and used to define five main data quality flags. The scripts export analysis-ready datasets, participant ID lists for the two-stage procedure, and a plain-text data quality report.

The default values are set to work with our [Mission_Possible_Survey_V1.qsf](https://github.com/survey-data-quality-lab/mission-possible/tree/03819bb4e7fdb9259a7d82d04e53e38ecc55b209/qualtrics%20survey%20file) survey. For testing, an example .xlsx file and .qsf file are provided.

You can adapt it to your own Qualtrics survey by following the instructions below. 

See https://github.com/survey-data-quality-lab/mission-possible for more information. 

**Requirements:** R ≥ 4.0 · Stata ≥ 14 (if using the Stata scripts)

---

## Folder structure

```
data raw/                          ← Qualtrics Excel export (.xlsx)
qualtrics survey file/             ← Qualtrics survey file (.qsf)
code/                              ← scripts listed below
data/                              ← cleaned datasets (written by scripts)
output/                            ← reports, codebook, ID lists (written by scripts)
```

---

## Scripts

| File | Role |
|---|---|
| `clean_tracker.R` | Parses tracker JSON and key log JSON; writes `tracker.xlsx` |
| `qsf_extract.R` | Extracts survey questions (QID) and export labels from the `.qsf` file; runs as part of `clean_tracker.R` |
| `main.do` / `main.R` | Main cleaning script (Stata / R); merges tracker output, defines data quality checks, and writes all outputs including the data quality report |
| `data_quality_report.do` / `data_quality_report.R` | Standalone script (Stata / R) to regenerate the data quality report from `all.dta` / `all.RData` |

---

## Workflow

### Step 0 — Download or clone the repository

Download or clone this repository to your computer, then open the project folder locally.

### Step 1 — Download files from Qualtrics

1. Export survey responses as an **Excel (.xlsx)** file (use **Export Labels**), and place it in `data raw/`.
2. Export the **Qualtrics survey (.qsf)** file (Survey → Tools → Import / Export → Export survey) and place it in `qualtrics survey file/`.

Note: make sure to export these two files at about the same time so there are no inconsistencies. 

### Step 2 — Run the R clean tracker script

Open `clean_tracker.R` and update the required settings at the top (section 0):

- `setwd(...)` — path to the project root         **[UPDATE]**
- `input_raw` — path to the raw Excel export      **[UPDATE]**
- `qsf_path` — path to the `.qsf` file            **[UPDATE]**

Then run the script. It calls `qsf_extract.R` automatically and writes the following outputs:

| File | Folder | Contents |
|---|---|---|
| `tracker.xlsx` | `data/` | Cleaned tracker and keystroke data; merged into main dataset in Step 3 |
| `tracker_cleaning_report.txt` | `output/` | How many tracker and key log rows were parsed, salvaged, or flagged |
| `qualtrics_variable_list.txt` | `output/` | Human-readable table of all survey questions and their Qualtrics export column names; constructed by `qsf_extract.R`  |
| `qid_map.R` | `code/` | Machine-readable table of all survey questions and their Qualtrics export column names; constructed by `qsf_extract.R` |

### Step 3 — Run the main cleaning script

The R and STATA scripts produce identical outputs. Open the chosen script and update plus verify the settings at the top (section 0):

**Option 3A — R (`main.R`)**

- If run in the same session as `clean_tracker.R`, the working directory and `input_raw` path are inherited automatically.
- Settings [3] to [5]                                 **[VERIFY]**

**Option 3B — STATA (`main.do`)**

- `cd` — path to the project root                    **[UPDATE]**
- `input_raw` — path to the raw Excel export         **[UPDATE]**
- Settings [3] to [5]                                **[VERIFY]**

Either script imports the raw survey data, merges `tracker.xlsx`, applies exclusion criteria and data quality flags, and writes the following outputs:

**Written to `data/`:**

| File | Contents |
|---|---|
| `main.RData` / `main.dta` | Cleaned dataset restricted to participants who pass all exclusion criteria |
| `all.RData` / `all.dta` | Full dataset including excluded participants, with exclusion and quality flags retained |

**Written to `output/`:**

| File | Contents |
|---|---|
| `keep_ids.xlsx` | Participant IDs of those who pass all main checks (used for the two-stage procedure) |
| `bonus_ids.xlsx` | Participant IDs and bonus payment amounts for selected dictators and recipients (zero-bonus rows dropped) |
| `data_quality_report.txt` | Plain-text data quality report covering exclusion and data quality metrics |
| `codebook.txt` / `codebook.xlsx` | Variable-level codebook for the main dataset |


---

## Notes

- The R and Stata scripts both read from the same raw Excel file and produce matching outputs.
- `tracker.xlsx` must exist before running `main.do` or `main.R`. Always run `clean_tracker.R` first.
- Typing-based checks (speed, paste, input jump) operate on the `key_log` column, which corresponds to the main open-text response. Multiple key log trackers can be processed simultaneously by adding entries to the `keylogs` list in `clean_tracker.R` section 0. But only `key_log` is used for constructing our main data quality checks in `main.do` and `main.R`.
