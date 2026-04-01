* =============================================================================
* Script:  main.do
* Author:  Sören Harrs
* Date:    2026-04-01
*
* Purpose: Imports the raw Qualtrics Excel export, merges tracker output from
*          clean_tracker.R, defines exclusion criteria and data quality flags,
*          and writes exports.
*
* Run AFTER clean_tracker.R — tracker.xlsx must exist before running this.
*
* Sections:
*   0. Settings [UPDATE and VERIFY]
*   1. Import data
*   2. Merge tracker data
*   3. Define data quality flags
*   4. Save datasets
*   5. Exports
*
*
* Outputs (written to data/):
*   main.dta                — analysis dataset; excluded observations removed
*   all.dta                 — full dataset with exclusion flags retained
*
* Outputs (written to output/):
*   keep_ids.xlsx           — participant IDs passing all checks (two-stage procedure)
*   bonus_ids.xlsx          — participant IDs and bonus amounts from dictator game
*   data_quality_report.txt — plain-text data quality report
*   codebook.txt            — variable-level codebook for the main dataset
* =============================================================================


********************************************************************************
*****  0. SETTINGS
********************************************************************************

* ---------------------------------------------------------------------------- *
* REQUIRED — always update
* ---------------------------------------------------------------------------- *

* [1] Working directory
cd "C://Users/sharrs/Dropbox/Project Bot Catching/Github/mission-possible-code"

* [2] Input data
local input_raw "data raw/Mission_Possible_Survey_V1_TESTDATA.xlsx"

* ---------------------------------------------------------------------------- *
* VERIFY — check that these are correct for your dataset. Adjust if needed.
*
* Defaults match standard Prolific setup using Mission_Possible_Baseline_Survey.qsf
* ---------------------------------------------------------------------------- *

* [3] Platform name
local platform "prolific"  

* [4] Participant ID variable name in raw data
local participant_id "prolific_id"

* [5] Identify variable names for key survey variables.
*     CHECK "output/qualtrics_variable_list.txt" or your raw data export. 
*     Enter the variable names of the video check, open text response, 
*     and dictator game choice in your dataset inside the parentheses "". 
*     Default matches Mission_Possible_Baseline_Survey.qsf. 

local video    "video"      	// video check question (e.g. "Q34")
local text     "text"      		// open text question for typing checks (e.g. "Q16")
local dictator "dictator"       // dictator game choice (e.g. "Q14")
local ip_address "ip_address"   // IP address variable (e.g. "IPAddress")

* Attention check questions are attention1_3 and attention1_4 by default. If your attention checks differ, adjust the logic in section 3.1 accordingly.

* Correct answer for video check is 3169 by default. If your video check question differs, adjust the logic in section 3.2 accordingly. 


* ---------------------------------------------------------------------------- *
* OPTIONAL — leave as-is unless you have a reason to change
* ---------------------------------------------------------------------------- *

* Tracker data (output of clean_tracker.R)
local tracker "data/tracker.xlsx"

* Output datasets
local output_main     "data/main.dta"
local output_all      "data/all.dta"

* Export: IDs of those who passed all main checks (for two-stage procedure)
local keep_ids "output/keep_ids.xlsx"

* Export: bonus payments for dictator game
local bonus_ids "output/bonus_ids.xlsx"

* Export: Data quality report output path (leave empty to skip)
local dq_report_out "output/data_quality_report.txt"

* Export: Codebook output path (leave empty to skip)
local codebook_out "output/codebook.txt"



********************************************************************************
********************************************************************************
*****  1. IMPORT DATA
********************************************************************************
********************************************************************************

clear all
import excel "`input_raw'", sheet("Sheet0") firstrow

* Drop the extra header row imported by Qualtrics
drop in 1

* Destring numeric variables
destring _all, replace

* Verify that columns configured in settings [4] and [5] exist in the imported data
foreach v in `participant_id' `video' `text' `dictator' {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "Column not found in imported data: `v'"
        di as error "Check settings [4]/[5] and verify against data/qualtrics_variable_list.txt"
        error 111
    }
}

* Add study identifier
gen study = "`platform'"

* Parse timestamp
gen double t = clock(RecordedDate, "MDY hm")
gen day_of_month = day(dofc(t))
gen month        = month(dofc(t))

* ---------------------------------------------------------------------------- *
* Define exclusion flag. Observations are only dropped before saving the final
* dataset so that all raw data is preserved in intermediate files.
* ---------------------------------------------------------------------------- *

gen exclusion = 0

* Incomplete surveys
replace exclusion = 1 if Finished != "True"

* Survey previews
replace exclusion = 1 if Status != "IP Address"

* Pilot data (uncomment and adjust if needed)
*replace exclusion = 1 if day_of_month == 11 & month == 8

* ---------------------------------------------------------------------------- *
* Flag repeated platform IDs
* ---------------------------------------------------------------------------- *

gen str150 participant_id = ""

replace participant_id = `participant_id'

* Within each study-exclusion-participant_id group, sort by recorded time and
* flag every observation after the first (i.e. the later duplicate entries).

bysort study exclusion participant_id (t): gen flag_id = (_n > 1)

replace exclusion = 1 if flag_id == 1 & Finished == "True"

* ---------------------------------------------------------------------------- *
* Check number of completed and excluded observations
* ---------------------------------------------------------------------------- *

tab exclusion


********************************************************************************
********************************************************************************
*****  2. MERGE TRACKER DATA (after R cleaning)
********************************************************************************
********************************************************************************

* Import cleaned tracker data and save as Stata file
preserve

import excel "`tracker'", sheet("Sheet1") firstrow clear

save "data/tracker.dta", replace

restore

* Merge tracker variables onto main dataset

rename ResponseId responseid

merge 1:1 responseid using "data/tracker.dta", force

* Drop unmatched observations from tracker file (should not occur)
drop if _merge == 2

drop _merge



********************************************************************************
********************************************************************************
*****  3. DEFINE DATA QUALITY FLAGS
********************************************************************************
********************************************************************************

* ---------------------------------------------------------------------------- *
* 3.0 Standardise key variable names (create from [5] if not already named correctly)
* ---------------------------------------------------------------------------- *

capture confirm variable video
if _rc != 0 gen video = `video'

capture confirm variable text
if _rc != 0 gen text = `text'


* ============================================================================ *
* 3.1  INATTENTION FLAG
* ============================================================================ *

* --- Classic attention check (Qualtrics survey questions) ------------------- *

gen ok_attention  = cond(attention1_3 == "Strongly Disagree" & attention1_4 == "Strongly Agree", 1, 0)
gen flag_attention = 1 - ok_attention
label variable ok_attention   "Passed classic attention check"
label variable flag_attention  "Failed classic attention check"


* ============================================================================ *
* 3.2  VIDEO CHECK FLAG
* ============================================================================ *

tostring video, replace

* Strip spaces and punctuation before comparing against expected answer
gen video_clean = ustrregexra(video, "[[:punct:][:space:]]", "")

gen ok_video  = 0
replace ok_video = 1 if video_clean == "3169"
gen flag_video = 1 - ok_video
label variable ok_video   "Passed video check"
label variable flag_video  "Failed video check"


* ============================================================================ *
* 3.3  OPEN TEXT RESPONSE FLAGS
* ============================================================================ *

* --- No keystrokes recorded --------------------------------------------- *

* key_log_num: recode missing numbers to 0 (no keys pressed)
recode key_log_num . = 0

gen flag_nokeys = cond(key_log_num == 0, 1, 0)
gen ok_nokeys   = 1 - flag_nokeys
label variable ok_nokeys "Keystrokes > 0"

* --- Paste event -------------------------------------------------------- *

gen flag_paste = cond(`text'_paste == 1, 1, 0)
gen ok_paste   = 1 - flag_paste
label variable ok_paste "No paste event detected"

* --- Large input jump event --------------------------------------------- *
* A jump >= 50 characters suggests text was inserted without typing.

gen flag_inputjump = cond(key_log_inputjump == 1 & key_log_inputjump_max >= 50, 1, 0)
gen ok_inputjump   = 1 - flag_inputjump
label variable ok_inputjump "No input jump event >= 50 characters"

* --- Unusually fast typing speed ---------------------------------------- *
* Threshold: median inter-keystroke interval <= 75 ms.
* Observations with only one or zero keys have missing median and are flagged as well.

gen flag_speed = cond(key_log_median <= 75, 1, 0)
replace flag_speed = 1 if key_log_median == .

gen ok_speed = 1 - flag_speed
label variable ok_speed "Typing speed > 75 ms"

* --- Typed-text flag ---------------------------------------------------- *
* This composite flag combines paste, input jump, and no-keystroke
* indicators to improve detection coverage.

gen flag_typed = 0
replace flag_typed = 1 if flag_paste    == 1
replace flag_typed = 1 if flag_inputjump == 1
replace flag_typed = 1 if flag_nokeys   == 1

gen ok_typed = 1 - flag_typed
label variable ok_typed "Typed Text"

* --- Typed with typical speed ------------------------------------------- *
* Requires both the composite typed flag and the speed flag to pass.

gen ok_typedspeed = ok_typed * ok_speed
label variable ok_typedspeed "Typed text with typical speed"

* ============================================================================ *
* 3.4  DUPLICATE IP ADDRESS FLAG
* ============================================================================ *

* --- Duplicate IP address --------------------------------------------------- *

bysort study exclusion ip_address: ///
    gen flag_ip = _N

replace flag_ip = 0 if flag_ip == 1
replace flag_ip = 1 if flag_ip > 1

gen ok_ip = 1 - flag_ip
label variable ok_ip "Unique IP address"


* ============================================================================ *
* 3.5   SUMMARY FLAG: ALL MAIN CHECKS PASSED
* ============================================================================ *

gen all_passed = 0

replace all_passed = 1 if ///
    ok_attention  == 1 & ///
    ok_video      == 1 & ///
    ok_typed      == 1 & ///
    ok_typedspeed == 1 & ///
    ok_ip         == 1

label variable all_passed "All main checks passed"



********************************************************************************
********************************************************************************
*****  4. SAVE DATASETS
********************************************************************************
********************************************************************************

* Sort by recorded time (matches R sort order for 1:1 comparison)
sort t

* Save full dataset (including excluded observations)
save `output_all', replace

* Drop excluded observations
drop if exclusion == 1

* Drop useless Qualtrics variables 
drop RecipientLastName RecipientFirstName RecipientEmail ExternalReference UserLanguage *_FirstClick *_LastClick *_PageSubmit *_ClickCount

* Save cleaned main dataset 
save `output_main', replace



********************************************************************************
********************************************************************************
*****  5. EXPORTS
********************************************************************************
********************************************************************************


********************************************************************************
*****  5.1  TWO-STAGE PROCEDURE: PARTICIPANT IDs PASSING ALL CHECKS
********************************************************************************

* Export participant IDs of those who passed all main checks
* (used to invite participants to stage 2)

use `output_main', clear

preserve

keep if all_passed == 1
keep participant_id
count
local n_keep = r(N)

di as result "keep_ids: `n_keep' participant(s) passed all checks"

if `n_keep' == 0 {
    di as text "  No participants passed all checks — keep_ids.xlsx not written."
}
else {
    export excel using "`keep_ids'", firstrow(variables) replace
}

restore


********************************************************************************
*****  5.2  DICTATOR GAME BONUS PAYMENTS
********************************************************************************

* Selection procedure:
*   - 1% of dictators are selected (sel_d) to have their transfer implemented.
*   - An equal number of recipients (sel_r) are randomly drawn from the rest.
*   - Dictator bonus = 10 - give (endowment minus transfer).
*   - Recipient bonus = the matched dictator's transfer (give).

use `output_main', clear

preserve

capture confirm variable dictator
if _rc != 0 gen dictator = `dictator'

* Extract the dollar amount from the dictator choice string (format: "$X")
split dictator, parse("$")
destring dictator2, force replace
drop dictator1
rename dictator2 give

set seed 123

* Select approximately 1% of observations as dictators
gen u = runiform()
gen byte sel_d = (u < 0.01)
count if sel_d
local N = r(N)

di as result "Bonus payments: `N' dictator(s) selected (approx. 1% of `=_N')"

if `N' == 0 {
    di as text "  No subjects selected for bonus payment — bonus_ids.xlsx not written."
}
else {

    * Randomly select an equal number of recipients from the remainder
    gen v = runiform() if !sel_d
    egen vr = rank(v) if !sel_d, field
    gen byte sel_r = (!sel_d & vr <= `N')

    sort u

    * Compute dictator bonus
    gen bonus = 10 - give if sel_d

    * Keep selected dictators and recipients
    keep if sel_d | sel_r

    order give, a(bonus)

    * Assign recipient bonuses (equal to matched dictator's transfer)
    gen idx = _n
    replace bonus = give[_n - `N'] if _n > `N'

    keep participant_id bonus

    drop if bonus == 0

    count
    di as result "  `=r(N)' rows written to `bonus_ids' (dictators + recipients, excluding zero-bonus rows)"

    list
    export excel using "`bonus_ids'", firstrow(variables) replace

}

restore

********************************************************************************
*****  5.3  CODEBOOK
********************************************************************************

if "`codebook_out'" != "" {
    log using "`codebook_out'", text replace name(codebook_log)
    codebook, compact
    log close codebook_log
    di "Codebook written to: `codebook_out'"
}


********************************************************************************
*****  5.4  DATA QUALITY REPORT
********************************************************************************

if "`dq_report_out'" != "" {
    global DQ_REPORT_OUT "`dq_report_out'"
    quietly do "code/data_quality_report.do"

    quietly {
        capture confirm file "`dq_report_out'"
        if _rc == 0 {
            noisily di ""

            tempname rptfh
            file open `rptfh' using "`dq_report_out'", read text
            file read `rptfh' line
            while r(eof) == 0 {
                noisily di as text `"`line'"'
                file read `rptfh' line
            }
            file close `rptfh'
        }
        else {
            noisily di as error "Report file not found after generation: `dq_report_out'"
        }
    }

    macro drop DQ_REPORT_OUT
}



********************************************************************************
********************************************************************************
*****  6. LOAD MAIN DATASET
********************************************************************************
********************************************************************************

use `output_main', clear