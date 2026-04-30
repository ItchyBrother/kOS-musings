// KOS Script for Rocket Launch and SubOrbitial flight (Project Kercury)

// Mode 0 - Prelaunch
CLEARSCREEN.
GLOBAL MODE IS 0.
SET holdTime TO 0.
PRINT "Mode 0 - Prelaunch".
SAS OFF.
PRINT "SAS OFF.".
LOCK STEERING TO HEADING (90,90).
PRINT "SETTING STEERING TO 90, 90.".
WAIT 1.

// Countdown
FROM {local countdown is 3.} UNTIL countdown = 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown + " " AT (0,3).
    WAIT 1.
}

// Mode 1 - Launch
SET MODE TO 1.
PRINT "Mode 1 - Launch".
LOCK THROTTLE TO 1.0.
STAGE.

// Initial vertical ascent for launch complex avoidance
LOCK STEERING TO HEADING (90,90).

UNTIL SHIP:ALTITUDE > 100 {
    WAIT 0.1.
}

// Pitch briefly to avoid launch complex
LOCK STEERING TO HEADING(90, 87). // 3 degrees east from vertical
PRINT "Launch Pad Avoidance Maneuver.".
WAIT 2. // Brief pitch maneuver
LOCK STEERING TO HEADING (90,90).

// Mode 2 - Ascent including Max Q
SET MODE TO 2.
PRINT "Mode 2 - Ascent".

// Start gravity turn when velocity reaches 50 m/s
WHEN SHIP:VELOCITY:SURFACE:MAG > 50 THEN {
    PRINT "Initiating gravity turn".
    gravityTurn(88).
}

// Mode 3 - MECO and Orbit Circularization
// MECO and wait for booster separation

// Testing for max Apoapsis.  Uncomment for Orbital flight.
//WHEN SHIP:APOAPSIS >= 83000 THEN {

// Burning all the fuel.  Comment out for Orbital flight.
WHEN STAGE:LIQUIDFUEL <=0.01 THEN {
    LOCK THROTTLE TO 0.
    SET MODE TO 3.
    PRINT "Mode 3 - MECO and Orbit Circularization".
    WAIT 0.1.
    PRINT "Main Engine Cut Off (MECO)".
}

// Switch to prograde at 36 km
WAIT UNTIL SHIP:ALTITUDE >= 36000.
LOCK STEERING TO PROGRADE.
PRINT "Switched to following Orbit Prograde.".

// Jettison escape tower at 50 km
WAIT UNTIL SHIP:ALTITUDE >= 50000.
AG1 ON. // Jettison escape tower
PRINT "Escape tower jettisoned".
//WAIT 5. // Small delay to ensure jettison is complete
//STAGE. // Booster stage separation
Staging(5).
PRINT "Booster stage separated".

// // Circulation function.  Parameter is the Pe desired.  Default is current Apoapsis. 
// // This is for orbital flights if type_of_flight equals 1. 
// // Most likely will change this out.
// if type_of_flight = 1{
//     // If the loop exits and the stage is ready, proceed with the burn
//     WAIT UNTIL STAGE:READY. 
//     PRINT "Circularization burn stage ready. TWR: " + ROUND(getCurrentTWR(), 2).

//     set target_pe to ship:apoapsis.
// //
//     run once circ (target_pe).
// //
// }
// Pitch to retrograde for deorbit preparation
WAIT 20.  //Waiting 30 seconds to give some seperation between capsule and booster.

//make sure SAS is off and RCS is on
SAS OFF.
RCS ON.
LOCK STEERING TO RETROGRADE.
WAIT 10.
PRINT"PROJECTED APOAPSIS IS: " + ROUND(SHIP:APOAPSIS,0).
// Going to do a series of manuvers here.  
// Need to check ETA to Apoapsis so we are in position to fire retropack at Apoapsis.
SET holdTime TO 2.

PRINT "Initiating flight maneuvers.".
// Align Anti-Normal
IF ETA:APOAPSIS > 10 AND ApoasisAhead() {
    PRINT "Executing Anti-Normal Maneuver.".
    aligntest(SHIP:PROGRADE + R(90,0,0), holdTime).
}
// Align Normal
IF ETA:APOAPSIS > 10 AND ApoasisAhead() {
    PRINT "Executing Normal Maneuver.".
    aligntest(SHIP:PROGRADE + R(-90,0,0), holdTime).
}
// Align Radial out
IF ETA:APOAPSIS > 10 AND ApoasisAhead() {
    PRINT "Executing Radial out Maneuver.".
    aligntest(SHIP:PROGRADE + R(0,90,0), holdTime).
}
// Align Radial in.
IF ETA:APOAPSIS > 10 AND ApoasisAhead() {
    PRINT "Executing Radial in Maneuver.".
    aligntest(SHIP:PROGRADE + R(0,-90,0), holdTime).
}
// Align Prograde
IF ETA:APOAPSIS > 10 AND ApoasisAhead() {
    PRINT "Executing Prograde Maneuver.".
    aligntest(PROGRADE, holdTime).
}
// Align Retrograde
aligntest(RETROGRADE, holdTime).

PRINT "Oriented retrograde for deorbit".
PRINT"ETA TO APOAPSIS IS: " + ROUND(ETA:APOAPSIS,0) + " seconds.".

SET holdTime TO 2.
// Checking to see if Apoasis is ahead, if so, we wait until it is 10 seconds away, 
// if not we start the Retro-burn immediately and prepare for landing sequence. 
IF ApoasisAhead() {
WAIT UNTIL ETA:APOAPSIS <=10. 
}
PRINT "Retro-burn intiated.".
PRINT "FIRE ONE!".
Staging(holdTime).
PRINT "FIRE TWO!".
Staging(holdTime).
PRINT "FIRE THREE!  Waiting to eject retro package.".
Staging(holdTime).
WAIT 8.
Staging(holdTime). //Eject retro package.
PRINT "Retro Packate ejected successfully!".
LOCK STEERING TO RETROGRADE.
WAIT 30.

// Print orbital parameters
PRINT "Orbital parameters:".
PRINT "Apoapsis: " + SHIP:APOAPSIS.
//PRINT "Periapsis: " + SHIP:PERIAPSIS.
//PRINT "Eccentricity: " + SHIP:ORBIT:ECCENTRICITY.
WAIT UNTIL SHIP:ALTITUDE <= 60000.
RCS OFF.
UNLOCK STEERING.
WAIT UNTIL SHIP:ALTITUDE <= 6000.
PRINT "DEPLOYING PARACHUTE!".
Staging(1).

// End of program
PRINT "Program completed".
shutdown.

// Function for gravity turn
FUNCTION gravityTurn {
    PARAMETER pitchAngle.
    PRINT "Setting to PitchAngle of: " + pitchAngle.
    LOCK STEERING TO HEADING(90, pitchAngle).

    WAIT UNTIL VANG(SHIP:FACING:VECTOR, HEADING(90, pitchAngle):VECTOR) <= 0.3.
    PRINT "Ship aligned to gravity turn vector".

    WAIT UNTIL VANG(SHIP:SRFPROGRADE:VECTOR, SHIP:FACING:VECTOR) <= 0.3.
    PRINT "Ship following surface prograde".
    LOCK STEERING TO SRFPROGRADE.
}

// Redefine getCurrentTWR after booster separation
FUNCTION getCurrentTWR {
    IF SHIP:MAXTHRUST = 0 {
        RETURN 0.
    } ELSE {
        RETURN SHIP:MAXTHRUST / (SHIP:MASS * (SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2)).
    }
}

// Checking Apoapsis
FUNCTION ApoasisAhead{
    RETURN SHIP:ORBIT:TRUEANOMALY < 180. 
}

// Spacecraft Alignment test
FUNCTION aligntest{

    parameter direction, holdTime.
    
    PRINT"ETA TO APOAPSIS IS: " + ROUND(ETA:APOAPSIS,0) + " seconds.".

    LOCK STEERING TO direction.
    
    //Verify that we are reasonabily aligned.  Hold this direction for specified time.
    WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, direction:FOREVECTOR) < 1.
    
    WAIT holdtime.
}

// Wait and Stage function
FUNCTION Staging{
    parameter holdTime.
    //Debug
    //PRINT "Hold Time is: " + holdTime.
    WAIT holdTime.
    STAGE.
}