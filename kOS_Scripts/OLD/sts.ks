// KOS Script for Stock Space Shuttle Launch
// Version 1.0 - Adapted from Saturn V script for stock KSP Space Shuttle.
// Assumes:
// - SSME tagged "SSME" or activated manually before run.
// - SRBs ignited by staging at T-0 (stage releases clamps and ignites SRBs).
// - OMS engines tagged "OMS".
// - Stage for SRB sep after burnout.
// - Stage for ET sep at MECO.
// - RCS available for ullage.
// - Have circ.ks for final circularization.

CLEARSCREEN.
GLOBAL MODE IS 0.
SET Recycle TO FALSE.

// Utility
FUNCTION Clamp {
    PARAMETER x, lo, hi.
    IF x < lo { RETURN lo. }
    IF x > hi { RETURN hi. }
    RETURN x.
}

PreDefinedShuttle(). 
PreLaunchShuttle().

SET voice to getVoice(0).
SET voiceTickNote to NOTE(480, 0.1).
SET voiceTakeOffNote to NOTE(720, 1).

// Variables for ignition sequence
LOCAL ignitionStarted IS FALSE.
LOCAL ignitionStartTime IS 0.
LOCAL srbIgnited IS FALSE.
SET rampSec TO 3.0.  // Ramp throttle over 3 seconds for SSME

GLOBAL meco_apo IS 65000.
// Handoff to circ.ks once we have a stable high apoapsis on Kerbin
GLOBAL turn_start_alt IS 700.
GLOBAL turn_end_alt IS 20000.
//GLOBAL min_pitch IS 30.

GLOBAL ap_hold_band IS 500.      // meters: deadband around target_Ap
GLOBAL ap_hold_kp IS 0.0006.     // throttle change per meter of Ap error (tune 0.0003..0.0012)
GLOBAL pe_goal IS 0.        // stop ET burn phase when Pe >= -10km (tune)
GLOBAL pe_pitch_cmd IS 5.        // degrees during Pe-build (flatten)
GLOBAL pe_pitch_min IS -10.       // allow small below-horizon late if stable
GLOBAL pe_pitch_max IS 20.
GLOBAL pe_mode_ap_frac IS 0.60.  // enter Ap-hold phase at 60% of target_Ap

// Throttle g-limit (keep <= this many gees)
GLOBAL g_limit IS 3.0.
GLOBAL maxq_press IS 25.
GLOBAL maxq_throt IS 0.65.
GLOBAL srb_thrust_drop IS 0.65.
LOCAL dynQPeak IS 0.
LOCAL maxq_recover_frac IS 0.90. // recover when Q drops below 90% of peak (tune 0.85..0.95)


SetupAbortDetection().

// Kerbin-scale pitch program: hold 90 until turn_start_alt, then ramp to min_pitch by turn_end_alt.
FUNCTION TargetPitch {

  LOCAL a IS SHIP:ALTITUDE.

  // Phase 0: before turn starts, hold the initial pitch you set in config
  IF a <= turn_start_alt { RETURN myPitchAngle. }

  // Phase 1: from turn_start_alt -> 10km, ramp myPitchAngle down to 30 deg
  IF a < 15000 {
    LOCAL t1 IS (a - turn_start_alt) / (15000 - turn_start_alt).
    SET t1 TO Clamp(t1, 0, 1).
    RETURN myPitchAngle + (30 - myPitchAngle) * t1.
  }

  // Phase 2: from 10km -> 30km, ramp 30 -> 10 deg (your request)
  IF a < 36000 {
    LOCAL t2 IS (a - 15000) / (36000 - 15000).
    SET t2 TO Clamp(t2, 0, 1).
    RETURN 36 + (15 - 36) * t2.
  }

  // Phase 3: above 30km, hold 10 deg (you can later hand off to peMode / Ap-hold)
  RETURN -15.
}

// Set up smooth throttle ramp trigger (runs in background)
WHEN TRUE THEN {
    IF ignitionStarted {
        LOCAL elapsed IS TIME:SECONDS - ignitionStartTime.
        LOCAL u IS elapsed / rampSec.
        IF u > 1 { SET u TO 1. }
        LOCAL targetThr IS u * u.  // Quadratic ease-in
        LOCK THROTTLE TO targetThr.
        IF u < 1 {
            PRESERVE.
        }
    } ELSE {
        PRESERVE.
    }
}

// Countdown Clock
PRINT "========================================" AT (0, 1).
PRINT "SPACE SHUTTLE LAUNCH SEQUENCE" AT (0, 0).
FROM {local countdown is myCountdownTime.} UNTIL countdown < 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown + "     " AT (0, 2).
    HUDTEXT("T- " + countdown, 1.5, 2, 18, white, FALSE).
    
    // T-8: Tail Service Mast + Fuel Cells
    IF countdown = 8 {
        PRINT "Tail Service Mast (Stage 6)      " AT (0, 14).
        Staging(0).
    }

    // T-6: Start SSME (Stage 5) + begin throttle ramp
    IF countdown = 6 AND NOT ignitionStarted {
        PRINT "SSME Start (Stage 5)             " AT (0, 16).
        LOCK THROTTLE TO 0.
        Staging(0).
        SET ignitionStarted TO TRUE.
        SET ignitionStartTime TO TIME:SECONDS.
        // Lock steering ONCE here using the proven liftoff law.
        LOCK STEERING TO UP + R(0,0,myRoll).
    }
    
    IF countdown = 0 AND NOT srbIgnited {
        PRINT "SRB Ignition / Clamp Release     " AT (0, 17).
        Staging(0).
        SET srbIgnited TO TRUE.
        voice:PLAY(voiceTakeOffNote).
        
        IF SHIP:AVAILABLETHRUST <= SHIP:MASS * 9.81 {
            PRINT "IGNITION FAILURE - HOLDING      " AT (0, 18).
            LOCK THROTTLE TO 0.
        }
    }
    
    // Display current throttle
    IF ignitionStarted {
        PRINT "Throttle: " + ROUND(THROTTLE * 100, 1) + "%     " AT (0, 8).
    }
    
    // Countdown tick sounds
    IF countdown <= 5 AND countdown > 0 { voice:PLAY(voiceTickNote). }

    // Check for abort or hold
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL key IS TERMINAL:INPUT:GETCHAR().
        IF key = "A" OR key = "a" {
            HUDTEXT ("ABORT! ABORT ABORT!", 5, 2, 15, red, TRUE).
            PRINT ">>> LAUNCH ABORTED <<<           " AT (0, 15).
            LOCK THROTTLE TO 0.
            WAIT 0.1.
            KLAXON_START(1, "sawtooth", 0.2).
            WAIT 5.
            KLAXON_STOP().
            WAIT 10.
            REBOOT.
        }
        IF key = "H" OR key = "h" {
            HUDTEXT ("HOLD..HOLD..HOLD!", 5, 2, 15, yellow, TRUE).
            PRINT ">>> LAUNCH HOLD <<<              " AT (0, 15).
            LOCK THROTTLE TO 0.
            SET ignitionStarted TO FALSE.
            SET srbIgnited TO FALSE.
            SET countdown TO myCountdownTime + 1.
            LaunchHold().
        }
    }
    
    WAIT 1.
}

// Mode 1 - Liftoff!
SET MODE TO 1.
LOCAL ascentGuidanceActive IS FALSE.
PRINT "Mode 1 - Liftoff                 " AT (0, 0).
voice:PLAY(voiceTakeOffNote).

// Ensure throttle is at 100%
LOCK THROTTLE TO 1.0.

PRINT "Roll/Pitch Program Initiated     " AT (0, 20). 
PRINT "Pitch Program: " + myPitchAngle + "°     " AT (0, 21).
WAIT UNTIL SHIP:ALTITUDE > 200.
LOCK STEERING TO HEADING(myAzimuth, 90, myRoll).
WAIT 0.1.

WAIT UNTIL SHIP:ALTITUDE > turn_start_alt.
LOCK STEERING TO HEADING(myAzimuth, myPitchAngle, myRoll).
SET ascentGuidanceActive TO TRUE.
WAIT 0.1.

WAIT UNTIL SHIP:ALTITUDE > 3000.
// Mode 2 - Ascent including Max Q and SRB Sep
SET MODE TO 2.
LOCAL maxQReached IS FALSE.
LOCAL maxQPassed IS FALSE.
LOCAL srbSepDone IS FALSE.
LOCAL srbThrustPeak IS 0.

PRINT "Mode 2 - Ascent/Gravity Turn    " AT (0, 0).

// Target throttle
LOCAL smoothedThrottle IS 1.0.
LOCAL throttleSlewPerSec IS 0.35. // 0.35 = takes ~3 sec to go 1.0 -> 0.0 (tune 0.2..0.6)
LOCAL lastT IS TIME:SECONDS.

LOCAL targetThrottle IS 1.0.

LOCAL peMode IS FALSE.
LOCAL apHoldThrottle IS 1.0.
LOCAL Rolled IS FALSE.

// Main ascent loop
UNTIL SHIP:APOAPSIS >= target_Ap {

    IF (NOT peMode) AND (SHIP:ORBIT:APOAPSIS >= target_Ap * pe_mode_ap_frac) AND (SHIP:ALTITUDE >= turn_end_alt) {
    SET peMode TO TRUE.
    PRINT "Ap-hold / Pe-build ACTIVE" AT (0, 14).
    }

    // Handoff: once apoapsis is at/above handoffAp, give guidance to circ.ks.
    // Do NOT cut throttle here; circ.ks will manage insertion.
    IF SHIP:ORBIT:APOAPSIS >= target_Ap {
        PRINT "Handoff to circ.ks (Ap >= " + ROUND(target_Ap/1000,1) + " km)" AT (0, 16).
        HUDTEXT("HANDOFF TO CIRC", 4, 2, 18, green, FALSE).
        BREAK.
    }

    // Dynamic pressure (kPa)
    LOCAL dynPressKpa IS SHIP:DYNAMICPRESSURE * 101.325.

    // Enter Max Q
    IF (NOT maxQReached) AND (dynPressKpa >= maxq_press) {
    SET maxQReached TO TRUE.
    SET targetThrottle TO maxq_throt.
    SET dynQPeak TO dynPressKpa.
    }

    // Track peak once in Max-Q
    IF maxQReached AND (NOT maxQPassed) {
    IF dynPressKpa > dynQPeak { SET dynQPeak TO dynPressKpa. }

    // Exit Max-Q when we've come off the peak
    IF dynPressKpa <= (dynQPeak * maxq_recover_frac) {
        SET maxQPassed TO TRUE.
        SET targetThrottle TO 1.0.
    }
    }
    
    // // Dynamic pressure
    // LOCAL dynPressKpa IS SHIP:DYNAMICPRESSURE * 101.325.
    // LOCAL dynQPeak IS 0.
    // LOCAL maxq_recover_frac IS 0.90. // recover when Q drops below 90% of peak (tune 0.85..0.95)

    // // Max Q handling
    // IF NOT maxQReached AND dynPressKpa >= maxq_press {
    //     PRINT "MAX Q                            " AT (0, 2).
    //     HUDTEXT ("MAX Q", 5, 2, 20, yellow, FALSE).
    //     SET maxQReached TO TRUE.
    //     SET targetThrottle TO maxq_throt.
    // }
    // IF maxQReached AND NOT maxQPassed AND dynPressKpa < (maxq_press * 0.8) {
    //     SET targetThrottle TO 1.0.
    //     SET maxQPassed TO TRUE.
    // }
    // G-limit throttle (approx): Some kOS versions do not provide SHIP:GEES.
    // Approximate "G-load" using thrust acceleration (similar to KSP's g-meter proper acceleration):
    //   g_est ~= (current_thrust / mass) / g0
    // This ignores lift/drag contributions but works well for a throttle limiter.
    LOCAL g0 IS 9.80665.
    LOCAL g_est IS 0.
    IF SHIP:MASS > 0 {
        SET g_est TO (SHIP:AVAILABLETHRUST / SHIP:MASS) / g0.
    }

    LOCAL throttleCmd IS targetThrottle.

    IF g_est > g_limit AND g_est > 0 {
        SET throttleCmd TO throttleCmd * (g_limit / g_est).
    }

    SET throttleCmd TO Clamp(throttleCmd, 0, 1).

    IF peMode {

        LOCAL apErr IS SHIP:ORBIT:APOAPSIS - target_Ap.
        SET apErr TO Clamp(apErr, -5000, 5000).

        IF ABS(apErr) <= ap_hold_band {
            SET apHoldThrottle TO apHoldThrottle + (throttleCmd - apHoldThrottle) * 0.1.
        } ELSE {
            SET apHoldThrottle TO apHoldThrottle - (apErr * ap_hold_kp).
        }

        SET apHoldThrottle TO Clamp(apHoldThrottle, 0.10, 1.0).

        IF apHoldThrottle < throttleCmd {
            SET throttleCmd TO apHoldThrottle.
        }
    }

    // Slew / smooth
    LOCAL nowT IS TIME:SECONDS.
    LOCAL dt IS nowT - lastT.
    SET lastT TO nowT.
    IF dt < 0 { SET dt TO 0.1. }
    IF dt > 0.5 { SET dt TO 0.5. }

    LOCAL maxStep IS throttleSlewPerSec * dt.
    LOCAL diff IS throttleCmd - smoothedThrottle.
    IF diff >  maxStep { SET diff TO  maxStep. }
    IF diff < -maxStep { SET diff TO -maxStep. }

    SET smoothedThrottle TO Clamp(smoothedThrottle + diff, 0, 1).
    LOCK THROTTLE TO smoothedThrottle.
    
    // Update display
    LOCAL TWR IS SHIP:AVAILABLETHRUST / (SHIP:MASS * 9.81).
    PRINT "Altitude:  " + ROUND(SHIP:ALTITUDE/1000, 2) + " km     " AT (0, 4).
    PRINT "Apoapsis:  " + ROUND(SHIP:APOAPSIS/1000, 1) + " km     " AT (0, 5).
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km     " AT (0, 6).
    PRINT "Velocity:  " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s     " AT (0, 7).
    PRINT "Dyn Press: " + ROUND(dynPressKpa, 1) + " kPa     " AT (0, 8).
    
    // Kerbin-scale gravity turn
    IF ascentGuidanceActive {

        // Base pitch from your schedule
        LOCAL pitchCmd IS TargetPitch().
        
        IF flRoll AND NOT Rolled AND SHIP:ALTITUDE > 40000 {
            SET myRoll TO 0.  //Heads-up
            SET Rolled TO TRUE.  //Will block any further attempt to change.
            PRINT "Shuttle rolling to heads-up attitude." AT (0, 20).
        }

        IF peMode {
            // Flatten to build horizontal speed (raises Pe)
            SET pitchCmd TO pe_pitch_cmd.

            // Optional: gradually allow flatter as you get higher
            IF SHIP:ALTITUDE > 40000 { SET pitchCmd TO pitchCmd - 10. }
            IF SHIP:ALTITUDE > 55000 { SET pitchCmd TO pitchCmd - 2. }
        

            // If head-sup roll is enabled, keep pitch >= 0 to avoid diving.
            IF flRoll AND Rolled { SET pe_pitch_min TO 0. }

            SET pitchCmd TO Clamp(pitchCmd, pe_pitch_min, pe_pitch_max).

        } ELSE {
            SET pitchCmd TO Clamp(pitchCmd, 0, 90).
        }

        LOCK STEERING TO HEADING(myAzimuth, pitchCmd, myRoll).

        PRINT "PitchCmd:    " + ROUND(pitchCmd,1) + "   "
            // + " Ap:" + ROUND(SHIP:ORBIT:APOAPSIS/1000,1) + "km"
            // + " Pe:" + ROUND(SHIP:ORBIT:PERIAPSIS/1000,1) + "km   " 
            AT (0, 9).
    }

    PRINT "G-Force:   " + ROUND(TWR, 2) + " g      " AT (0, 10).
        
    IF NOT srbSepDone {
        LOCAL currThrust IS SHIP:AVAILABLETHRUST.
        SET srbThrustPeak TO MAX(srbThrustPeak, currThrust).
        IF currThrust < srbThrustPeak * srb_thrust_drop {
            PRINT "SRB Separation                  " AT (0, 15).
            Staging(0.5).
            SET srbSepDone TO TRUE.
        }
    }
    
    // Clear MAX Q
    IF SHIP:ALTITUDE >= 15000 {
        PRINT "                                " AT (0, 2).
    }
    
    IF peMode AND SHIP:ORBIT:PERIAPSIS >= pe_goal {
        PRINT "Pe goal reached, handoff ready" AT (0, 17).
        WAIT UNTIL SHIP:APOAPSIS >= 75000. 
        BREAK.
    }

    WAIT 0.1.

}

// Mode 3 - MECO and External tank seperation
SET MODE TO 3. 
PRINT "Mode 3 - MECO and ET Seperation      " AT (0, 0).
// MECO
PRINT "MECO - SSME Shutdown             " AT (0, 18).
LOCK THROTTLE TO 0.
AG3 ON.  //LOCK GIMBAL and SHUTOFF SSME.
PRINT "Waiting for ET seperation alitude of:" AT (0,22).
PRINT meco_apo + " meters." AT (0, 23).
WAIT UNTIL SHIP:ALTITUDE > meco_apo.
RCS ON.
LOCK STEERING TO PROGRADE.
WAIT 10.
PRINT "External Tank Separation         " AT (0, 25).
Staging(1).
WAIT 0.1.
SET SHIP:CONTROL:TOP TO 1.
WAIT 5.
SET SHIP:CONTROL:TOP TO 0.
LOCK THROTTLE TO 0.

// Mode 4 - Orbit Circularization
SET MODE TO 4.
PRINT "Mode 4 - Orbit Circularization   " AT (0, 0).
UNLOCK THROTTLE.
UNLOCK STEERING.
AG4 ON. //Activate OMS and activates all additional resources.
RUNPATH ("circ.ks", target_Ap, target_Pe, orbitMode).
AG4 OFF. // Deactivate OMS.
// If circ returns, stop this script.
WAIT 10.
RCS ON.
LOCK STEERING TO PROGRADE.
Stable().
SET MODE TO 5.
CLEARSCREEN.
PRINT "========================================" AT (0, 2).
PRINT "Mode 5 - Orbit Established       " AT (0, 0).
PRINT "Final Orbit:                     " AT (0, 5).
PRINT "Apoapsis:  " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km     " AT (0, 6).
PRINT "Periapsis: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km     " AT (0, 7).
RCS OFF.
UNLOCK STEERING.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
SAS ON.
AG5 ON.
WAIT 10.
PRINT "Opening Cargo bay doors." AT (0,10).
WAIT 5.
PRINT "Deploying Antenna."  AT (0, 11).
PRINT ">>>>> END OF LAUNCH PROGRAM <<<<<" AT (0,15).
PRINT ">>>>>> PROGRAM END <<<<<<<" AT (0,17).

// Functions (same as Saturn, adapted)
FUNCTION SetupAbortDetection {
    PRINT "Abort: Backspace (click outside terminal)" AT (0, 25).
    WHEN TRUE THEN {
        IF SHIP:ALTITUDE < 30000 {
            IF ABORT {
                PRINT ">>> ABORT SEQUENCE <<<          " AT (0, 24).
                HUDTEXT("ABORT! ABORT!", 10, 2, 30, red, TRUE).
                LOCK THROTTLE TO 0.
                UNLOCK STEERING.
                SAS ON.
                ABORT OFF.
                KLAXON_START(1, "square", 0.3).
                WAIT 3.
                KLAXON_STOP().
                PRINT "Manual Control Returned         " AT (0, 23).
                RETURN FALSE.
            }
            PRESERVE.
        } ELSE {
            RETURN FALSE.
        }
    }
}

FUNCTION LaunchHold {
    CLEARSCREEN.
    PRINT ">>> LAUNCH HOLD <<<              " AT (0, 0).
    PRINT "Press any key to resume...       " AT (0, 5).
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    WAIT 1.
    UNSET dummy.
}

FUNCTION Staging {
    PARAMETER holdTime.
    WAIT holdTime.
    STAGE.
}

FUNCTION KLAXON_START {
    PARAMETER voiceIdx IS 1, wave IS "sawtooth", vol IS 1.0.
    SET V0 TO GETVOICE(voiceIdx).
    SET V0:WAVE TO wave.
    SET V0:VOLUME TO vol.
    SET V0:TEMPO TO 1.0.
    LOCAL whoop IS LIST(SLIDENOTE(400,600,0.35), SLIDENOTE(600,400,0.35)).
    SET V0:LOOP TO TRUE.
    V0:PLAY(whoop).
}

FUNCTION KLAXON_STOP {
    PARAMETER voiceIdx IS 1.
    GETVOICE(voiceIdx):STOP().
}

// Prelaunch Shuttle
FUNCTION PreLaunchShuttle {
    PRINT "Mode 0 - Prelaunch".
    PRINT "".
    PRINT "Default parameters. Change or proceed.".
    UNTIL FALSE {
        DisplayParameters().
        LOCAL choice IS TERMINAL:INPUT:GETCHAR().
        IF choice = "R" OR choice = "r" {
            PreDefinedShuttle().
            PRINT "Reset to defaults.".
            WAIT 1.
        } ELSE IF choice = "1" { SET myCountdownTime TO GetNumericInput(). }
        ELSE IF choice = "2" { SET myPitchAngle TO GetNumericInput(). }
        ELSE IF choice = "3" { SET myAzimuth TO GetNumericInput(). }
        ELSE IF choice = "4" { SET myRoll TO GetNumericInput(). }
        ELSE IF choice = "5" { SET target_Ap TO GetNumericInput(). }
        ELSE IF choice = "6" { SET target_Pe TO GetNumericInput(). }
        ELSE IF choice = "7" { SET myLiftOff TO GetNumericInput(). }
        ELSE IF choice = "8" { SET orbitMode TO GetNumericInput(). }
        ELSE IF choice = "9" { 
            IF flRoll = "FALSE" {
                SET flRoll TO "TRUE".
            } ELSE {
                SET flRoll TO "FALSE".
            }
        }ELSE {
            PRINT "Proceeding...".
            WAIT 5.
            BREAK.
        }
        WAIT 0.5.
    }
    PRINT "Final parameters:".
    WAIT 3.
    DisplayParameters().
    WAIT 10.
    CLEARSCREEN.
    PRINT "=========================================".
    PRINT "         Starting STS Systems.".
    PRINT "=========================================".
    PRINT " ".
    SAS OFF.
    RCS OFF.
    FUELCELLS ON.
    PRINT "Fuel Cells started and running".
    PRINT "Starting pad fuel pumps.".
    AG10 ON.
    WAIT 5.
    PRINT "Fueling started.".
    UNTIL ResourcesFull(0.999) {
        LOCAL lfAmt IS 0.
        LOCAL lfCap IS 0.
        LOCAL oxAmt IS 0.
        LOCAL oxCap IS 0.
        LOCAL monoAmt IS 0.
        LOCAL monoCap IS 0.

        FOR r IN SHIP:RESOURCES {
            IF r:NAME = "LiquidFuel" {
            SET lfAmt TO r:AMOUNT.
            SET lfCap TO r:CAPACITY.
            }
            IF r:NAME = "Oxidizer" {
            SET oxAmt TO r:AMOUNT.
            SET oxCap TO r:CAPACITY.
            }
            IF r:NAME = "MonoPropellant" {
            SET monoAmt TO r:AMOUNT.
            SET monoCap TO r:CAPACITY.
            }
        }

        LOCAL lfPct IS 100.
        LOCAL oxPct IS 100.
        LOCAL moPct IS 100.

        IF lfCap > 0 { SET lfPct TO 100 * lfAmt / lfCap. }
        IF oxCap > 0 { SET oxPct TO 100 * oxAmt / oxCap. }
        IF monoCap > 0 { SET moPct TO 100 * monoAmt / monoCap. }

        PRINT "LF: " + ROUND(lfPct,1) + "%  OX: " + ROUND(oxPct,1) + "%  MONO: " + ROUND(moPct,1) + "%      " AT (0, 11).

        WAIT 0.5.
    }

    PRINT "Fueling complete".
    PRINT "Guidance online.".
    PRINT "Press any key to arm launch...".
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    prepareLaunchShuttle().
}

// Defaults
FUNCTION PreDefinedShuttle {
    GLOBAL myCountdownTime TO 10.
    GLOBAL myPitchAngle TO 65.
    GLOBAL myAzimuth TO 90.
    GLOBAL myRoll TO 180.
    GLOBAL target_Ap TO 90000.
    GLOBAL target_Pe TO 80000.
    GLOBAL myLiftOff TO 3.
    GLOBAL orbitMode TO 0.
    GLOBAL flRoll TO FALSE.
}

// Display
FUNCTION DisplayParameters {
    CLEARSCREEN.
    PRINT "STS Parameters (R=reset, #=edit, other=proceed)".
    PRINT "1. Countdown: " + myCountdownTime.
    PRINT "2. Init Pitch: " + myPitchAngle + "°".
    PRINT "3. Azimuth: " + myAzimuth + "°".
    PRINT "4. Liftoff Roll: " + myRoll.
    PRINT "5. Target Ap: " + target_Ap + "m".
    PRINT "6. Target Pe: " + target_Pe + "m".
    PRINT "7. Liftoff Stages: " + myLiftOff.
    PRINT "8. Orbit Mode: " + orbitMode.
    PRINT "9. Flight Roll:" + flRoll.
}

// Numeric Input
FUNCTION GetNumericInput {
    LOCAL inputString IS "".
    PRINT "Enter new value (press Enter when done): ".
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL mychar IS TERMINAL:INPUT:GETCHAR().
            IF mychar = TERMINAL:INPUT:RETURN {
                BREAK.
            } ELSE IF (mychar >= "0" AND mychar <= "9") OR mychar = "." {
                SET inputString TO inputString + mychar.
                PRINT "          " AT (TERMINAL:WIDTH - 20, TERMINAL:HEIGHT - 1).
                PRINT inputString AT (TERMINAL:WIDTH - 20, TERMINAL:HEIGHT - 1).
            }
        }
        WAIT 0.01.
    }
    IF inputString = "" {
        PRINT "No input provided, returning 0.".
        RETURN 0.
    }
    LOCAL numericValue IS inputString:TONUMBER(0).
    IF numericValue = 0 AND inputString <> "0" {
        PRINT "Invalid number entered, using 0.".
    }
    RETURN numericValue.
}

// Prep
FUNCTION prepareLaunchShuttle {
    CLEARSCREEN.
    PRINT "=========================================".
    PRINT "       Final STS Systems Checks.".
    PRINT "=========================================".
    PRINT " ".
    AG9 ON.  //Stop fueling, retract LOX, Crew arms
    PRINT "Fueling Complete.".
    WAIT 1.
    PRINT "Shuttle Control surfaces testing".
    WAIT 3.
    PRINT "Intertank access arm retracting.".
    WAIT 26.
    PRINT "Crew access arm retracting".
    WAIT 30.
    PRINT "LOX vent arm retracting".
    WAIT 30.
    PRINT "Shuttle Ready for Liftoff!".
    WAIT 5.
    PRINT "Press any key to proceed.".
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    WAIT 1.
    CLEARSCREEN.
}

// StripPadding (simplified)
FUNCTION StripPadding {
    PARAMETER num.
    RETURN "" + num.
}

// Returns TRUE when the vessel's LF/OX/Mono are "full enough"
FUNCTION ResourcesFull {
  PARAMETER tol IS 0.999. // 99.9%

  LOCAL lfAmt IS 0.
  LOCAL lfCap IS 0.
  LOCAL oxAmt IS 0.
  LOCAL oxCap IS 0.
  LOCAL monoAmt IS 0.
  LOCAL monoCap IS 0.

  FOR r IN SHIP:RESOURCES {
    IF r:NAME = "LiquidFuel" {
      SET lfAmt TO r:AMOUNT.
      SET lfCap TO r:CAPACITY.
    }
    IF r:NAME = "Oxidizer" {
      SET oxAmt TO r:AMOUNT.
      SET oxCap TO r:CAPACITY.
    }
    IF r:NAME = "MonoPropellant" {
      SET monoAmt TO r:AMOUNT.
      SET monoCap TO r:CAPACITY.
    }
  }

  // Treat "missing resource" as already satisfied (capacity 0)
  LOCAL lfOK IS (lfCap <= 0) OR (lfAmt / lfCap >= tol).
  LOCAL oxOK IS (oxCap <= 0) OR (oxAmt / oxCap >= tol).
  LOCAL monoOK IS (monoCap <= 0) OR (monoAmt / monoCap >= tol).

  RETURN lfOK AND oxOK AND monoOK.
}

FUNCTION Stable {
    // Wait until we're aligned to prograde within N degrees
    LOCAL tolDeg IS 2.0.   // tighten to 1.0 if you want
    LOCAL stableCount IS 0.
    LOCAL needStable IS 10. // consecutive checks (10 * 0.1s = 1s stable)

    UNTIL stableCount >= needStable {

    // Forward direction of the ship (a unit vector)
    LOCAL fwd IS SHIP:FACING:VECTOR:NORMALIZED.

    // Prograde direction (orbital prograde is a direction)
    LOCAL pro IS SHIP:PROGRADE:VECTOR:NORMALIZED.

    // Angle between vectors (degrees)
    LOCAL ang IS VANG(fwd, pro).

    IF ang <= tolDeg {
        SET stableCount TO stableCount + 1.
    } ELSE {
        SET stableCount TO 0.
    }

    PRINT "Aligning to PROGRADE... err=" + ROUND(ang,2) + " deg   " AT (0, 20).
    WAIT 0.1.
    }
}