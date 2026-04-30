// KOS Script for Rocket Launch Orbital Flight (Project Kemini)
// Version 1.0 - Taking Saturn IB script and modifying for Saturn V.

// Mode 0 - Prelaunch
CLEARSCREEN.
GLOBAL MODE IS 0.
// SET holdTime TO 0.
SET Recycle TO FALSE.
// Predefined function sets default values
PROCESSOR("SATV"):DEACTIVATE().

PreDefined(). 
PreLaunch().

SET voice to getVoice(0).
SET voiceTickNote to NOTE(480, 0.1).
SET voiceTakeOffNote to NOTE(720, 1).

// Variables for ignition sequence
LOCAL ignitionStarted IS FALSE.
LOCAL ignitionStartTime IS 0.
SET rampSec TO 8.0.  // Ramp throttle over the last 8 seconds of countdown

SetupAbortDetection().

// Set up smooth throttle ramp trigger (runs in background)
WHEN TRUE THEN {
    IF ignitionStarted {
        LOCAL elapsed IS TIME:SECONDS - ignitionStartTime.
        LOCAL u IS elapsed / rampSec.
        IF u > 1 { SET u TO 1. }
        // Quadratic ease-in (feels like "spool"); use u for linear
        LOCAL targetThr IS u * u.
        LOCK THROTTLE TO targetThr.
        
        // Continue updating until ramp complete
        IF u < 1 {
            PRESERVE.
        }
    } ELSE {
        PRESERVE.  // Keep checking until ignition starts
    }
}

//PRINT "myLiftOff value: " + myLiftOff AT (0,20).
// Countdown Clock
FROM {local countdown is myCountdownTime.} UNTIL countdown <= 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown + " " AT (0,3).
    HUDTEXT("T- " + countdown, 1.5, 2, 18, white, FALSE).
    
    IF countdown = 9 AND NOT ignitionStarted {
        PRINT "Ignition Sequence Started!" AT (0,5).
        
        // Lock throttle and steering
        LOCK THROTTLE TO 0.
        LOCK STEERING TO LOOKDIRUP( HEADING(90, 90):VECTOR, SHIP:FACING:TOPVECTOR ).
        
        // Calculate remaining stages after engine ignition
        LOCAL myStage IS MAX(0, myLiftOff - 1).
        
        // First staging: Ignite engines
        Staging(0.5).
        PRINT "Engines igniting..." AT (0,6).
        SET myStage TO myStage - 1.
        
        // Mark ignition as started - throttle ramp begins
        SET ignitionStarted TO TRUE.
        SET ignitionStartTime TO TIME:SECONDS.
        
        // Set up WHEN trigger to retract arms when throttle reaches 70%
        WHEN THROTTLE >= 0.70 AND myStage > 0 THEN {
            PRINT "Engines at 70%, retracting arms..." AT (0,7).
            UNTIL myStage <= 0 {
                Staging(0.1).
                SET myStage TO myStage - 1.
            }
        }
        
        IF SHIP:AVAILABLETHRUST <= 0 {
            PRINT "Ignition failure – clamps holding." AT (0,10).
            LOCK THROTTLE TO 0.
        }
    }
    
    // Display current throttle
    IF ignitionStarted {
        PRINT "Throttle: " + ROUND(THROTTLE * 100) + "%    " AT (0,6).
    }
    
    // Countdown tick sounds
    IF countdown <= 5 {
        voice:PLAY(voiceTickNote).
    }
    
    // Check for abort or hold
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL key IS TERMINAL:INPUT:GETCHAR().
        IF key = "A" OR key = "a" {
            HUDTEXT ("ABORT! ABORT ABORT!", 5, 2, 15, red, TRUE).
            PRINT "Launch has been aborted." AT (0,5).
            LOCK THROTTLE TO 0.  // Cut throttle immediately
            WAIT 0.1.  // Allow a physic tick
            KLAXON_START(1, "sawtooth", 0.2).
            WAIT 5.
            KLAXON_STOP().
            WAIT 10.
            REBOOT.
        }
        IF key = "H" or key = "h" {
            HUDTEXT ("HOLD..HOLD..HOLD!", 5, 2, 15, yellow, TRUE).
            PRINT "Launch has been placed in a hold!" AT (0,5).
            LOCK THROTTLE TO 0.  // Cut throttle during hold
            SET ignitionStarted TO FALSE.  // Reset ignition flag
            SET countdown TO myCountdownTime + 1.
            LaunchHold().
        }
    }
    
    WAIT 1.
}

// Mode 1 - Liftoff!
SET MODE TO 1.
PRINT "Mode 1 - Launch".
voice:PLAY(voiceTakeOffNote).

// Ensure throttle is at 100%
LOCK THROTTLE TO 1.0.
LOCK STEERING TO LOOKDIRUP( HEADING(90, 90):VECTOR, SHIP:FACING:TOPVECTOR ).

// Release clamps → Liftoff!
Staging(1).
HUDTEXT ("LIFT-OFF!", 10, 2, 20, yellow, TRUE).

// Pitch briefly to avoid launch complex
//PRINT "Launch Pad Avoidance Maneuver.".
WAIT UNTIL SHIP:ALTITUDE > 300.

PRINT "ROLL PROGRAM!". 
LOCK STEERING TO HEADING(90, myPitchAngle, myRoll).
PRINT "PITCH PROGRAM Pitching to: " + myPitchAngle + "°".
WAIT 0.1.  //Allow physic tick.

// Mode 2 - Ascent including Max Q
SET MODE TO 2.
LOCAL FIRSTSTAGE IS TRUE.
LOCAL SECONDSTAGE IS FALSE.
LOCAL centerEngineCut IS FALSE.
LOCAL mecoPrep IS FALSE.
PRINT "Mode 2 - Ascent and Gravity turn".

// Main ascent loop - handles both gravity turn AND staging checks
UNTIL SECONDSTAGE AND SHIP:ALTITUDE > 40000 {
    
    // === GRAVITY TURN LOGIC ===
    IF SHIP:ALTITUDE >= 2000 AND SHIP:ALTITUDE < 25000 {
        SET pitchAngle TO myPitchAngle - ((SHIP:ALTITUDE - 2000) * (40 / 28000)).
        IF pitchAngle < 40 { SET pitchAngle TO 40. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle, myRoll).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
    }
    
    IF SHIP:ALTITUDE >= 25000 AND SHIP:ALTITUDE < 35000 {
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle, myRoll).
    }
    
    IF SHIP:ALTITUDE >= 35000 {
        LOCK STEERING TO HEADING(myAzimuth, 40, (myRoll -180)).
        PRINT "Holding 40 degrees, Roll to crew heads up." AT (0, 21).
    }
    
    // === STAGING CHECKS ===
    
    // Center engine cutoff at 20% fuel
    IF FIRSTSTAGE AND NOT centerEngineCut AND STAGE:LIQUIDFUEL < (STAGE:RESOURCESLEX["LiquidFuel"]:CAPACITY * 0.07) {
        PRINT "First Stage Center Engine Cut-off." AT (0, 11).
        FOR eng IN SHIP:ENGINES{
            IF eng:TAG = "F1CUT" {
                eng:SHUTDOWN.
            }
        }
        SET centerEngineCut TO TRUE.
    }
    
    // MECO prep at 5% fuel
    IF FIRSTSTAGE AND NOT mecoPrep AND STAGE:LIQUIDFUEL < (STAGE:RESOURCESLEX["LiquidFuel"]:CAPACITY * 0.03) {
        PRINT "Preparing for Main Engine Cut-off." AT (0, 11).
        LOCK STEERING TO PROGRADE.
        SET mecoPrep TO TRUE.
    }
    
    // First stage burnout
    IF FIRSTSTAGE AND STAGE:LIQUIDFUEL < 0.1 AND STAGE:OXIDIZER < 0.1 {
        PRINT "MECO!" AT (0, 12).
        LOCK THROTTLE TO 0.
        Staging(0.5).  // FIRST AND SECOND STAGE SEPERATION.
        PRINT "First stage Jettison." AT (0, 13).
        WAIT 2.
        LOCK THROTTLE TO 1.  // SECOND STAGE THROTTLE UP.
        Staging(2).  // Tower Jettison
        PRINT "Escape tower jettison." AT (0, 14).
        Staging(3). 
        Staging(1).
        PRINT "Interstage Jettisoned!" AT (0, 15).
        SET FIRSTSTAGE TO FALSE.
        //SET SECONDSTAGE TO TRUE.
    }
    
    WAIT 0.1.  // Loop delay
}

// Second stage burnout
WAIT UNTIL STAGE:LIQUIDFUEL < 0.1 OR SHIP:APOAPSIS >= 115000. 
PRINT "SECO!" AT (0, 16).
LOCK THROTTLE TO 0.
Staging(1).
LOCK THROTTLE TO 1.
PRINT "Second stage Jettison." AT (0, 17).
Staging(3).
PRINT "Third stage ignition!" AT (0, 18).
WAIT 3.
AG8 ON. // Toggles Ullage motors on third stage.

PRINT "============Ascent complete!==============" AT (0, 22).
// Mode 3 - Coast to Target Apoapsis
SET MODE TO 3.
PRINT "Mode 3 - Burning to target apoapsis".

// Continue burning until apoapsis reaches target
UNTIL SHIP:ORBIT:APOAPSIS >= target_Ap {
    PRINT "Current Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km  Target: " + ROUND(target_Ap/1000, 1) + " km    " AT (0, 21).
    WAIT 0.1.
}

// Cut throttle when we hit target apoapsis
LOCK THROTTLE TO 0.
PRINT "Target apoapsis reached - S-IVB ENGINE CUTOFF!" AT (0, 22).
PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0, 23).
PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 24).

// Mode 4 - Orbit Circularization and MECO
SET MODE TO 4.
PRINT "Mode 4 - Orbit Circularization and MECO".

// Ullage trigger that handles multiple sequential nodes
LOCAL lastNodeTime IS -999.

// Ullage and third stage J2 control while circ running.
WHEN HASNODE AND NEXTNODE:ETA <= 60 THEN {  // Catch it early
    LOCAL currentNodeTime IS TIME:SECONDS + NEXTNODE:ETA.
    
    IF ABS(currentNodeTime - lastNodeTime) > 30 {
        SET lastNodeTime TO currentNodeTime.
        
        // Calculate when the burn will actually START
        LOCAL burnDuration IS NEXTNODE:DELTAV:MAG / (SHIP:AVAILABLETHRUST / SHIP:MASS).
        LOCAL burnStartETA IS burnDuration / 2.  // Circ starts burn at half-duration
        LOCAL ullageStartETA IS burnStartETA + 10.  // Fire ullage 10 seconds before burn
        
        PRINT "Burn duration: " + ROUND(burnDuration, 1) + "s" AT (0, 20).
        PRINT "Burn starts at T-" + ROUND(burnStartETA, 1) + "s" AT (0, 21).
        PRINT "Ullage at T-" + ROUND(ullageStartETA, 1) + "s" AT (0, 22).
        
        // Wait until it's time for ullage
        WAIT UNTIL NEXTNODE:ETA <= ullageStartETA.
        
        PRINT "Shutting down main engine for ullage..." AT (0, 23).
        AG9 ON.  // Turn off S-IVB J2 Engine
        WAIT 1.
        LOCK THROTTLE TO 1.  //making sure they fire!
        PRINT "Ullage motors firing!" AT (0, 24).
        AG8 OFF.  // Fire ullage motors
        WAIT 5.
        
        PRINT "Restarting main engine..." AT (0, 25).
        AG9 OFF.  // Restart main engine
        WAIT 3.
        AG8 ON.  // Shut off ullage
        
        //PRINT "Ullage complete - ready for burn." AT (0, 26).
    }
    
    PRESERVE.
}

run circ (target_Ap, target_Pe, orbitMode).

// Lock steering to prograde for the maneuver
LOCK STEERING TO PROGRADE.

// Shut down sustainer engine
CLEARSCREEN.
PRINT "Cleaning up orbit.".
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,4).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,5).
PRINT "Third Stage shutdown!" AT (0,7).
WAIT 10.
AG9 ON.  // Shuts down SIV-B J2 Engine.

//Capsule seperation.
PROCESSOR("SATV"):ACTIVATE().
PRINT "S-IVB processor should be active." AT (0, 8).
// Force CSM to stay in control temporarily
//Staging(10).  Staging now handled by S-IVB Stage.
WAIT 5.
AG7 ON.
RCS ON.
PRINT "CSM seperated from booster!" AT (0, 7).
SET SHIP:CONTROL:FORE TO 1.
WAIT 2.
SET SHIP:CONTROL:FORE TO 0.

LOCK THROTTLE TO 0.
// Final clean up.
CLEARSCREEN.
WAIT 30.
LOCK STEERING TO RETROGRADE. // Pitch to retrograde
SET MODE TO 5.
CLEARSCREEN.
PRINT "Mode 5 - Orbit operations.".
PRINT "Final orbital parameters:".
PRINT "---------------------" AT (0, 2).
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,3).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,4).
WAIT 10.
PRINT "End of ascent program." AT (0, 10).
WAIT 2.
RCS OFF.
UNLOCK STEERING.
SAS ON.
REBOOT.
// END OF PROGRAM.

// Abort Detection Function - User must click outside terminal for abort to work
FUNCTION SetupAbortDetection {
    PRINT "Abort detection active (Backspace to abort)" AT (0, 22).
    PRINT "NOTE: Click outside terminal window for abort to work!" AT (0, 23).
    
    WHEN TRUE THEN {
        IF SHIP:ALTITUDE < 21000 {
            IF ABORT {
                // ABORT SEQUENCE
                PRINT ">>> ABORT SEQUENCE INITIATED <<<" AT (0, 24).
                HUDTEXT("ABORT! ABORT! ABORT!", 10, 2, 30, red, TRUE).
                
                LOCK THROTTLE TO 0.
                UNLOCK STEERING.
                SAS ON.
                ABORT OFF.
                
                KLAXON_START(1, "square", 0.3).
                WAIT 3.
                KLAXON_STOP().
                
                PRINT "Manual control returned to pilot" AT (0, 25).
                RETURN FALSE.
            }
            PRESERVE.
        } ELSE {
            PRINT "Abort detection disabled (above 20km)" AT (0, 23).
            RETURN FALSE.
        }
    }
}

FUNCTION LaunchHold {
    CLEARSCREEN.
    PRINT "Currently launch is in a HOLD!" AT (0, 5).
    PRINT "When ready to proceed, press any key..." AT (0,6).
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    WAIT 1.
    UNSET dummy.
}

// DEBUG FUNCTION TO PAUSE SCREEN.
FUNCTION Debug{
    PRINT "Press any key to continue....".
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    WAIT 1.
    UNSET dummy.
}

// Staging Function
FUNCTION Staging {
    PARAMETER holdTime.
    WAIT holdTime.
    STAGE.
}

// Resource Capacity Check
FUNCTION GetResourceCapacity {
    PARAMETER resourceName.
    FOR resource IN SHIP:RESOURCES {
        IF resource:NAME = resourceName {
            RETURN resource:CAPACITY.
        }
    }
    RETURN 0.
}

FUNCTION KLAXON_START {
    PARAMETER voiceIdx IS 1.
    PARAMETER wave IS "sawtooth". // "square", "triangle", "sine", "noise" also valid
    PARAMETER vol IS 1.0.

    SET V0 TO GETVOICE(voiceIdx).
    SET V0:WAVE TO wave.
    SET V0:VOLUME TO vol.
    SET V0:TEMPO TO 1.0.

    // Two sliding notes make a classic “whoop”
    SET whoop TO LIST(
        SLIDENOTE(400, 600, 0.35), // rise
        SLIDENOTE(600, 400, 0.35)  // fall
    ).

    SET V0:LOOP TO TRUE.
    V0:PLAY(whoop).               // plays in background, returns immediately
}

FUNCTION KLAXON_STOP {
    PARAMETER voiceIdx IS 1.
    GETVOICE(voiceIdx):STOP().
}

// Prelaunch Configuration
FUNCTION PreLaunch {
    IF Recycle{
        SET Recycle TO FALSE.
    }
    PRINT "Mode 0 - Prelaunch".
    PRINT "".
    PRINT "The following are the default parameters. Select the number to change, or any other key to proceed.".
    UNTIL FALSE {
        DisplayParameters().
        LOCAL choice IS TERMINAL:INPUT:GETCHAR().
        IF choice = "R" OR choice = "r" {
            PreDefined().
            PRINT "Parameters reset to defaults.".
            WAIT 1.
        } ELSE IF choice = "1" {
            SET myCountdownTime TO GetNumericInput().
            PRINT "Countdown Time set to: " + myCountdownTime.
        } ELSE IF choice = "2" {
            SET myPitchAngle TO GetNumericInput().
            PRINT "Pitch Angle set to: " + myPitchAngle.
        } ELSE IF choice = "3" {
            SET myAzimuth TO GetNumericInput().
            PRINT "Azimuth set to: " + myAzimuth.
        } ELSE IF choice = "4" {
            SET myRoll TO GetNumericInput().
            PRINT "Roll set to: " + myRoll.
        } ELSE IF choice = "5" {
            SET target_Ap TO GetNumericInput().
            PRINT "Target Apoapsis set to: " + target_Ap.
        } ELSE IF choice = "6" {
            SET target_Pe TO GetNumericInput().
            PRINT "Target Periapsis set to: " + target_Pe.
        } ELSE IF choice = "7" {
            SET myLiftOff TO GetNumericInput().
            PRINT "STAGES to LiftOff set to: " + myLiftOff.
        } ELSE IF choice = "8" {
            SET orbitMode TO GetNumericInput().
            PRINT "Orbit Mode set to: " + orbitMode + " (0=Coast, 1=Throttle, 2=Continuous)".
        } ELSE {
            PRINT "Proceeding with current values...".
            BREAK.
        }
        WAIT 0.5.
    }
    PRINT "Final parameters:".
    DisplayParameters().
    SAS OFF.
    RCS OFF.
    PRINT "Retracting crane and damper arm.".
    AG6 ON.  //ACTION GROUP 6 Assigned to Crane and Arm.
    WAIT 10.
    PRINT "Guidance computers ON. (e.g. SAS OFF)".
    //LOCK STEERING TO HEADING(90, 90, 0).
    PRINT "INITIATING GYROS. (e.g. Lock Steering to straight up.)".
    WAIT 1.
    PRINT "When ready to proceed, press any key...".
    SET dummy TO TERMINAL:INPUT:GETCHAR().
    WAIT 1.
    UNSET dummy.
    prepareLaunch().
}

// Default Parameters
FUNCTION PreDefined {
    GLOBAL myCountdownTime TO 10.      // Countdown timer
    GLOBAL myPitchAngle TO 85.         // Pitch angle for gravity turn
    GLOBAL myAzimuth TO 90.            // Azimuth (90 = due east)
    GLOBAL myRoll TO 0.                // Roll
    GLOBAL target_Ap TO 250000.        // Target Apoapsis
    GLOBAL target_Pe TO 200000.        // Target Periapsis
    GLOBAL myLiftOff TO 4.             // Stages until liftoff
    GLOBAL orbitMode TO 0.             // Orbit mode: 0=Coast, 1=Throttle, 2=Continuous

    IF Recycle{
        PreLaunch().
    }
}

// Display Parameters
FUNCTION DisplayParameters {
    CLEARSCREEN.
    PRINT "The following are the default parameters.".
    PRINT "Select a number to change, 'R' to reset, or any other key to proceed.".
    PRINT " ".
    PRINT "1. Countdown Time: " + StripPadding(myCountdownTime).
    PRINT "2. Pitch Angle: " + StripPadding(myPitchAngle).
    PRINT "3. Azimuth: " + StripPadding(myAzimuth).
    PRINT "4. Roll: " + StripPadding(myRoll).
    PRINT "5. Target Apoapsis: " + StripPadding(target_Ap).
    PRINT "6. Target Periapsis: " + StripPadding(target_Pe).
    PRINT "7. STAGES to LiftOff: " + StripPadding(myLiftOff).
    PRINT "8. Orbit Mode: " + orbitMode + " (0=Coast, 1=Throttle, 2=Continuous)".
    PRINT " ".
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

// Strip Padding
FUNCTION StripPadding {
    PARAMETER num.
    LOCAL numStr IS "" + num.
    UNTIL numStr:STARTSWITH("0") = FALSE {
        IF numStr:LENGTH > 1 {
            SET numStr TO numStr:SUBSTRING(1, numStr:LENGTH - 1).
        } ELSE {
            BREAK.
        }
    }
    RETURN numStr.
}

// ========== helpers ==========
// Build a lexicon with keys "start","toggle","stop" from a part module's
// action/event names (case-insensitive substring match).
FUNCTION GET_ACT_NAMES {
    PARAMETER fuelMod1.
    LOCAL names IS fuelMod1:ALLACTIONNAMES.
    IF names:LENGTH = 0 { SET names TO fuelMod1:ALLEVENTNAMES. }

    LOCAL startName  IS "".
    LOCAL toggleName IS "".
    LOCAL stopName   IS "".

    FOR a IN names {
        LOCAL la IS a:TOLOWER().
        IF startName  = "" AND la:CONTAINS("start")  { SET startName  TO a. }
        IF toggleName = "" AND la:CONTAINS("toggle") { SET toggleName TO a. }
        IF stopName   = "" AND la:CONTAINS("stop")   { SET stopName   TO a. }
    }

    LOCAL acts IS LEXICON().
    SET acts["start"]  TO startName.
    SET acts["toggle"] TO toggleName.
    SET acts["stop"]   TO stopName.
    RETURN acts.
}

// Call as ACTION if present, else as EVENT.
FUNCTION DO_CMD {
    PARAMETER targetMod, cmdName.
    IF cmdName = "" { RETURN. }
    IF targetMod:ALLACTIONNAMES:CONTAINS(cmdName) {
        targetMod:DOACTION(cmdName, TRUE).
    } ELSE IF targetMod:ALLEVENTNAMES:CONTAINS(cmdName) {
        targetMod:DOEVENT(cmdName).
    }
}

// Resolve best "drain" command strings for ModuleResourceDrain.
// Returns a LEXICON with "start","toggle","stop" for a ModuleResourceDrain
FUNCTION GET_DRAIN_CMDS {
    PARAMETER drainMod.
    LOCAL startName  IS "".
    LOCAL toggleName IS "".
    LOCAL stopName   IS "".

    // Build a combined list of names (kOS can't "+" lists)
    LOCAL names IS LIST().
    FOR n IN drainMod:ALLACTIONNAMES { names:ADD(n). }
    FOR n IN drainMod:ALLEVENTNAMES { names:ADD(n). }

    // Try to find "start/toggle/stop" that also mention "drain"
    FOR n IN names {
        LOCAL lowerName IS n:TOLOWER().
        IF startName  = "" AND lowerName:CONTAINS("start")  AND lowerName:CONTAINS("drain") { SET startName  TO n. }
        IF toggleName = "" AND lowerName:CONTAINS("toggle") AND lowerName:CONTAINS("drain") { SET toggleName TO n. }
        IF stopName   = "" AND lowerName:CONTAINS("stop")   AND lowerName:CONTAINS("drain") { SET stopName   TO n. }
    }

    // Fallback: some valves expose just "Drain"
    IF startName = "" {
        FOR n IN names {
            IF n:TOLOWER() = "drain" { SET startName TO n. BREAK. }
        }
    }

    LOCAL m IS LEXICON().
    SET m["start"]  TO startName.
    SET m["toggle"] TO toggleName.
    SET m["stop"]   TO stopName.
    RETURN m.
}

// --- Full Detank Helper Function ---
FUNCTION FullDetank {
    PARAMETER drainList, cmdList, totalLF, totalOX, totalMono.
    
    CLEARSCREEN.
    PRINT "=== FULL DETANK ===" AT (0, 0).
    PRINT "" AT (0, 1).
    PRINT "Starting full detank of all tanks..." AT (0, 2).
    
    // Start all drains
    FOR i IN RANGE(0, drainList:LENGTH) {
        LOCAL d IS drainList[i].
        LOCAL cm IS cmdList[i].
        DO_CMD(d, cm["start"]).
    }
    PRINT "All drain valves started." AT (0, 3).
    PRINT "Press '9' to stop detank" AT (0, 4).
    PRINT "" AT (0, 5).
    
    LOCAL detankLine IS 6.
    UNTIL ROUND(SHIP:LIQUIDFUEL, 2) <= 0 AND ROUND(SHIP:OXIDIZER, 2) <= 0 {
        LOCAL lfPercent IS 0.
        LOCAL oxPercent IS 0.
        LOCAL monoPercent IS 0.
        
        IF totalLF > 0 { SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / totalLF) * 100). }
        IF totalOX > 0 { SET oxPercent TO ROUND((SHIP:OXIDIZER / totalOX) * 100). }
        IF totalMono > 0 { SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / totalMono) * 100). }
        
        PRINT "Detanking: LF " + ROUND(SHIP:LIQUIDFUEL) + " (" + lfPercent + "%)  OX " + ROUND(SHIP:OXIDIZER) + " (" + oxPercent + "%)  Mono " + ROUND(SHIP:MONOPROPELLANT) + " (" + monoPercent + "%)    " AT (0, detankLine).
        
        IF TERMINAL:INPUT:HASCHAR {
            SET k TO TERMINAL:INPUT:GETCHAR().
            IF k = "9" {
                PRINT "Detank stopped by user                  " AT (0, detankLine + 1).
                BREAK.
            }
        }
        WAIT 0.5.
    }
    
    // Stop all drains
    FOR i IN RANGE(0, drainList:LENGTH) {
        LOCAL d IS drainList[i].
        LOCAL cm IS cmdList[i].
        IF cm["stop"] <> "" { 
            DO_CMD(d, cm["stop"]). 
        } ELSE IF cm["toggle"] <> "" { 
            DO_CMD(d, cm["toggle"]). 
        }
    }
    
    PRINT "" AT (0, detankLine + 2).
    PRINT "Detank complete. Final: LF " + ROUND(SHIP:LIQUIDFUEL,1) + "  OX " + ROUND(SHIP:OXIDIZER,1) + "  Mono " + ROUND(SHIP:MONOPROPELLANT,1) AT (0, detankLine + 3).
    WAIT 2.
}

// ========== main ==========
// Launch Preparation
//  NOTE: For fueling and other pad functions to work you need to create a module manager cfg to read the fuel/power, etc options.  See your 
//  SimNASA folder under GAMEDATA for more information.
// Launch Preparation with SIVB Partial Fueling
// Strategy: Fill everything to 100%, then drain SIVB to target percentage
FUNCTION prepareLaunch {
    CLEARSCREEN.
    PRINT "Launch Preparation Script" AT (0, 0).

    // --- Set your desired SIVB tank fuel percentage here ---
    SET SIVB_TARGET_PERCENT TO 100.  // Drain SIVB down to 50% (adjust as needed)

    // --- locate the stand part ---
    SET basePart TO 0.
    FOR p IN SHIP:PARTS {
        IF p:NAME = "AM_MLP_SaturnMobileLauncherClampBase" OR p:TITLE:TOLOWER():CONTAINS("Saturn Launcher Base") {
            SET basePart TO p.
            BREAK.
        }
    }
    IF basePart = 0 {
        PRINT "Error: No Saturn Launch Stand found." AT (0, 1).
        WAIT 5.
        REBOOT.
    }

    // --- activate generators ---
    LOCAL genCount IS 0.
    LOCAL currentLine IS 2.
    FOR moduleName IN basePart:ALLMODULES {
        IF moduleName = "ModuleGenerator" {
            SET genCount TO genCount + 1.
            SET genModule TO basePart:GETMODULE(moduleName).
            IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
                genModule:DOACTION("activate generator", TRUE).
                PRINT "Activated generator " + genCount + " on stand" AT (0, currentLine).
                SET currentLine TO currentLine + 1.
            } ELSE IF genModule:ALLEVENTNAMES:CONTAINS("activate generator") {
                genModule:DOEVENT("activate generator").
                PRINT "Activated generator " + genCount + " (event) on stand" AT (0, currentLine).
                SET currentLine TO currentLine + 1.
            }
        }
    }

    // --- find FuelingSystem ---
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    SET fuelMod TO 0.
    FOR mn IN basePart:ALLMODULES {
        IF mn = "ModuleResourceConverter" {
            LOCAL m IS basePart:GETMODULE(mn).
            IF m:ALLACTIONNAMES:CONTAINS("Start Fueling") OR m:ALLEVENTNAMES:CONTAINS("Start Fueling") {
                SET fuelMod TO m.
                BREAK.
            }
        }
    }
    IF fuelMod = 0 {
        PRINT "Error: FuelingSystem not found on stand." AT (0, currentLine).
        WAIT 5.
        REBOOT.
    }
    SET FUEL_ACTS TO GET_ACT_NAMES(fuelMod).

    // --- collect ALL drain valves and identify which are on SIVB ---
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    SET allValveDrains TO LIST().
    SET sivbValveDrains TO LIST().
    
    FOR p IN SHIP:PARTS {
        IF p:NAME = "ReleaseValve" {
            FOR mn IN p:ALLMODULES {
                IF mn = "ModuleResourceDrain" {
                    LOCAL drainMod IS p:GETMODULE(mn).
                    allValveDrains:ADD(drainMod).
                    
                    // Check if this valve is attached to a SIVB-tagged part
                    IF p:PARENT:TAG = "SIVB" {
                        sivbValveDrains:ADD(drainMod).
                    }
                }
            }
        }
    }
    
    IF allValveDrains:LENGTH = 0 {
        PRINT "Error: No ModuleResourceDrain found on ReleaseValve parts." AT (0, currentLine).
        WAIT 8.
        REBOOT.
    }

    SET ALL_DRAIN_CMDS TO LIST().
    FOR d IN allValveDrains {
        ALL_DRAIN_CMDS:ADD(GET_DRAIN_CMDS(d)).
    }
    
    SET SIVB_DRAIN_CMDS TO LIST().
    FOR d IN sivbValveDrains {
        SIVB_DRAIN_CMDS:ADD(GET_DRAIN_CMDS(d)).
    }

    // --- Find SIVB tank(s) by kOS tag ---
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    SET lfCap TO 0. 
    SET oxCap TO 0.
    SET monoCap TO 0.

    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LiquidFuel" { SET lfCap TO res:CAPACITY. }
        IF res:NAME = "Oxidizer" { SET oxCap TO res:CAPACITY. }
        IF res:NAME = "MonoPropellant" { SET monoCap TO res:CAPACITY. }
    }

    CLEARSCREEN.
    PRINT "=== FUELING PLAN ===" AT (0, 0).
    PRINT "Step 1: Fill ALL tanks to 100%" AT (0, 1).
    SET currentLine TO 2.
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Total Capacities - LF: " + ROUND(lfCap) + "  OX: " + ROUND(oxCap) + "  Mono: " + ROUND(monoCap) AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Press 'S' to start fueling to 100%" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Any other key to abort" AT (0, currentLine).
    SET currentLine TO currentLine + 1.

    // --- fueling start ---
    WAIT UNTIL TERMINAL:INPUT:HASCHAR.
    LOCAL startKey IS TERMINAL:INPUT:GETCHAR().
    IF startKey = "S" OR startKey = "s" {
        DO_CMD(fuelMod, FUEL_ACTS["start"]).
        PRINT "" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
        PRINT "=== FUELING TO 100% ===" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
        PRINT "FuelingSystem started" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
        PRINT "Press '0' to toggle fueling, '9' to abort" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
        PRINT "" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
    } ELSE {
        PRINT "" AT (0, currentLine).
        SET currentLine TO currentLine + 1.
        PRINT "Fueling not started. Aborting..." AT (0, currentLine).
        WAIT 5.
        REBOOT.
    }

    // --- Standard fueling loop to 100% ---
    LOCAL fuelLine IS currentLine.
    LOCAL fuelingAborted IS FALSE.
    UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
        LOCAL lfPercent IS 0.
        LOCAL oxPercent IS 0.
        LOCAL monoPercent IS 0.
        
        IF lfCap > 0 { SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / lfCap) * 100). }
        IF oxCap > 0 { SET oxPercent TO ROUND((SHIP:OXIDIZER / oxCap) * 100). }
        IF monoCap > 0 { SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / monoCap) * 100). }

        PRINT "Fueling: LF " + ROUND(SHIP:LIQUIDFUEL) + " (" + lfPercent + "%)  OX " + ROUND(SHIP:OXIDIZER) + " (" + oxPercent + "%)  Mono " + ROUND(SHIP:MONOPROPELLANT) + " (" + monoPercent + "%)    " AT (0, fuelLine).

        IF TERMINAL:INPUT:HASCHAR {
            SET keyF TO TERMINAL:INPUT:GETCHAR().
            IF keyF = "0" {
                IF FUEL_ACTS["toggle"] <> "" {
                    DO_CMD(fuelMod, FUEL_ACTS["toggle"]).
                } ELSE {
                    IF FUEL_ACTS["stop"] <> "" { DO_CMD(fuelMod, FUEL_ACTS["stop"]). }
                    WAIT 0.1.
                    DO_CMD(fuelMod, FUEL_ACTS["start"]).
                }
                PRINT "Fueling toggled (on/off)                " AT (0, fuelLine + 1).
            }
            IF keyF = "9" {
                IF FUEL_ACTS["stop"] <> "" { DO_CMD(fuelMod, FUEL_ACTS["stop"]). }
                PRINT "Fueling aborted by user                 " AT (0, fuelLine + 1).
                SET fuelingAborted TO TRUE.
                BREAK.
            }
        }
        WAIT 0.5.
    }

    // Stop fueling
    IF FUEL_ACTS["stop"] <> "" { DO_CMD(fuelMod, FUEL_ACTS["stop"]). }
    
    // Handle abort case
    IF fuelingAborted {
        PRINT "" AT (0, fuelLine + 2).
        PRINT "Fueling incomplete. Press 'D' to detank, any other key to abort" AT (0, fuelLine + 3).
        LOCAL abortChoice IS TERMINAL:INPUT:GETCHAR().
        IF abortChoice = "D" OR abortChoice = "d" {
            // Call full detank function
            FullDetank(allValveDrains, ALL_DRAIN_CMDS, lfCap, oxCap, monoCap).
        }
        PRINT "Aborting launch preparation..." AT (0, fuelLine + 4).
        WAIT 5.
        REBOOT.
    }
    
    PRINT "Fueling to 100% complete!          " AT (0, fuelLine + 1).
    PRINT "Final: LF " + ROUND(SHIP:LIQUIDFUEL,1) + "  OX " + ROUND(SHIP:OXIDIZER,1) + "  Mono " + ROUND(SHIP:MONOPROPELLANT,1) AT (0, fuelLine + 2).
    WAIT 2.
    SET currentLine TO fuelLine + 4.

    // Fueling complete - proceed to launch
    WAIT 2.
    PRINT "" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "=== FUELING COMPLETE ===" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Press 'P' to proceed to launch countdown" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Press 'D' to detank all" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    PRINT "Any other key to abort" AT (0, currentLine).
    SET currentLine TO currentLine + 1.
    LOCAL choice IS TERMINAL:INPUT:GETCHAR().
    
    IF choice = "P" OR choice = "p" {
        PRINT "Proceeding to launch..." AT (0, currentLine).
        WAIT 1.
        // Raise/Retract the crew access arm
        PRINT "Retracting crew access arm...." AT (0, 24).
        AG10 ON.
        WAIT 5.  // Give it time to retract
        PRINT "Crew arm operation complete. Press 'P' to proceed or 'A' to abort" AT (0, 25).
        PRINT "Fuel Cells now active and at full power." AT (0, 26).
        LOCAL finalChoice IS TERMINAL:INPUT:GETCHAR().
        IF finalChoice = "P" OR finalChoice = "p" {
            PRINT "Proceeding to countdown..." AT (0, 27).
            PRINT "Launch prep complete. Ready for liftoff!" AT (0, 28).
            WAIT 3.
        } ELSE IF finalChoice = "A" OR finalChoice = "a" {
            PRINT "ABORT...ABORT...ABORT!" AT (0, 26).
            WAIT 5.
            REBOOT.
        } ELSE {
            PRINT "Invalid input. Aborting..." AT (0, 26).
            WAIT 5.
            REBOOT.
        }
        CLEARSCREEN.
        RETURN.
    } ELSE IF choice = "D" OR choice = "d" {
        FullDetank(allValveDrains, ALL_DRAIN_CMDS, lfCap, oxCap, monoCap).
        PRINT "Detank complete. Aborting launch preparation..." AT (0, currentLine).
        WAIT 5.
        REBOOT.
    } ELSE {
        PRINT "Aborting..." AT (0, currentLine).
        WAIT 5.
        REBOOT.
    }
    CLEARSCREEN.
}