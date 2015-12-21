# Photometry
Eric Dose's R scripts etc for telescope photometry, especially for processing FITS image files and field-of-view data all the way to AAVSO reports for submission.

## My workflow
This is in development 2015-early 2016. As of now, I process a new AN (Astronight) folder (e.g., /20151218) ... *in this order*:

**Input.R (pre-calibration):**

 1. **renameObject()** --- Renames FITS files and FITS header "OBJECT" value from old to new Object name, across all FITS files (and subdirectories) within AN top folder. For example, renames all "Landolt_001" to "Std_001". For occasional use when object name in ACP plan turned out not to be the best one; this  should be run before renameACP() if possible.
 1. **renameACP()**  ---  Renames all _target_ fits files (not calibration files) from ACP-format names (like TargetName-S001-R001-C003-V-dupe1.fts) to my own filename format (like TargetName-0003-V.fts). The sequence number is based on time (JD) from the FITS header, is validated and sorted by time across all files of the same TargetName. Renaming is not fooled by dupe or duplicate naming across subdirectories. TargetNames and Filter IDs are verified for equality between the original file name and the FITS header. All target FITS files are then collected in the top AN folder. A table of old vs new file names is written to a text file, and the data frame is stored as a .RData file for immediate reload into R.
 1. **prepareForCal()**  ---  Sets up folders /Calibration (all flat, dark, bias images for the AN), /CalibrationMasters (calibration images duplicated here & ultimate home of MaxIm generated calibration master frames), /Ur (backup of all renamed target FITS files; may move this forward to renameACP() (or similar fn) so that the Ur files are really Ur), and /Photometry (catchall for metadata about this AN folder).

**Calibration of all target images in MaxIm DL (not R):**

 1. Ensure all needed raw flat, dark, and bias frames are collected in /CalibrationMasters.
 1. In MaxIm, "Set Calibration" to this /CalibrationMasters folder, and "Replace w/Masters".
 1. Load all FITS from /Uncalibrated folder, "Calibrate All", "Close All/Save=Yes to All".

**Input.R (post-calibration):**

 1. **finishFITS()**  ---  Deletes all non-master files from /CalibrationMasters, verifies via FITS headers that all calibrations happened OK, moves target FITS files from /Uncalibrated to /Calibrated, cleans up directory structure.
 1. **run_APT_all()**  ---  Prepares inputs for and invokes APT software to build R data frame suitable for later use in photometric model building and AAVSO. APT is a bit limited in its aperture math, and I may later write my own aperture math in R, but for now APT is very reliable in its star marking in images. This function draws heavily on previously prepared FOV (field-of-view), one text file per field of view, which roughly corresponds to a VPhot "sequence" (badly named by AAVSO) of all the relevant target, check, and standard comp stars; my FOV file includes some additional metadata that might as well be bundled with the VPhot data, right in the same files.

**Model.R**

 1. **modelAll()**  ---  Runs a mixed-model regression for each filter. Inputs are all comp stars with minimum signal-to-noise ratio and that are not saturated *in the original FITS image*. This function returns a master model list for the entire Astronight, which list includes all data that later will be needed to predict check-star and target-star magnitudes, plus all the other data required for an AAVSO report. 
 1. ***--> some plot and diagnostic functions*** are needed here, especially to curate outlier data points.

**Predict.R**

 1. **predictAll()**  ---  [need to write this. will require color-index spline, interpolation, and correction. also some extinction cleverness.]
 1. **write_AAVSO()**  ---  [in development. will need to draw on a LOT of metadata, but this should be available from outputs of the above, previously executed functions].

So this is obviously a work in progress...
