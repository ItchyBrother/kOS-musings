// KOS Script for Rocket Launch Orbital Flight (Project Kemini)
// Version 1.0 - Taking KerbAtlas script and modifying.
// Version 1.1 - Fixed detanking issue.
// Version 1.2 - Added a Recycle Script option at the end of Detanking.
// Version 1.3 - Added HOLD/ABORT sequences.  Plus several HUD TEXTs
// Version 1.4 - Added a main engine throttle up.
// Version 1.5 - Removed the run once circ as it was impacting the subsequent running to raise Pe after orbit insert.
// Version 1.6 - Added Gemini Titan Second stage deorbit.

// Mode 0 - Prelaunch
CLEARSCREEN.
GLOBAL MODE IS 0.
// SET holdTime TO 0.
SET Recycle TO FALSE.
// Predefined function sets default values
PROCESSOR("Titan"):DEACTIVATE().

PreDefined(). 
PreLaunch().

SET voice to getVoice(0).
SET voiceTickNote to NOTE(480, 0.1).
SET voiceTakeOffNote to NOTE(720, 1).
// Countdown Clock
FROM {local countdown is myCountdownTime.} UNTIL countdown <= 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown + " " AT (0,3).
    WAIT 1.
    IF countdown <= 5 {
        voice:PLAY(voiceTickNote).
    }
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL key IS TERMINAL:INPUT:GETCHAR().
        IF key = "A" OR key = "a" {
            HUDTEXT ("ABORT! ABORT ABORT!", 5, 2, 15, red, TRUE).
            PRINT "Launch has been aborted." AT (0,5).
            PRINT "Raising tower and extending panels." AT (0, 24).
            KLAXON_START(1, "sawtooth", 0.2).
            WAIT 5.
            AG7 OFF. 
            WAIT 30.
            KLAXON_STOP().
            AG6 OFF. 
            WAIT 10.
            REBOOT.
        }
        IF key = "H" or key = "h" {
            HUDTEXT ("HOLD..HOLD..HOLD!", 5, 2, 15, yellow, TRUE).
            PRINT "Launch has been placed in a hold!".
            SET countdown TO myCountdownTime + 1.
            LaunchHold().

        }
    }
}

// Mode 1 - Launch
SET MODE TO 1.
PRINT "Mode 1 - Launch".
LOCK THROTTLE TO 0.
LOCK STEERING TO LOOKDIRUP( HEADING(90, 90):VECTOR, SHIP:UP:VECTOR ).
voice:PLAY(voiceTakeOffNote).

// 1) Ignite engines, keep clamps engaged (fire all but the last liftoff stage)
LOCAL myStage IS MAX(0, myLiftOff - 1).
UNTIL myStage <= 0 {
  Staging(0.1).                 // your helper: stage, then wait 0.1 s
  SET myStage TO myStage - 1.
}

// 2) Ramp throttle smoothly to 100% over rampSec seconds
SET rampSec TO 3.0.             // tweak: 1.5–3.0 feels nice
LOCAL t0 IS TIME:SECONDS.
LOCAL startThr IS THROTTLE.     // in case it isn't exactly 0

UNTIL TIME:SECONDS - t0 >= rampSec {
  LOCAL u IS (TIME:SECONDS - t0) / rampSec.
  IF u > 1 { SET u TO 1. }.
  // Quadratic ease-in (feels like “spool”); use u for linear
  LOCAL targetThr IS startThr + (1 - startThr) * (u * u).
  LOCK THROTTLE TO targetThr.
  WAIT 0.05.
}
LOCK THROTTLE TO 1.0.

// 3) Sanity: confirm we actually have thrust (catches a failed light)
IF SHIP:AVAILABLETHRUST <= 0 {
  PRINT "Ignition failure — clamps holding.".
  // e.g., ABORT logic here: LOCK THROTTLE TO 0.  RETURN.
} ELSE {
  // 4) Release clamps → Liftoff!
  Staging(0.1).
  HUDTEXT ("LIFT-OFF!", 5, 2, 15, yellow, TRUE).
}

PRINT "Launch Pad Avoidance Maneuver.".
UNTIL SHIP:ALTITUDE > 200 {
    LOCK STEERING TO LOOKDIRUP( HEADING(90, 87):VECTOR, SHIP:UP:VECTOR ).  
    WAIT 2.
}
// Pitch briefly to avoid launch complex
//LOCK STEERING TO HEADING(90, 87). // 3 degrees east from vertical
PRINT "ROLL PROGRAM! Pitching to: " + myPitchAngle + "°".
LOCK STEERING TO HEADING(90, myPitchAngle).
WAIT 0.1.  //Allow physic tick.

// Mode 2 - Ascent including Max Q
SET MODE TO 2.
SET FIRSTSTAGE TO TRUE.
PRINT "Mode 2 - Ascent and Gravity turn".

// Phase 1: Pitch over more rapidly between 2 km and 30 km
WHEN SHIP:ALTITUDE >= 2000 THEN {
    UNTIL SHIP:ALTITUDE >= 30000 {
        SET pitchAngle TO myPitchAngle - ((SHIP:ALTITUDE - 2000) * (43 / 28000)). // 88° to 45°
        IF pitchAngle < 45 { SET pitchAngle TO 45. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
        IF STAGE:LIQUIDFUEL < 0.1 AND STAGE:OXIDIZER < 0.1 AND FIRSTSTAGE {
            // Perform first stage shutdown and staging.  Should happen around 20-40 km
            PRINT "MECO!".
            Staging(0.1).
            PRINT "First stage Jettison." AT (0, 12).
            PRINT "Second stage igniton!" AT (0, 13).
            SET FIRSTSTAGE TO FALSE.
        } 
        WAIT 0.1.
    }
}

UNTIL SHIP:ALTITUDE >= 40000 {

    // Phase 2 pitch control: 45° ➝ 5° between 30–45 km
    IF SHIP:ALTITUDE >= 30000 {
        SET pitchAngle TO 45 - ((SHIP:ALTITUDE - 30000) * (40 / 15000)). // 45 to 5
        IF pitchAngle < 5 { SET pitchAngle TO 5. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
        IF STAGE:LIQUIDFUEL < 0.1 AND STAGE:OXIDIZER < 0.1 AND FIRSTSTAGE {
            // Perform first stage shutdown and staging.  Should happen around 20-40 km
            PRINT "MECO!".
            Staging(0.1).
            PRINT "First stage Jettison." AT (0, 12).
            PRINT "Second stage igniton!" AT (0, 13).
            SET FIRSTSTAGE TO FALSE.
        }
    }
    WAIT 0.1.
}

LOCK STEERING TO PROGRADE.
PRINT "Gravity turn complete.  Holding Prograde."  AT (0, 24).

// Mode 4 - Orbit Circularization and MECO
SET MODE TO 4.
PRINT "Mode 4 - Orbit Circularization and MECO".

run circ (target_Ap, target_Pe, orbitMode).

// Lock steering to prograde for the maneuver
LOCK STEERING TO PROGRADE.

// Shut down sustainer engine
CLEARSCREEN.
PRINT "Cleaning up orbit.".
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,4).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,5).
PRINT "SECO!" AT (0,7).
WAIT 20.

//Capsule seperation.
PROCESSOR("Titan"):ACTIVATE().
Staging(10).
PRINT "Capsule seperated from booster!" AT (0, 7).
RCS ON.
SET SHIP:CONTROL:FORE TO 1.
SET SHIP:CONTROL:TOP TO 1.
SET SHIP:CONTROL:STARBOARD TO -1.
WAIT 2.
SET SHIP:CONTROL:FORE TO 0.
SET SHIP:CONTROL:TOP TO 0.
SET SHIP:CONTROL:STARBOARD TO 0.
LOCK THROTTLE TO 0.
// Final clean up.
CLEARSCREEN.

IF SHIP:ALTITUDE < 70000 {
    HUDTEXT ("WAITING TO EXIT ATMOSPHERE @ 70K.", 5, 2, 20, YELLOW, TRUE).
}
// Waiting until we are outside Kerbin atmophere before proceeding.
WAIT UNTIL SHIP:ALTITUDE > 70000.
SET TgtApPE TO FALSE.
IF SHIP:ORBIT:PERIAPSIS < target_Pe  {
    PRINT "Running Circulazation program." AT (0, 10).
    WAIT 5.
    IF SHIP:ORBIT:APOAPSIS < target_Ap AND target_Pe > SHIP:ORBIT:APOAPSIS {
        run circ(target_Pe, SHIP:ORBIT:APOAPSIS, 0, TRUE).
        SET TgtApPE TO TRUE.
    } ELSE {
    run circ(SHIP:ORBIT:APOAPSIS, target_Pe, 0, TRUE).
    }   
}

IF TgtApPE {
    run circ(target_Ap, target_Pe, 0, TRUE).
    PRINT "PROGRAM COMPLETE.  REBOOTING COMPUTER IN 40 seconds." AT (0,10).
} 
    
PRINT "PROGRAM COMPLETE.  REBOOTING COMPUTER IN 40 seconds." AT (0,10).

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
REBOOT.
// END OF PROGRAM.

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
    PRINT "Guidance computers ON. (e.g. SAS OFF)".
    LOCK STEERING TO HEADING(90, 90).
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
    GLOBAL target_Ap TO 120000.        // Target Apoapsis
    GLOBAL target_Pe TO 80000.         // Target Periapsis
    GLOBAL myLiftOff TO 2.             // Stages until liftoff
    GLOBAL orbitMode TO 2.             // Orbit mode: 0=Coast, 1=Throttle, 2=Continuous

    IF Recycle{
        PreLaucch().
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

// ========== main ==========
// Launch Preparation
//  NOTE: For fueling and other pad functions to work you need to create a module manager cfg to read the fuel/power, etc options.  See your 
//  SimNASA folder under GAMEDATA for more information.
FUNCTION prepareLaunch {
    CLEARSCREEN.
    PRINT "Launch Preparation Script" AT (0, 0).

    // --- locate the stand part (prefer internal name; fallback to title match) ---
    SET basePart TO 0.
    FOR p IN SHIP:PARTS {
        IF p:NAME = "AM_MLP_TitanIILaunchStand" OR p:TITLE:TOLOWER():CONTAINS("titan ii launch stand") {
            SET basePart TO p.
            BREAK.
        }
    }
    IF basePart = 0 {
        PRINT "Error: No Titan II Launch Stand found." AT (0, 1).
        WAIT 5.
        REBOOT.
    }

    // --- activate any ModuleGenerators on the stand ---
    LOCAL genCount IS 0.
    FOR moduleName IN basePart:ALLMODULES {
        IF moduleName = "ModuleGenerator" {
            SET genCount TO genCount + 1.
            SET genModule TO basePart:GETMODULE(moduleName).
            IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
                genModule:DOACTION("activate generator", TRUE).
                PRINT "Activated generator " + genCount + " on stand" AT (0, 1 + genCount).
            } ELSE IF genModule:ALLEVENTNAMES:CONTAINS("activate generator") {
                genModule:DOEVENT("activate generator").
                PRINT "Activated generator " + genCount + " (event) on stand" AT (0, 1 + genCount).
            }
        }
    }

    // --- find FuelingSystem on the stand ---
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
        PRINT "Error: FuelingSystem not found on stand." AT (0, 5).
        WAIT 5.
        REBOOT.
    }
    SET FUEL_ACTS TO GET_ACT_NAMES(fuelMod).

    // --- collect all ModuleResourceDrain modules on ReleaseValve parts (rocket vessel) ---
    SET valveDrains TO LIST().
    FOR p IN SHIP:PARTS {
        IF p:NAME = "ReleaseValve" {
            FOR mn IN p:ALLMODULES {
                IF mn = "ModuleResourceDrain" {
                    valveDrains:ADD(p:GETMODULE(mn)).
                }
            }
        }
    }
    IF valveDrains:LENGTH = 0 {
        PRINT "Error: No ModuleResourceDrain found on ReleaseValve parts (rocket)." AT (0, 6).
        PRINT "Verify valves are on the ROCKET (not the stand) and present." AT (0, 7).
        WAIT 8.
        REBOOT.
    }

    // Resolve drain command names once per valve (optional debug prints if needed)
    SET DRAIN_CMDS_LIST TO LIST().
    FOR d IN valveDrains {
        DRAIN_CMDS_LIST:ADD(GET_DRAIN_CMDS(d)).
        // Uncomment for debugging:
        // PRINT "Drain actions: " + d:ALLACTIONNAMES.
        // PRINT "Drain events : " + d:ALLEVENTNAMES.
    }

    // --- capacity snapshot ---
    SET lfCap TO 0. SET oxCap TO 0. SET monoCap TO 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LiquidFuel" { SET lfCap TO res:CAPACITY. }
        IF res:NAME = "Oxidizer" { SET oxCap TO res:CAPACITY. }
        IF res:NAME = "MonoPropellant" { SET monoCap TO res:CAPACITY. }
    }
    PRINT "Capacities - LF: " + ROUND(lfCap) + "  OX: " + ROUND(oxCap) + "  Mono: " + ROUND(monoCap) AT (0, 9).
    PRINT "Press 'S' to start fueling, 0 to toggle, 9 to abort" AT (0, 10).
    PRINT "Initial LF: " + ROUND(SHIP:LIQUIDFUEL,2) + "  OX: " + ROUND(SHIP:OXIDIZER,2) + "  Mono: " + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 11).

    // --- fueling start ---
    WAIT UNTIL TERMINAL:INPUT:HASCHAR.
    LOCAL startKey IS TERMINAL:INPUT:GETCHAR().
    IF startKey = "S" OR startKey = "s" {
        DO_CMD(fuelMod, FUEL_ACTS["start"]).
        PRINT "FuelingSystem started" AT (0, 12).
    } ELSE {
        PRINT "Fueling not started. Aborting..." AT (0, 12).
        WAIT 5.
        REBOOT.
    }

    // --- fueling loop (no ternary) ---
    UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
        IF lfCap > 0 { SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / lfCap) * 100). } ELSE { SET lfPercent TO 0. }
        IF oxCap > 0 { SET oxPercent TO ROUND((SHIP:OXIDIZER   / oxCap) * 100). } ELSE { SET oxPercent TO 0. }
        IF monoCap > 0 { SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / monoCap) * 100). } ELSE { SET monoPercent TO 0. }

        PRINT "Fueling: LF: " + ROUND(SHIP:LIQUIDFUEL) + "  OX: " + ROUND(SHIP:OXIDIZER) + "  Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 13).
        PRINT "Percentages - LF: " + lfPercent + "%  OX: " + oxPercent + "%  Mono: " + monoPercent + "%" AT (0, 14).

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
                PRINT "Fueling toggled (on/off)" AT (0, 15).
            }
            IF keyF = "9" {
                IF FUEL_ACTS["stop"] <> "" { DO_CMD(fuelMod, FUEL_ACTS["stop"]). }
                PRINT "Fueling aborted" AT (0, 15).
                BREAK.
            }
        }
        WAIT 0.5.
    }

    // safety stop fueling
    IF FUEL_ACTS["stop"] <> "" { DO_CMD(fuelMod, FUEL_ACTS["stop"]). }
    PRINT "Fueling complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL,2) + "  OX: " + ROUND(SHIP:OXIDIZER,2) + "  Mono: " + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 16).

    // --- choose next step ---
    PRINT "Enter 'D' to detank, 'P' to proceed to launch" AT (0, 17).
    LOCAL choice IS TERMINAL:INPUT:GETCHAR().

    IF choice = "D" OR choice = "d" {
        PRINT "Tower must be lowered to detank Launch Vehicle." AT (0, 18).
        AG6 ON. 
        WAIT 10.
        KLAXON_START(1, "sawtooth", 0.2).
        WAIT 2.
        AG7 ON. 
        WAIT 35.
        KLAXON_STOP().

        PRINT "Starting detanking via valve drains..." AT (0, 19).

        // Start all drains
        FOR i IN RANGE(0, valveDrains:LENGTH) {
            LOCAL d  IS valveDrains[i].
            LOCAL cm IS DRAIN_CMDS_LIST[i].
            DO_CMD(d, cm["start"]).
        }
        PRINT "Drains started." AT (0, 20).

        // sanity snapshot
        SET _lf0 TO SHIP:LIQUIDFUEL.
        SET _ox0 TO SHIP:OXIDIZER.
        SET _mo0 TO SHIP:MONOPROPELLANT.
        SET _t0  TO TIME:SECONDS.
        SET _warned TO FALSE.

        // loop until empty (or keypress)
        UNTIL ROUND(SHIP:LIQUIDFUEL, 2) <= 0 AND ROUND(SHIP:OXIDIZER, 2) <= 0 {
            PRINT "Detanking: LF=" + ROUND(SHIP:LIQUIDFUEL) +
                  " OX=" + ROUND(SHIP:OXIDIZER) +
                  " Mono=" + ROUND(SHIP:MONOPROPELLANT) AT (0, 21).

            IF NOT _warned AND TIME:SECONDS - _t0 > 3 AND
               ROUND(SHIP:LIQUIDFUEL,3) = ROUND(_lf0,3) AND
               ROUND(SHIP:OXIDIZER,3) = ROUND(_ox0,3) AND
               ROUND(SHIP:MONOPROPELLANT,3) = ROUND(_mo0,3) {
                PRINT "Note: levels unchanged — ensure each valve is 'Drain Mode: Vessel', LF/OX/Mono enabled, and decoupler crossfeed ON." AT (0, 22).
                SET _warned TO TRUE.
            }

            IF TERMINAL:INPUT:HASCHAR {
                SET k TO TERMINAL:INPUT:GETCHAR().
                IF k = "0" {
                    // Toggle all drains
                    FOR j IN RANGE(0, valveDrains:LENGTH) {
                        LOCAL d2  IS valveDrains[j].
                        LOCAL cm2 IS DRAIN_CMDS_LIST[j].
                        IF cm2["toggle"] <> "" {
                            DO_CMD(d2, cm2["toggle"]).
                        } ELSE {
                            DO_CMD(d2, cm2["stop"]).
                            WAIT 0.1.
                            DO_CMD(d2, cm2["start"]).
                        }
                    }
                    PRINT "Detanking toggled (on/off)" AT (0, 22).
                }
                IF k = "9" {
                    // Stop all drains
                    FOR j2 IN RANGE(0, valveDrains:LENGTH) {
                        LOCAL d3  IS valveDrains[j2].
                        LOCAL cm3 IS DRAIN_CMDS_LIST[j2].
                        IF cm3["stop"] <> "" {
                            DO_CMD(d3, cm3["stop"]).
                        } ELSE IF cm3["toggle"] <> "" {
                            DO_CMD(d3, cm3["toggle"]).
                        }
                    }
                    PRINT "Detanking aborted" AT (0, 23).
                    BREAK.
                }
            }
            WAIT 0.5.
        }

        // Safety: stop all drains
        FOR k2 IN RANGE(0, valveDrains:LENGTH) {
            LOCAL d4  IS valveDrains[k2].
            LOCAL cm4 IS DRAIN_CMDS_LIST[k2].
            IF cm4["stop"] <> "" { DO_CMD(d4, cm4["stop"]). }
            ELSE IF cm4["toggle"] <> "" { DO_CMD(d4, cm4["toggle"]). }
        }

        PRINT "Detanking complete. Final LF=" + ROUND(SHIP:LIQUIDFUEL,2) +
              " OX=" + ROUND(SHIP:OXIDIZER,2) +
              " Mono=" + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 23).

        PRINT "Raising tower and extending panels." AT (0, 24).
        KLAXON_START(1, "sawtooth", 0.2).
        WAIT 2.
        AG7 OFF. 
        WAIT 35.
        KLAXON_STOP().
        AG6 OFF. 
        WAIT 10.
        PRINT "Press 'P' to proceed to RECYCLE or any other key to ABORT." AT (0, 25).
        WAIT UNTIL TERMINAL:INPUT:HASCHAR.
        LOCAL contKey IS TERMINAL:INPUT:GETCHAR().
        IF contKey = "P" OR contKey = "p" {
            PRINT "Recycle launch script in 10 seconds." AT (0 , 26).
            SET Recycle TO TRUE.
            WAIT 10.
            PreDefined().
        } ELSE {
            PRINT "Aborting Launch..." AT (0, 26).
            WAIT 5.
            REBOOT.
        }
    }

    // --- normal tower sequence ---
    PRINT "Retracting Tower Panels." AT (0, 24).
    AG6 ON.  
    WAIT 10.
    PRINT "LOWERING TOWER!" AT (0, 25).
    KLAXON_START(1, "sawtooth", 0.2).
    WAIT 2.
    AG7 ON.  
    WAIT 35.
    KLAXON_STOP().
    PRINT "Tower lowering complete. Press 'P' to proceed or 'A' to abort" AT (0, 25).
    LOCAL finalChoice IS TERMINAL:INPUT:GETCHAR().
    IF finalChoice = "P" OR finalChoice = "p" {
        PRINT "Tower lowered, proceeding to countdown..." AT (0, 26).
    } ELSE IF finalChoice = "A" OR finalChoice = "a" {
        PRINT "ABORT...ABORT...ABORT!" AT (0, 26).
        PRINT "RAISING TOWER!" AT (0, 27).
        KLAXON_START(1, "sawtooth", 0.5).
        AG7 ON.  
        WAIT 40.
        KLAXON_STOP().
        PRINT "Extending Tower panels." AT (0, 28).
        AG6 ON. 
        WAIT 10.
        PRINT "RECYCLING COUNTDOWN!"  AT (0, 30).
        WAIT 5.
        REBOOT.
    } ELSE {
        PRINT "Invalid input. Aborting..." AT (0, 26).
        WAIT 5.
        REBOOT.
    }

    PRINT "Launch prep complete. Ready for liftoff!" AT (0, 27).
    WAIT 1.
    CLEARSCREEN.
}