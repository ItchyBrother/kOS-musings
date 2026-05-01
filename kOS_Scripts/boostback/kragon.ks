// ============================================================
//  kragon_ascent.ks  |  Kragon/Kalcon Two-Stage Ascent
//  Kerbal Scale (1:1 KSP / Kerbin)  |  Stock Aero
//  Adapted from sts.ks
// ============================================================
//
//  PROCESSOR SETUP (do this once from the kOS terminal on pad):
//    PROCESSOR("Kalcon"):BOOTFILENAME IS "kalcon_boot.ks".
//  Then make sure kalcon_boot.ks is on the Kalcon's local volume.
//
//  KALCON ACTION GROUPS (same as falcon9_rtls.ks requires):
//    AG1  Grid fins toggle
//    GEAR ON  Landing legs deploy
//    AG3  Shut down 2 outer center engines (leave center on)
//
//  USAGE:
//    run kragon.
//
//  ── MODE MAP ─────────────────────────────────────────────────
//    0  Prelaunch / Menu
//    1  Liftoff
//    2  Ascent / Gravity Turn  (Kalcon burning)
//    3  MECO / Kalcon Handoff / Separation
//    4  Kragon Second Stage Burn
//    5  Orbit Established
// ============================================================

@LAZYGLOBAL OFF.
CLEARSCREEN.
GLOBAL MODE IS 0.
PROCESSOR("Kalcon9"):DEACTIVATE().
PROCESSOR("Kragon 2 Stage"):DEACTIVATE().

// ── Utility ──────────────────────────────────────────────────
FUNCTION Clamp {
    PARAMETER x, lo, hi.
    IF x < lo { RETURN lo. }
    IF x > hi { RETURN hi. }
    RETURN x.
}

FUNCTION FitLine {
    PARAMETER msg.
    LOCAL s IS "" + msg.
    IF s:LENGTH > TERMINAL:WIDTH {
        SET s TO s:SUBSTRING(0, TERMINAL:WIDTH).
    }
    RETURN s:PADRIGHT(TERMINAL:WIDTH).
}

// ============================================================
//  CONFIGURABLE DEFAULTS
// ============================================================
FUNCTION PreDefinedKragon {
    // Countdown & attitude
    GLOBAL myCountdownTime IS 10.     // seconds before T-0
    GLOBAL myPitchAngle    IS 80.     // initial pitch at liftoff (degrees from horizon)
    GLOBAL myAzimuth       IS 90.     // launch azimuth (90 = due east)
    GLOBAL myRoll          IS 0.      // roll during ascent

    // Stage 1 (Kalcon) targets
    GLOBAL kalcon_meco_ap  IS 45000.  // Ap (m) at which to cut Kalcon and hand off

    // Stage 2 (Kragon) targets — passed to circ.ks
    GLOBAL target_Ap       IS 150000.
    GLOBAL target_Pe       IS 145000.
    GLOBAL orbitMode       IS 0.

    // ── Named landing pads ──────────────────────────────────
    //  Add or edit pads here.  The prelaunch menu references these by number.
    GLOBAL PAD_NAMES IS LIST("PAD 1", "PAD 2", "PAD 3", "Custom").
    GLOBAL PAD_LATS  IS LIST(-0.185464,  -0.205686,  -0.195547,  -0.0972).
    GLOBAL PAD_LNGS  IS LIST(-74.472935, -74.473032, -74.485164, -74.5577).
    //GLOBAL PAD_ALTS  IS LIST(69,          69,          69,          67).

    // Active pad (index into the lists above; 0 = PAD 1)
    GLOBAL selectedPad IS 0.
    GLOBAL pad_lat     IS PAD_LATS[0].
    GLOBAL pad_lng     IS PAD_LNGS[0].
    //GLOBAL pad_alt     IS PAD_ALTS[0].

    // Ascent tuning
    GLOBAL turn_start_alt  IS 700.        // AGL alt to begin gravity turn (m)
    GLOBAL maxq_press      IS 25.         // kPa — throttle-down threshold for Max-Q
    GLOBAL maxq_throt      IS 0.65.       // throttle during Max-Q window
    GLOBAL g_limit         IS 3.5.        // g-load ceiling during ascent
}

// ============================================================
//  DISPLAY
// ============================================================
FUNCTION DisplayParameters {
    CLEARSCREEN.
    PRINT "Kragon/Kalcon Parameters  (R=reset  #=edit  other=proceed)".
    PRINT "1. Countdown time:   " + myCountdownTime + " s".
    PRINT "2. Init pitch:       " + myPitchAngle + " deg".
    PRINT "3. Azimuth:          " + myAzimuth + " deg".
    PRINT "4. Roll:             " + myRoll + " deg".
    PRINT "5. Kalcon MECO Ap:   " + kalcon_meco_ap + " m".
    PRINT "6. Target Ap:        " + target_Ap + " m".
    PRINT "7. Target Pe:        " + target_Pe + " m".
    PRINT "8. Orbit mode:       " + orbitMode.
    PRINT "9. Landing pad:      [" + PAD_NAMES[selectedPad] + "]  " + pad_lat + " / " + pad_lng + " / " .//+ pad_alt + " m".
}

// ============================================================
//  NUMERIC INPUT
// ============================================================
FUNCTION GetNumericInput {
    PARAMETER prompt IS "new value".
    LOCAL inputString IS "".
    LOCAL inputRow IS 12.

    // Do not print on the terminal's bottom row here.  kOS still advances
    // the cursor after PRINT AT, and printing at HEIGHT-1 can scroll the
    // terminal so each partial value appears on a new line.  Keep the edit
    // field on a stable menu row and pad the whole line every redraw.
    PRINT FitLine("Editing " + prompt + "  (Enter to confirm):") AT (0, inputRow).
    PRINT FitLine("> ") AT (0, inputRow + 1).

    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR().
            IF ch = TERMINAL:INPUT:RETURN { BREAK. }
            ELSE IF ch = TERMINAL:INPUT:BACKSPACE {
                IF inputString:LENGTH > 0 {
                    SET inputString TO inputString:SUBSTRING(0, inputString:LENGTH - 1).
                }
            }
            ELSE IF (ch >= "0" AND ch <= "9") OR ch = "." OR ch = "-" {
                SET inputString TO inputString + ch.
            }
            PRINT FitLine("> " + inputString) AT (0, inputRow + 1).
        }
        WAIT 0.01.
    }
    IF inputString = "" { RETURN 0. }
    RETURN inputString:TONUMBER(0).
}

FUNCTION TargetPitch {
    LOCAL a IS SHIP:ALTITUDE.
    IF a <= turn_start_alt { RETURN myPitchAngle. }

    // 0 → 8km: gentle roll to 75° (nearly vertical)
    IF a < 8000 {
        LOCAL t IS Clamp((a - turn_start_alt) / (8000 - turn_start_alt), 0, 1).
        RETURN myPitchAngle + (75 - myPitchAngle) * t.
    }

    // 8 → 20km: ramp 75° → 55° (still steep — limiting Hspd buildup)
    IF a < 20000 {
        LOCAL t IS Clamp((a - 8000) / 12000, 0, 1).
        RETURN 75 + (55 - 75) * t.
    }

    // 20 → 35km: ramp 55° → 30° (approaching staging)
    IF a < 35000 {
        LOCAL t IS Clamp((a - 20000) / 15000, 0, 1).
        RETURN 55 + (30 - 55) * t.
    }

    // >35km: hold 30° — Kragon pitches further on its own after separation
    RETURN 30.
}

// ============================================================
//  AUDIO HELPERS
// ============================================================
FUNCTION KLAXON_START {
    PARAMETER voiceIdx IS 1, wave IS "sawtooth", vol IS 1.0.
    LOCAL V0 IS GETVOICE(voiceIdx).
    SET V0:WAVE TO wave.
    SET V0:VOLUME TO vol.
    SET V0:TEMPO TO 1.0.
    LOCAL whoop IS LIST(SLIDENOTE(400, 600, 0.35), SLIDENOTE(600, 400, 0.35)).
    SET V0:LOOP TO TRUE.
    V0:PLAY(whoop).
}

FUNCTION KLAXON_STOP {
    PARAMETER voiceIdx IS 1.
    GETVOICE(voiceIdx):STOP().
}

// ============================================================
//  MAIN PROGRAM START
// ============================================================
PreDefinedKragon().
PRINT "Mode 0 - Prelaunch".
PRINT "".
PRINT "Default parameters loaded.  Edit or proceed.".
UNTIL FALSE {
    DisplayParameters().
    LOCAL choice IS TERMINAL:INPUT:GETCHAR().
    IF      choice = "R" OR choice = "r" { PreDefinedKragon(). PRINT "Reset to defaults.". WAIT 1. }
    ELSE IF choice = "1" { SET myCountdownTime  TO GetNumericInput("Countdown time"). }
    ELSE IF choice = "2" { SET myPitchAngle     TO GetNumericInput("Initial pitch"). }
    ELSE IF choice = "3" { SET myAzimuth        TO GetNumericInput("Azimuth"). }
    ELSE IF choice = "4" { SET myRoll           TO GetNumericInput("Roll"). }
    ELSE IF choice = "5" { SET kalcon_meco_ap   TO GetNumericInput("Kalcon MECO Ap"). }
    ELSE IF choice = "6" { SET target_Ap        TO GetNumericInput("Target Ap"). }
    ELSE IF choice = "7" { SET target_Pe        TO GetNumericInput("Target Pe"). }
    ELSE IF choice = "8" { SET orbitMode        TO GetNumericInput("Orbit mode"). }
    ELSE IF choice = "9" {
        CLEARSCREEN.
        PRINT "── Select Landing Pad ───────────────────────────".
        LOCAL i IS 0.
        UNTIL i >= PAD_NAMES:LENGTH - 1 {   // all entries except the last "Custom" slot
            PRINT (i + 1) + ". " + PAD_NAMES[i] + "   " + PAD_LATS[i] + " / " + PAD_LNGS[i].
            SET i TO i + 1.
        }
        PRINT "C. Custom  (enter lat / lng / alt manually)".
        PRINT "".
        PRINT "Current: [" + PAD_NAMES[selectedPad] + "]  — any other key cancels.".

        LOCAL ch IS TERMINAL:INPUT:GETCHAR().

        // Numbered pad choices  (1 … n-1)
        LOCAL numPads IS PAD_NAMES:LENGTH - 1.   // number of named pads (excludes Custom)
        LOCAL idx IS ch:TONUMBER(-1).
        IF idx >= 1 AND idx <= numPads {
            SET selectedPad TO idx - 1.
            SET pad_lat TO PAD_LATS[selectedPad].
            SET pad_lng TO PAD_LNGS[selectedPad].
            //SET pad_alt TO PAD_ALTS[selectedPad].
            PRINT "Selected: " + PAD_NAMES[selectedPad].
            WAIT 0.8.

        // Custom entry
        } ELSE IF ch = "C" OR ch = "c" {
            SET selectedPad TO PAD_NAMES:LENGTH - 1.   // point at "Custom" slot
            PRINT "Latitude  (decimal degrees, S is negative):".
            SET pad_lat TO GetNumericInput("Landing pad latitude").
            PRINT "Longitude (decimal degrees, W is negative):".
            SET pad_lng TO GetNumericInput("Landing pad longitude").
            //PRINT "Elevation ASL (meters):".
            //SET pad_alt TO GetNumericInput("Landing pad elevation").
            // Overwrite the Custom slot in the lists so the display stays accurate
            SET PAD_LATS[selectedPad] TO pad_lat.
            SET PAD_LNGS[selectedPad] TO pad_lng.
            //SET PAD_ALTS[selectedPad] TO pad_alt.
            PRINT "Custom pad saved.".
            WAIT 0.8.

        } ELSE {
            PRINT "Cancelled.".
            WAIT 0.5.
        }
    }
    ELSE {
        PRINT "Proceeding with these parameters...".
        WAIT 3.
        BREAK.
    }
    WAIT 0.3.
}
DisplayParameters().
WAIT 4.
CLEARSCREEN.
PRINT "=================================================".
PRINT "         Starting Kragon Systems.".
PRINT "=================================================".
PRINT " ".
SAS OFF.
RCS OFF.
PRINT "Systems nominal.  Guidance online.".
AG10 ON.
// ACCESS ARM RETRACT
// FUELING OF KALCON 9
// FUELCELLS ON.
PRINT "Crew Access Arm Retracted".
//PRINT "Fuel Cells started and running".
PRINT "Starting pad fuel pumps.".
AG10 ON.
//AG9 ON. //TEMP to speed things up
WAIT 5.
PRINT "Fueling started.".
LOCAL fuelingComplete IS FALSE.
UNTIL fuelingComplete {
    LOCAL lfAmt IS 0.
    LOCAL lfCap IS 0.
    LOCAL oxAmt IS 0.
    LOCAL oxCap IS 0.
    LOCAL monoAmt IS 0.
    LOCAL monoCap IS 0.

    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LiquidFuel" {
        SET lfAmt TO res:AMOUNT.
        SET lfCap TO res:CAPACITY.
        }
        IF res:NAME = "Oxidizer" {
        SET oxAmt TO res:AMOUNT.
        SET oxCap TO res:CAPACITY.
        }
        IF res:NAME = "MonoPropellant" {
        SET monoAmt TO res:AMOUNT.
        SET monoCap TO res:CAPACITY.
        }
    }

    LOCAL lfPct IS 100.
    LOCAL oxPct IS 100.
    LOCAL moPct IS 100.

    IF lfCap > 0 { SET lfPct TO 100 * lfAmt / lfCap. }
    IF oxCap > 0 { SET oxPct TO 100 * oxAmt / oxCap. }
    IF monoCap > 0 { SET moPct TO 100 * monoAmt / monoCap. }

    // Treat "missing resource" as already satisfied (capacity 0).
    LOCAL lfOK IS (lfCap <= 0) OR (lfAmt / lfCap >= 0.999).
    LOCAL oxOK IS (oxCap <= 0) OR (oxAmt / oxCap >= 0.999).
    LOCAL monoOK IS (monoCap <= 0) OR (monoAmt / monoCap >= 0.999).
    SET fuelingComplete TO lfOK AND oxOK AND monoOK.

    PRINT FitLine("LF: " + ROUND(lfPct,1) + "%  OX: " + ROUND(oxPct,1) + "%  MONO: " + ROUND(moPct,1) + "%      ") AT (0, 11).

    IF NOT fuelingComplete { WAIT 0.5. }
}
AG9 ON.
PRINT "Fueling complete".
PRINT "Guidance online.".
PRINT "Upper launch clamp retracting.".
WAIT 5.
PRINT "Strongback Tower moved to postion 1".
PRINT "Press any key to arm launch...".
LOCAL prelaunchArmKey IS TERMINAL:INPUT:GETCHAR().


// Steering/throttle are locked once here. Later guidance code only
// updates these command variables, including inside loops.
GLOBAL guidanceThrottleCmd IS 0.
GLOBAL guidanceSteeringCmd IS SHIP:FACING.
LOCK THROTTLE TO guidanceThrottleCmd.
LOCK STEERING TO guidanceSteeringCmd.

LOCAL voice IS getVoice(0).
LOCAL voiceTickNote IS NOTE(480, 0.1).
LOCAL voiceLiftoffNote IS NOTE(720, 1).

PRINT FitLine("Abort key: Backspace") AT (0, 25).
WHEN TRUE THEN {
    IF SHIP:ALTITUDE < 30000 {
        IF ABORT {
            HUDTEXT("ABORT! ABORT!", 10, 2, 30, red, TRUE).
            PRINT FitLine(">>> ABORT SEQUENCE <<<") AT (0, 24).
            SET guidanceThrottleCmd TO 1.
            UNLOCK STEERING.
            SAS ON.
            ABORT OFF.
            KLAXON_START(1, "sawtooth", 0.3).
            WAIT 3.
            KLAXON_STOP().
            PRINT FitLine("Manual Control Returned") AT (0, 23).
            RETURN FALSE.
        }
        PRESERVE.
    } ELSE {
        RETURN FALSE.
    }
}

// ── Ignition ramp variables ───────────────────────────────
LOCAL ignitionStarted IS FALSE.
LOCAL ignitionStartTime IS 0.
LOCAL rampSec IS 2.0.

// Smooth throttle command ramp on engine start. The throttle lock is
// installed once below; this trigger only updates the command variable.
WHEN TRUE THEN {
    IF ignitionStarted {
        LOCAL elapsed IS TIME:SECONDS - ignitionStartTime.
        LOCAL u IS Clamp(elapsed / rampSec, 0, 1).
        SET guidanceThrottleCmd TO u * u. // quadratic ease-in
        IF u < 1 { PRESERVE. }
    } ELSE {
        PRESERVE.
    }
}

// ── Countdown ────────────────────────────────────────────
CLEARSCREEN.
PRINT "==============================================".
PRINT "     KRAGON / KALCON LAUNCH SEQUENCE".
PRINT "==============================================".
PRINT "Pad: " + pad_lat + "°  " + pad_lng + "°   MECO Ap: " + kalcon_meco_ap / 1000 + " km".

FROM { LOCAL countdown IS myCountdownTime. }
UNTIL countdown < 0
STEP { SET countdown TO countdown - 1. }
DO {
    PRINT FitLine("T-" + countdown + "         ") AT (0, 4).
    HUDTEXT("T- " + countdown, 1.5, 2, 18, white, FALSE).

    // T-6: Kalcon engine ignition + throttle ramp
    IF countdown = 2 AND NOT ignitionStarted {
        PRINT FitLine("Kalcon Engine Start             ") AT (0, 14).
        SET guidanceThrottleCmd TO 0.
        STAGE.                               // fire Kalcon engines
        SET ignitionStarted TO TRUE.
        SET ignitionStartTime TO TIME:SECONDS.
    }

    // T-0: Release launch clamps
    IF countdown = 0 {
        PRINT FitLine("Clamp Release — Liftoff!        ") AT (0, 15).
        AG8 ON.
        STAGE.
        SET guidanceSteeringCmd TO LOOKDIRUP(HEADING(90,90):VECTOR, SHIP:FACING:TOPVECTOR).
        voice:PLAY(voiceLiftoffNote).
        IF SHIP:AVAILABLETHRUST <= SHIP:MASS * 9.81 {
            PRINT FitLine("IGNITION FAILURE — HOLDING      ") AT (0, 16).
            SET guidanceThrottleCmd TO 0.
        }
    }

    IF ignitionStarted { PRINT FitLine("Throttle: " + ROUND(THROTTLE * 100, 1) + "%     ") AT (0, 8). }
    IF countdown <= 5 AND countdown > 0 { voice:PLAY(voiceTickNote). }

    // Abort / Hold keys during countdown
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL key IS TERMINAL:INPUT:GETCHAR().
        IF key = "A" OR key = "a" {
            HUDTEXT("ABORT! ABORT ABORT!", 5, 2, 15, red, TRUE).
            SET guidanceThrottleCmd TO 0.
            KLAXON_START(1, "sawtooth", 0.2).
            WAIT 5.
            KLAXON_STOP().
            WAIT 10.
            REBOOT.
        }
        IF key = "H" OR key = "h" {
            HUDTEXT("HOLD..HOLD..HOLD!", 5, 2, 15, yellow, TRUE).
            SET guidanceThrottleCmd TO 0.
            SET ignitionStarted TO FALSE.
            SET countdown TO myCountdownTime + 1.

            CLEARSCREEN.
            PRINT FitLine(">>> LAUNCH HOLD <<<") AT (0, 0).
            PRINT FitLine("Press any key to resume...") AT (0, 5).
            LOCAL holdResumeKey IS TERMINAL:INPUT:GETCHAR().
            WAIT 1.
        }
    }

    WAIT 1.
}

// ============================================================
//  MODE 1 — LIFTOFF
// ============================================================
SET MODE TO 1.
PRINT FitLine("Mode 1 - Liftoff                                ") AT (0, 0).
SET guidanceThrottleCmd TO 1.0.

WAIT UNTIL SHIP:ALTITUDE > 200.
SET guidanceSteeringCmd TO HEADING(myAzimuth, 90, myRoll).

WAIT UNTIL SHIP:ALTITUDE > turn_start_alt.
SET guidanceSteeringCmd TO HEADING(myAzimuth, myPitchAngle, myRoll).

// ============================================================
//  MODE 2 — ASCENT / GRAVITY TURN  (Kalcon burning)
// ============================================================
SET MODE TO 2.
PRINT FitLine("Mode 2 - Ascent / Gravity Turn                  ") AT (0, 0).

LOCAL smoothedThrottle IS 1.0.
LOCAL throttleSlewPerSec IS 0.35.
LOCAL lastT IS TIME:SECONDS.
LOCAL targetThrottle IS 1.0.
LOCAL maxQReached IS FALSE.
LOCAL maxQPassed IS FALSE.
LOCAL dynQPeak IS 0.

UNTIL SHIP:APOAPSIS >= kalcon_meco_ap {

    LOCAL dynPressKpa IS SHIP:DYNAMICPRESSURE * 101.325.

    // Max-Q throttle management
    IF (NOT maxQReached) AND (dynPressKpa >= maxq_press) {
        SET maxQReached TO TRUE.
        SET targetThrottle TO maxq_throt.
        SET dynQPeak TO dynPressKpa.
        PRINT FitLine("MAX-Q — Throttling back         ") AT (0, 16).
    }
    IF maxQReached AND NOT maxQPassed {
        IF dynPressKpa > dynQPeak { SET dynQPeak TO dynPressKpa. }
        IF dynPressKpa <= (dynQPeak * 0.90) {
            SET maxQPassed TO TRUE.
            SET targetThrottle TO 1.0.
            PRINT FitLine("MAX-Q PASSED — Full throttle   ") AT (0, 16).
        }
    }

    // G-limit clamp
    LOCAL g0 IS 9.80665.
    LOCAL throttleCmd IS targetThrottle.
    IF SHIP:MASS > 0 {
        LOCAL g_est IS SHIP:AVAILABLETHRUST / (SHIP:MASS * g0).
        IF g_est > g_limit AND g_est > 0 {
            SET throttleCmd TO throttleCmd * (g_limit / g_est).
        }
    }
    SET throttleCmd TO Clamp(throttleCmd, 0, 1).

    // Throttle slew (prevents step changes)
    LOCAL nowT IS TIME:SECONDS.
    LOCAL dt IS Clamp(nowT - lastT, 0, 0.5).
    SET lastT TO nowT.
    LOCAL maxStep IS throttleSlewPerSec * dt.
    LOCAL diff IS Clamp(throttleCmd - smoothedThrottle, -maxStep, maxStep).
    SET smoothedThrottle TO Clamp(smoothedThrottle + diff, 0, 1).
    SET guidanceThrottleCmd TO smoothedThrottle.

    // Gravity turn steering
    LOCAL pitchCmd IS Clamp(TargetPitch(), 0, 90).
    SET guidanceSteeringCmd TO HEADING(myAzimuth, pitchCmd, myRoll).

    // Telemetry display
    PRINT FitLine("Alt:     " + ROUND(SHIP:ALTITUDE / 1000, 2) + " km      ") AT (0, 4).
    PRINT FitLine("Ap:      " + ROUND(SHIP:APOAPSIS / 1000, 1) + " km  (target " + ROUND(kalcon_meco_ap / 1000, 1) + " km)   ") AT (0, 5).
    PRINT FitLine("Speed:   " + ROUND(SHIP:VELOCITY:SURFACE:MAG) + " m/s     ") AT (0, 6).
    PRINT FitLine("DynPres: " + ROUND(dynPressKpa, 1) + " kPa       ") AT (0, 7).
    PRINT FitLine("Pitch:   " + ROUND(pitchCmd, 1) + " deg       ") AT (0, 8).
    PRINT FitLine("Throttle:" + ROUND(THROTTLE * 100, 1) + "%           ") AT (0, 9).

    WAIT 0.01.
}

// ============================================================
//  MODE 3 — MECO / KALCON HANDOFF / SEPARATION
// ============================================================
SET MODE TO 3.
CLEARSCREEN.
PRINT FitLine("Mode 3 - MECO / Kalcon Handoff                  ") AT (0, 0).
PRINT FitLine("Ap target reached: " + ROUND(SHIP:APOAPSIS / 1000, 1) + " km") AT (0, 2).

// Step 1: Write pad parameters to Kalcon's volume
PRINT FitLine("Writing RTLS parameters to Kalcon volume...") AT (0, 4).
LOCAL paramPath IS "0:/rtls_params.ks".

// Remove stale file if present
IF EXISTS(paramPath) { DELETEPATH(paramPath). }

// Write using LOG statement — kOS file object WRITELN is not valid
LOG "// Auto-generated by kragon_ascent.ks at MECO" TO paramPath.
LOG "SET rtls_pad_lat TO " + pad_lat + "." TO paramPath.
LOG "SET rtls_pad_lng TO " + pad_lng + "." TO paramPath.
//LOG "SET rtls_pad_alt TO " + pad_alt + "." TO paramPath.

PRINT FitLine("RTLS params written to 0:/rtls_params.ks") AT (0, 20).

// Step 2: Activate the Kalcon processor
//         kalcon_boot.ks will detect the params file and run falcon9_rtls
PRINT FitLine("Activating Kalcon processor...") AT (0, 5).
PROCESSOR("Kalcon9"):ACTIVATE().

// Step 3: Brief pause — let Kalcon CPU boot and read the params file
//         before we cut engines and lose the inter-vehicle volume access
WAIT 1.5.

// Step 4: MECO — cut Kalcon engines
PRINT FitLine("MECO — Kalcon Engine Cutoff") AT (0, 6).
SET guidanceThrottleCmd TO 0.
WAIT 1.0.

// Step 5: Separation
PRINT FitLine("Kalcon Separation") AT (0, 7).
// Point prograde for a clean horizontal separation
SET guidanceSteeringCmd TO PROGRADE.
WAIT 2.0.
STAGE.    // decouple Kalcon

// Step 6: Coast — let separation distance build
PRINT FitLine("Coasting — building separation distance...") AT (0, 8).
WAIT 2.0.
AG2 ON.
// Step 7: Kragon engine ignition
PRINT FitLine("Kragon Engine Ignition!") AT (0, 9).
//STAGE.                          // fire Kragon second stage engine
SET guidanceThrottleCmd TO 1.0.
PRINT FitLine("Abort fins retracted") AT (0, 10).
WAIT 1.

// ============================================================
//  MODE 4 — KRAGON SECOND STAGE BURN
// ============================================================
SET MODE TO 4.
CLEARSCREEN.
PRINT FitLine("Mode 4 - Kragon Second Stage Burn               ") AT (0, 0).

// Burn prograde until Ap ≥ target_Ap.
// After max-Q is long gone, full throttle is fine.
// A simple Pe-build: once Ap is set, pitch toward horizon.
LOCAL stage2SlewLast IS TIME:SECONDS.
LOCAL stage2Smoothed IS 1.0.

UNTIL (SHIP:APOAPSIS >= target_Ap) { //AND SHIP:PERIAPSIS >= -5000) {

    // Simple Ap-hold: back off throttle when Ap is close
    LOCAL apErr IS target_Ap - SHIP:APOAPSIS.
    LOCAL tCmd IS Clamp(apErr / 5000, 0.15, 1.0).

    LOCAL dt2 IS Clamp(TIME:SECONDS - stage2SlewLast, 0, 0.5).
    SET stage2SlewLast TO TIME:SECONDS.
    LOCAL step2 IS 0.35 * dt2.
    SET stage2Smoothed TO Clamp(stage2Smoothed + Clamp(tCmd - stage2Smoothed, -step2, step2), 0, 1).
    SET guidanceThrottleCmd TO stage2Smoothed.

    // Pitch: drive to horizon once Ap ≥ target; otherwise follow turn schedule
    LOCAL pitchS2 IS 0.
    IF SHIP:APOAPSIS < target_Ap {
        SET pitchS2 TO Clamp(TargetPitch(), -5, 30).
    }
    SET guidanceSteeringCmd TO HEADING(myAzimuth, pitchS2, myRoll).

    PRINT FitLine("Alt:     " + ROUND(SHIP:ALTITUDE / 1000, 2) + " km       ") AT (0, 4).
    PRINT FitLine("Ap:      " + ROUND(SHIP:APOAPSIS / 1000, 1) + " km        ") AT (0, 5).
    PRINT FitLine("Pe:      " + ROUND(SHIP:PERIAPSIS / 1000, 1) + " km        ") AT (0, 6).
    PRINT FitLine("Throttle:" + ROUND(THROTTLE * 100, 1) + "%            ") AT (0, 7).

    // Safety cutoff — don't overshoot Ap badly
    IF SHIP:APOAPSIS >= (target_Ap + 8000) { BREAK. }

    WAIT 0.01.
}

// Stage 2 SECO
SET guidanceThrottleCmd TO 0.
UNLOCK STEERING.
SAS ON.
RCS ON.
PRINT FitLine("Stage 2 SECO") AT (0, 9).
PRINT FitLine("Handing off to Orbit circularization.") AT (0, 10).
WAIT 3.

// ============================================================
//  MODE 4b — CIRCULARIZATION HANDOFF
// ============================================================
// Wait until above atmosphere before circularizing
WAIT UNTIL SHIP:ALTITUDE > 70000.

IF SHIP:PERIAPSIS < 70000 {
    RUNPATH("circ.ks", SHIP:APOAPSIS, target_Pe, orbitMode).
} ELSE IF SHIP:APOAPSIS >= target_Ap + 5000 {
    RUNPATH("circ.ks", SHIP:APOAPSIS, target_Pe, orbitMode).
} ELSE {
    RUNPATH("circ.ks", target_Ap, target_Pe, orbitMode).
}

// ============================================================
//  MODE 5 — ORBIT ESTABLISHED
// ============================================================
SET MODE TO 5.
CLEARSCREEN.
PRINT "=================================================".
PRINT "Mode 5 - Orbit Established".
PRINT "=================================================".
PRINT "Apoapsis:  " + ROUND(SHIP:ORBIT:APOAPSIS / 1000, 1) + " km".
PRINT "Periapsis: " + ROUND(SHIP:ORBIT:PERIAPSIS / 1000, 1) + " km".
SAS ON.
RCS OFF.
UNLOCK STEERING.
UNLOCK THROTTLE.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
PRINT "".
PRINT ">>>>> KRAGON ASCENT COMPLETE <<<<<".
