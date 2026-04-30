// ===========================================================================
// FLIGHT LOG RECORDER v2.0
// Run this AFTER landing to record calibration data
// Automatically reads the prediction that was saved
// ===========================================================================

CLEARSCREEN.
PRINT "=== MUN RETURN FLIGHT LOG ===".
PRINT " ".

IF STATUS <> "LANDED" AND STATUS <> "SPLASHED" {
  PRINT "Run this after landing only!".
  WAIT UNTIL FALSE.
}

// Read saved flight data
LOCAL flightDataFile IS "0:/flight_data.txt".
IF NOT EXISTS(flightDataFile) {
  PRINT "No prediction data found!".
  PRINT "Run tkimun.ks from Kerbin SOI before landing.".
  WAIT UNTIL FALSE.
}

SWITCH TO 0.
SET file TO OPEN(flightDataFile).
SET content TO file:READALL:STRING.
SET lines TO content:SPLIT(CHAR(10)).

SET pe TO lines[0]:TONUMBER().
SET predicted TO lines[1]:TONUMBER().

PRINT "Flight data loaded:".
PRINT "Pe targeted: " + ROUND(pe/1000,1) + " km".
PRINT "Predicted landing: " + ROUND(predicted,2) + "°".
PRINT " ".

// Get actual landing position
LOCAL actual IS SHIP:LONGITUDE.
IF actual > 180 SET actual TO actual - 360.

PRINT "Actual landing: " + ROUND(SHIP:LATITUDE,6) + "°, " + ROUND(actual,6) + "°".
PRINT " ".

// Calculate error
LOCAL error IS actual - predicted.
IF error > 180 SET error TO error - 360.
ELSE IF error < -180 SET error TO error + 360.

PRINT "=== RESULTS ===".
PRINT "Target Pe: " + ROUND(pe/1000,1) + " km".
PRINT "Predicted landing: " + ROUND(predicted,2) + "°".
PRINT "Actual landing: " + ROUND(actual,2) + "°".
PRINT "Error: " + ROUND(error,2) + "°".
IF error > 0 PRINT "  (landed EAST of prediction)".
ELSE IF error < 0 PRINT "  (landed WEST of prediction)".
ELSE PRINT "  (PERFECT!)".

// Append to log file
LOCAL logFileName IS "0:/flight_log.txt".

LOG "========================================" TO logFileName.
LOG "Flight at T+" + ROUND(TIME:SECONDS) + "s" TO logFileName.
LOG "Pe: " + ROUND(pe/1000,1) + " km" TO logFileName.
LOG "Predicted: " + ROUND(predicted,2) + "°" TO logFileName.
LOG "Actual: " + ROUND(actual,2) + "°, " + ROUND(SHIP:LATITUDE,2) + "°" TO logFileName.
LOG "Error: " + ROUND(error,2) + "°" TO logFileName.
LOG "" TO logFileName.

PRINT " ".
PRINT "=== UPDATE YOUR SCRIPT ===".
PRINT "In tkimun.ks, in calibrationData, change:".
PRINT "  " + ROUND(pe) + ", -999".
PRINT "to:".
PRINT "  " + ROUND(pe) + ", " + ROUND(error,2).
PRINT " ".
PRINT "Data also saved to flight_log.txt".
PRINT " ".

WAIT UNTIL FALSE.
