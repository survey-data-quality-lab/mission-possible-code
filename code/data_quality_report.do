* =============================================================================
* Script:  data_quality_report.do
* Author:  Sören Harrs
* Date:    2026-03-20
*
* Purpose: Produces a clean plain-text data quality report. All statistics are
*          computed first, then written via file write — no Stata command echo.
*
* Input:   data/all.dta
* Output:  output/data_quality_report.txt
* =============================================================================


********************************************************************************
*****  0. SETTINGS
********************************************************************************

local output_all "data/all.dta"
if "$DQ_REPORT_OUT" != "" local report_out "$DQ_REPORT_OUT"
else                       local report_out "output/data_quality_report.txt"


********************************************************************************
*****  1. COMPUTE STATISTICS
********************************************************************************

use "`output_all'", clear

* --- Section 1: Sample overview ---

quietly count
local N = r(N)

quietly count if exclusion == 0
local n_incl = r(N)

quietly count if exclusion == 1
local n_excl = r(N)

quietly count if Finished != "True"
local n_incomplete = r(N)

quietly count if Status != "IP Address"
local n_preview = r(N)

quietly count if flag_id == 1 & Finished == "True"
local n_dup_id = r(N)

* Platform and date range
local f_platform = study[1]

quietly summarize t
local f_date_min : display %tdDD_Mon_CCYY dofc(r(min))
local f_date_max : display %tdDD_Mon_CCYY dofc(r(max))

* --- Section 2: Attrition (real incomplete responses only) ---

preserve
quietly keep if Finished != "True" & Status == "IP Address"

quietly count
local n_drop = r(N)

quietly count if Progress == 0
local n_d0  = r(N)

quietly count if Progress >= 1 & Progress < 25
local n_d1  = r(N)

quietly count if Progress >= 25 & Progress < 50
local n_d25 = r(N)

quietly count if Progress >= 50 & Progress < 75
local n_d50 = r(N)

quietly count if Progress >= 75
local n_d75 = r(N)

restore

* --- Section 3: Quality flags (analysis sample only) ---

preserve
quietly keep if exclusion == 0

quietly count
local N_a = r(N)

quietly count if flag_attention  == 1
local n_att    = r(N)
quietly count if flag_video      == 1
local n_vid    = r(N)
quietly count if flag_nokeys     == 1
local n_nokeys = r(N)
quietly count if flag_paste      == 1
local n_paste  = r(N)
quietly count if flag_inputjump  == 1
local n_jump   = r(N)
quietly count if flag_speed      == 1
local n_speed  = r(N)
quietly count if flag_ip         == 1
local n_ip     = r(N)
quietly count if flag_typed      == 1
local n_typed  = r(N)
quietly count if ok_typedspeed   == 0
local n_ts     = r(N)
quietly count if all_passed      == 1
local n_pass   = r(N)

restore

local n_fail = `N_a' - `n_pass'


********************************************************************************
*****  2. FORMAT VALUES INTO DISPLAY STRINGS
********************************************************************************

* Section 1
local f_N            : display %6.0f  `N'
local f_n_incomplete : display %5.0f  `n_incomplete'
local f_pct_incomp   : display %4.1f  `n_incomplete' / `N' * 100
local f_n_preview    : display %5.0f  `n_preview'
local f_pct_preview  : display %4.1f  `n_preview'    / `N' * 100
local f_n_dup        : display %5.0f  `n_dup_id'
local f_pct_dup      : display %4.1f  `n_dup_id'     / `N' * 100
local f_n_excl       : display %5.0f  `n_excl'
local f_pct_excl     : display %4.1f  `n_excl'       / `N' * 100
local f_n_incl       : display %5.0f  `n_incl'
local f_pct_incl     : display %4.1f  `n_incl'       / `N' * 100

* Section 2 — attrition
local f_n_drop  : display %5.0f  `n_drop'
local f_n_d0    : display %5.0f  `n_d0'
local f_n_d1    : display %5.0f  `n_d1'
local f_n_d25   : display %5.0f  `n_d25'
local f_n_d50   : display %5.0f  `n_d50'
local f_n_d75   : display %5.0f  `n_d75'

local f_pct_d0  : display %4.1f  cond(`n_drop' > 0, `n_d0'  / `n_drop' * 100, 0)
local f_pct_d1  : display %4.1f  cond(`n_drop' > 0, `n_d1'  / `n_drop' * 100, 0)
local f_pct_d25 : display %4.1f  cond(`n_drop' > 0, `n_d25' / `n_drop' * 100, 0)
local f_pct_d50 : display %4.1f  cond(`n_drop' > 0, `n_d50' / `n_drop' * 100, 0)
local f_pct_d75 : display %4.1f  cond(`n_drop' > 0, `n_d75' / `n_drop' * 100, 0)

* Section 3 — flag table (failed count, failed %, passed count, passed %)
foreach c in att vid nokeys paste jump speed ip typed ts {

    if "`c'" == "ts" local nn = `n_ts'
    else             local nn = `n_`c''
    local np = `N_a' - `nn'

    local ff_`c'  : display %5.0f `nn'
    local fp_`c'  : display %4.1f `nn' / `N_a' * 100
    local pf_`c'  : display %5.0f `np'
    local pp_`c'  : display %4.1f `np' / `N_a' * 100
}

* Section 4
local f_Na       : display %5.0f  `N_a'
local f_n_pass   : display %5.0f  `n_pass'
local f_pct_pass : display %4.1f  `n_pass' / `N_a' * 100
local f_n_fail   : display %5.0f  `n_fail'
local f_pct_fail : display %4.1f  `n_fail' / `N_a' * 100


********************************************************************************
*****  3. WRITE REPORT
********************************************************************************

local S1 "================================================================="
local S2 "-----------------------------------------------------------------"
local S3 "  ----------------------------------------------------------"

file open rpt using "`report_out'", write replace

file write rpt "`S1'"                                                                          _n
file write rpt "DATA QUALITY REPORT"                                                           _n
file write rpt "`S1'"                                                                          _n
file write rpt "Generated : $S_DATE  $S_TIME"                                                 _n
file write rpt "Platform  : `f_platform'"                                                      _n
file write rpt "Date range: `f_date_min' – `f_date_max'"                                      _n
file write rpt "Input     : `output_all'"                                                      _n
file write rpt ""                                                                              _n

* --- 1. Sample Overview ---

file write rpt "`S2'"                                                                          _n
file write rpt "1.  SAMPLE OVERVIEW"                                                           _n
file write rpt "`S2'"                                                                          _n
file write rpt ""                                                                              _n
file write rpt "  Total observations (raw)                        `f_N'"                      _n
file write rpt ""                                                                              _n
file write rpt "  Exclusion criteria (may overlap across rows):"                              _n
file write rpt "    Incomplete survey  (Finished != True)      `f_n_incomplete'  (`f_pct_incomp'%)"  _n
file write rpt "    Survey preview     (Status  != IP Addr)    `f_n_preview'  (`f_pct_preview'%)"    _n
file write rpt "    Duplicate platform ID (later entry)        `f_n_dup'  (`f_pct_dup'%)"           _n
file write rpt ""                                                                              _n
file write rpt "    Total excluded  (exclusion == 1)           `f_n_excl'  (`f_pct_excl'%)"         _n
file write rpt "    Analysis sample (exclusion == 0)           `f_n_incl'  (`f_pct_incl'%)"         _n
file write rpt ""                                                                              _n

* --- 2. Survey Attrition ---

file write rpt "`S2'"                                                                          _n
file write rpt "2.  SURVEY ATTRITION  (N = `f_n_drop' incomplete real responses)"             _n
file write rpt "`S2'"                                                                          _n
file write rpt ""                                                                              _n
file write rpt "  Progress at drop-off:"                                                      _n
file write rpt ""                                                                              _n
file write rpt "    Range                          N    % of incomplete"                       _n
file write rpt "    ------------------------------------------------"                         _n
file write rpt "    0%  (never left landing page) `f_n_d0'  (`f_pct_d0'%)"                   _n
file write rpt "    1  – 24%                      `f_n_d1'  (`f_pct_d1'%)"                   _n
file write rpt "    25 – 49%                      `f_n_d25'  (`f_pct_d25'%)"                 _n
file write rpt "    50 – 74%                      `f_n_d50'  (`f_pct_d50'%)"                 _n
file write rpt "    75 – 99%                      `f_n_d75'  (`f_pct_d75'%)"                 _n
file write rpt "    ------------------------------------------------"                         _n
file write rpt "    Total                         `f_n_drop'"                                 _n
file write rpt ""                                                                              _n

* --- 3. Data Quality Flags ---

file write rpt "`S2'"                                                                          _n
file write rpt "3.  MAIN DATA QUALITY FLAGS  (N = `f_Na')"                                         _n
file write rpt "`S2'"                                                                          _n
file write rpt ""                                                                              _n
file write rpt "  Check                          Failed              Passed"                  _n
file write rpt "`S3'"                                                                          _n
file write rpt "  Attention check               `ff_att'  (`fp_att'%)     `pf_att'  (`pp_att'%)"      _n
file write rpt "  Video check                   `ff_vid'  (`fp_vid'%)     `pf_vid'  (`pp_vid'%)"      _n
file write rpt "  Typed text                    `ff_typed'  (`fp_typed'%)     `pf_typed'  (`pp_typed'%)" _n
file write rpt "  Typed with typical speed      `ff_ts'  (`fp_ts'%)     `pf_ts'  (`pp_ts'%)"          _n
file write rpt "  Unique IP address             `ff_ip'  (`fp_ip'%)     `pf_ip'  (`pp_ip'%)"          _n
file write rpt "`S3'"                                                                          _n
file write rpt ""                                                                              _n
file write rpt "  Keystrokes > 0                `ff_nokeys'  (`fp_nokeys'%)     `pf_nokeys'  (`pp_nokeys'%)" _n
file write rpt "  No paste event                `ff_paste'  (`fp_paste'%)     `pf_paste'  (`pp_paste'%)"  _n
file write rpt "  No input jump >= 50 chars     `ff_jump'  (`fp_jump'%)     `pf_jump'  (`pp_jump'%)"  _n
file write rpt "  Typing speed > 75 ms          `ff_speed'  (`fp_speed'%)     `pf_speed'  (`pp_speed'%)" _n
file write rpt ""                                                                              _n
file write rpt "  Note: Typed text = keystrokes > 0 AND no paste AND no input jump."         _n
file write rpt "        Typed with typical speed additionally requires speed > 75 ms."        _n
file write rpt ""                                                                              _n

* --- 4. Summary ---

file write rpt "`S2'"                                                                          _n
file write rpt "4.  SUMMARY"                                                                   _n
file write rpt "`S2'"                                                                          _n
file write rpt ""                                                                              _n
file write rpt "  All main checks passed (all_passed == 1)   `f_n_pass'  (`f_pct_pass'%)"            _n
file write rpt "  At least one check failed                  `f_n_fail'  (`f_pct_fail'%)"            _n
file write rpt ""                                                                              _n
file write rpt "`S1'"                                                                          _n

file close rpt

di as result `"Report written to: `report_out'"'
