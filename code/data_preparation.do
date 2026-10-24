*******************************************************************************
* CFPS 2014/2018: data preparation workflow
* Purpose: document the Stata workflow used before the R analysis
*
* Raw CFPS files are not distributed with this repository. Set the folders
* below to the location of data obtained through an authorized CFPS account.
* File and variable names may differ slightly by the CFPS release version.
*******************************************************************************

version 17
clear all
set more off

* 1. Project folders ----------------------------------------------------------

global raw_data    "path/to/authorized/cfps/files"
global working     "path/to/project/working"
global output      "path/to/project/data"

* 2. Prepare the 2014 household file ------------------------------------------

use "${raw_data}/2014/cfps2014famecon.dta", clear

* Retain the variables used in this project.
keep fid10 provcd14 food expense
rename provcd14 Province_2014
rename food     FOOD_2014
rename expense  TOTAL_2014

* CFPS special codes: non-response, not applicable, unknown, etc.
foreach var of varlist FOOD_2014 TOTAL_2014 {
    replace `var' = . if inlist(`var', -10, -9, -8, -2, -1)
}

isid fid10
save "${working}/cfps2014_household.dta", replace

* 3. Prepare the 2018 household file ------------------------------------------

use "${raw_data}/2018/cfps2018famecon.dta", clear

keep fid10 provcd18 food expense
rename provcd18 Province_2018
rename food     FOOD_2018
rename expense  TOTAL_2018

foreach var of varlist FOOD_2018 TOTAL_2018 {
    replace `var' = . if inlist(`var', -10, -9, -8, -2, -1)
}

isid fid10
save "${working}/cfps2018_household.dta", replace

* 4. Match households observed in both waves ----------------------------------

use "${working}/cfps2014_household.dta", clear
merge 1:1 fid10 using "${working}/cfps2018_household.dta"

* Keep households observed in both 2014 and 2018.
keep if _merge == 3
drop _merge

* Use the common household identifier in the public-facing analysis file.
rename fid10 ID

* 5. Construct the outcome variables ------------------------------------------

gen Engel_2014 = FOOD_2014 / TOTAL_2014
gen Engel_2018 = FOOD_2018 / TOTAL_2018

label variable Engel_2014 "Engel coefficient, 2014"
label variable Engel_2018 "Engel coefficient, 2018"

* 6. Merge the province-level 2014 DFI index ----------------------------------

* Before this step, prepare an authorized province-DFI file with the variables
* Province_2014 and DFI. Province codes/names must use the same convention as
* the CFPS file.
merge m:1 Province_2014 using "${raw_data}/dfi/province_dfi_2014.dta"
keep if _merge == 3
drop _merge

rename Province_2014 Province

* 7. Create the high/low DFI indicator ----------------------------------------

quietly summarize DFI, detail
gen Treat_p = (DFI >= r(p50)) if !missing(DFI)
label define treat_label 0 "Low DFI" 1 "High DFI"
label values Treat_p treat_label

order ID Treat_p Province FOOD_2014 FOOD_2018 TOTAL_2014 TOTAL_2018 ///
    Engel_2014 Engel_2018 DFI

* 8. Export the analysis file --------------------------------------------------

export excel using "${output}/analysis_data.xlsx", ///
    sheet("Sheet1") firstrow(variables) replace

*******************************************************************************
* The exported file is read by code/analysis.R.
*******************************************************************************
