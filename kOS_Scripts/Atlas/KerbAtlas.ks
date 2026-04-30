// KOS Script for Rocket Launch Orbital Flight (Project Kercury)
// Version 1.0 - Updated for orbitMode parameter and integrated circularization logic
// Version 2.0 - Added Booster shutdown sequence to mimic real Mercury-Atlas.  
// Adjusted booster engines to provide equalivent thrust with Module Manager.
// Modified LV-T30 with 373.5 kN of thrust ISP of 292 VAC 247 SEA.
// Modified LV-T45 with 3 degrees gimbal.  Use only at 60% thrust.
// Remove gravity turn function and hardcoded gravity turn based on Atlas Mercury. 

// Mode 0 - Prelaunch
CLEARSCREEN.
GLOBAL MODE IS 0.
SET holdTime TO 0.
PROCESSOR("KAtlas"):DEACTIVATE(). //Turning off the booster processor.
SET voice to getVoice(0).
SET voiceTickNote to NOTE(480, 0.1).
SET voiceTakeOffNote to NOTE(720, 1).

// Predefined function sets default values
PreDefined(). 
PreLaunch().

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
            PRINT "Launch ABORTED!" AT (0,4).
            WAIT 5. 
            REBOOT.
        }
    }
}

// Mode 1 - Launch
SET MODE TO 1.
PRINT "Mode 1 - Launch".
LOCK THROTTLE TO 1.0.
voice:PLAY(voiceTakeOffNote).
FROM {LOCAL myStage IS myLiftOff.} UNTIL myStage = 0 STEP {SET myStage TO myStage -1.} DO {
    Staging(1).
}
PRINT "LIFT-OFF!".

UNTIL SHIP:ALTITUDE > 100 {
    WAIT 0.1.
}

// Pitch briefly to avoid launch complex
LOCK STEERING TO HEADING(90, 87). // 3 degrees east from vertical
PRINT "Launch Pad Avoidance Maneuver.".
WAIT 2.
LOCK STEERING TO HEADING(90, 90).
WAIT 0.1.  //Allow physic tick.

// Mode 2 - Ascent including Max Q
SET MODE TO 2.
PRINT "Mode 2 - Ascent and Gravity turn".

// Phase 1: Pitch over more rapidly between 2 km and 30 km
WHEN SHIP:ALTITUDE >= 2000 THEN {
    UNTIL SHIP:ALTITUDE >= 30000 {
        SET pitchAngle TO 88 - ((SHIP:ALTITUDE - 2000) * (43 / 28000)). // 88° to 45°
        IF pitchAngle < 45 { SET pitchAngle TO 45. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
        WAIT 0.1.
    }
}

//LOGIC TO THROTTLE DOWN BOOSTERS PRIOR TO SEPERATION.
// Get list of all engines
LIST ENGINES IN allEngines.

SET boosterEngines TO LIST().

FOR eng IN allEngines {
    IF eng:NAME = "liquidEngine.v2" {  // These are the modified LT-V30 engines.
        boosterEngines:ADD(eng).
    }
}

UNTIL SHIP:ALTITUDE >= 45000 {

    // Phase 2 pitch control: 45° ➝ 5° between 30–45 km
    IF SHIP:ALTITUDE >= 30000 {
        SET pitchAngle TO 45 - ((SHIP:ALTITUDE - 30000) * (40 / 15000)). // 45 to 5
        IF pitchAngle < 5 { SET pitchAngle TO 5. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
    }

    // Escape Tower Jettison at 35 km
    IF SHIP:ALTITUDE >= 35000 AND MODE <> 3 {
        SET MODE TO 3.
        PRINT "Mode 3 - Booster and Escape tower jettison".
        AG1 ON. // Jettison escape tower.
        PRINT "Escape Tower Jettisoned!".
        WAIT 0.1.
    }

        // Booster throttle-down: 100% ➝ 0% between 40–45 km
    IF SHIP:ALTITUDE >= 40000 {
        SET scaleFactor TO 1 - ((SHIP:ALTITUDE - 40000) / 5000).
        SET scalePercent TO MAX(0, scaleFactor * 100).
        FOR b IN boosterEngines {
            SET b:THRUSTLIMIT TO scalePercent.
        }
        PRINT "Throttling boosters to " + ROUND(scalePercent, 1) + "%" AT (0, 21).
        
    }

    WAIT 0.1.
}

// Perform shutdown and staging at 45 km
AG10 ON. // Custom action group for booster engine shutdown
PRINT "Booster Shutdown." AT (0, 11).
Staging(2).
PRINT "Booster Jettison." AT (0, 12).

LOCK STEERING TO PROGRADE.
PRINT "Gravity turn complete.  Holding Prograde."  AT (0, 24).

// Mode 4 - Orbit Circularization and MECO
SET MODE TO 4.
PRINT "Mode 4 - Orbit Circularization and MECO".

run once circ (target_Ap, target_Pe, orbitMode).

// Lock steering to prograde for the maneuver
LOCK STEERING TO PROGRADE.

// Shut down sustainer engine (assuming AG7 toggles it off)
CLEARSCREEN.
PRINT "Cleaning up orbit.".
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,4).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,5).
PRINT "Shutting down sustainer engine." AT (0,7).
AG7 ON. // Assuming AG7 turns sustainer off

// Re-enable sustainer engine
PRINT "Enabling sustainer engine." AT (0,8).
AG7 OFF. // AG7 toggles sustainer back on
WAIT 0.1.
PRINT "Pending capsule separation." AT (0,9).
WAIT 5.
PRINT "Activating booster computer." AT (0,10).
PROCESSOR("KAtlas"):ACTIVATE().
WAIT 5.
PRINT "Booster computer active, Capsule Seperation!" AT (0,11).
Staging(1).

// Final clean up.
CLEARSCREEN.
RCS ON.
WAIT 30.
LOCK STEERING TO RETROGRADE. // Pitch to retrograde
SET MODE TO 5.
CLEARSCREEN.
PRINT "Mode 5 - Orbit operations.".
PRINT "Final orbital parameters:".
PRINT "---------------------" AT (0, 2).
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,3).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,4).
WAIT UNTIL FALSE.
// SHUTDOWN.

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

// Prelaunch Configuration
FUNCTION PreLaunch {
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
    GLOBAL myCountdownTime TO 10.       // Countdown timer
    GLOBAL myPitchAngle TO 88.         // Pitch angle for gravity turn
    GLOBAL myAzimuth TO 90.            // Azimuth (90 = due east)
    GLOBAL myRoll TO 0.                // Roll
    GLOBAL target_Ap TO 150000.        // Target Apoapsis
    GLOBAL target_Pe TO 85000.         // Target Periapsis
    GLOBAL myLiftOff TO 3.             // Stages until liftoff
    GLOBAL orbitMode TO 2.             // Orbit mode: 0=Coast, 1=Throttle, 2=Continuous
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

// Launch Preparation
FUNCTION prepareLaunch {
    CLEARSCREEN.
    PRINT "Launch Preparation Script" AT (0, 0).
    LOCAL baseParts IS SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall").
    IF baseParts:LENGTH > 0 {
        SET basePart TO baseParts[0].
        LOCAL genCount IS 0.
        FOR moduleName IN basePart:ALLMODULES {
            IF moduleName = "ModuleGenerator" {
                SET genCount TO genCount + 1.
                SET genModule TO basePart:GETMODULE(moduleName).
                IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
                    genModule:DOACTION("activate generator", TRUE).
                    PRINT "Activated generator " + genCount + " on " + basePart:NAME AT (0, 1 + genCount).
                } ELSE IF genModule:ALLEVENTNAMES:CONTAINS("activate generator") {
                    genModule:DOEVENT("activate generator").
                    PRINT "Activated generator " + genCount + " (event) on " + basePart:NAME AT (0, 1 + genCount).
                } ELSE {
                    PRINT "Generator " + genCount + " already active on " + basePart:NAME AT (0, 1 + genCount).
                }
            }
        }
        SET capsuleDrainPart TO SHIP:PARTSTAGGED("CapsuleDrain")[0].
        SET lvDrainPart TO SHIP:PARTSTAGGED("LVDrain")[0].
        SET fuelMod TO 0.
        SET drainCapsule TO 0.
        SET drainLV TO 0.
        FOR mod IN basePart:MODULES {
            IF mod = "ModuleResourceConverter" {
                SET fuelMod TO basePart:GETMODULE(mod).
                PRINT "Assigned FuelingSystem on base" AT (0, 5).
            }
        }
        FOR mod IN capsuleDrainPart:MODULES {
            IF mod = "ModuleResourceDrain" {
                SET drainCapsule TO capsuleDrainPart:GETMODULE(mod).
                PRINT "Assigned DrainCapsule (Mono)" AT (0, 6).
            }
        }
        IF SHIP:PARTSTAGGED("LVDrain"):LENGTH > 0 {
            FOR mod IN lvDrainPart:MODULES {
                IF mod = "ModuleResourceDrain" {
                    SET drainLV TO lvDrainPart:GETMODULE(mod).
                    PRINT "Assigned DrainLV (LF/OX)" AT (0, 7).
                }
            }
        }
        IF fuelMod = 0 OR drainCapsule = 0 {
            PRINT "Error: Missing FuelingSystem or DrainCapsule" AT (0, 8).
            WAIT 5.
            REBOOT.
        }
        SET lfCap TO 0. SET oxCap TO 0. SET monoCap TO 0.
        FOR res IN SHIP:RESOURCES {
            IF res:NAME = "LiquidFuel" { SET lfCap TO res:CAPACITY. }
            IF res:NAME = "Oxidizer" { SET oxCap TO res:CAPACITY. }
            IF res:NAME = "MonoPropellant" { SET monoCap TO res:CAPACITY. }
        }
        PRINT "Capacities - LF: " + ROUND(lfCap) + " OX: " + ROUND(oxCap) + " Mono: " + ROUND(monoCap) AT (0, 9).
        PRINT "Press 'S' to start fueling, 0 to toggle, 9 to abort" AT (0, 10).
        PRINT "Initial LF: " + ROUND(SHIP:LIQUIDFUEL,2) + " OX: " + ROUND(SHIP:OXIDIZER,2) + " Mono: " + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 11).
        WAIT UNTIL TERMINAL:INPUT:HASCHAR.
        LOCAL startKey IS TERMINAL:INPUT:GETCHAR().
        IF startKey = "S" OR startKey = "s" {
            fuelMod:DOACTION("Start Fueling", TRUE).
            PRINT "FuelingSystem started" AT (0, 12).
        } ELSE {
            PRINT "Fueling not started. Aborting..." AT (0, 12).
            WAIT 5.
            REBOOT.
        }
        UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
            SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / lfCap) * 100).
            SET oxPercent TO ROUND((SHIP:OXIDIZER / oxCap) * 100).
            SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / monoCap) * 100).
            PRINT "Fueling: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 13).
            PRINT "Percentages - LF: " + lfPercent + "%  OX: " + oxPercent + "%  Mono: " + monoPercent + "%" AT (0, 14).
            IF TERMINAL:INPUT:HASCHAR {
                SET key TO TERMINAL:INPUT:GETCHAR().
                IF key = "0" {
                    fuelMod:DOACTION("Toggle Fueling", TRUE).
                    PRINT "Fueling toggled (on/off)" AT (0, 15).
                }
                IF key = "9" {
                    fuelMod:DOACTION("Stop Fueling", TRUE).
                    PRINT "Fueling aborted" AT (0, 15).
                    BREAK.
                }
            }
            WAIT 0.5.
        }
        fuelMod:DOACTION("Stop Fueling", TRUE).
        PRINT "Fueling complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL,2) + " OX: " + ROUND(SHIP:OXIDIZER,2) + " Mono: " + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 16).
        PRINT "Enter 'D' to detank, 'P' to proceed to launch" AT (0, 17).
        LOCAL choice IS TERMINAL:INPUT:GETCHAR().
        IF choice = "D" OR choice = "d" {
            PRINT "Starting detanking..." AT (0, 18).
            drainCapsule:DOACTION("drain", TRUE).
            IF drainLV <> 0 { drainLV:DOACTION("drain", TRUE). }
            PRINT "Detanking started" AT (0, 19).
            UNTIL SHIP:LIQUIDFUEL <= 0 AND SHIP:OXIDIZER <= 0 AND SHIP:MONOPROPELLANT <= 0 {
                PRINT "Detanking: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 20).
                IF TERMINAL:INPUT:HASCHAR {
                    SET key TO TERMINAL:INPUT:GETCHAR().
                    IF key = "0" {
                        drainCapsule:DOACTION("toggle draining", TRUE).
                        IF drainLV <> 0 { drainLV:DOACTION("toggle draining", TRUE). }
                        PRINT "Detanking toggled (on/off)" AT (0, 21).
                    }
                    IF key = "9" {
                        drainCapsule:DOACTION("stop draining", TRUE).
                        IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
                        PRINT "Detanking aborted" AT (0, 21).
                        BREAK.
                    }
                }
                WAIT 0.5.
            }
            drainCapsule:DOACTION("stop draining", TRUE).
            IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
            PRINT "Detanking complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 22).
            PRINT "Press 'P' to proceed after detanking" AT (0, 23).
            WAIT UNTIL TERMINAL:INPUT:GETCHAR() = "P" OR TERMINAL:INPUT:GETCHAR() = "p".
        }
        LOCAL walkwayParts IS SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewWalkwayMercury").
        IF walkwayParts:LENGTH > 0 {
            SET walkwayPart TO walkwayParts[0].
            SET walkwayModule TO walkwayPart:GETMODULE("ModuleAnimateGenericExtra").
            IF walkwayModule:ALLEVENTNAMES:CONTAINS("raise walkway") {
                walkwayModule:DOEVENT("raise walkway").
                PRINT "Raised walkway on " + walkwayPart:NAME AT (0, 24).
            } ELSE IF walkwayModule:ALLACTIONNAMES:CONTAINS("toggle walkway") {
                walkwayModule:DOACTION("toggle walkway", TRUE).
                PRINT "Toggled walkway on " + walkwayPart:NAME AT (0, 24).
            } ELSE {
                PRINT "Couldn’t raise walkway—check module state" AT (0, 24).
            }
        } ELSE {
            PRINT "Error: No walkway found" AT (0, 24).
        }
        PRINT "Raise walkway complete. Press 'P' to proceed or 'A' to abort" AT (0, 25).
        LOCAL finalChoice IS TERMINAL:INPUT:GETCHAR().
        IF finalChoice = "P" OR finalChoice = "p" {
            PRINT "Walkway raised, proceeding to countdown..." AT (0, 26).
        } ELSE IF finalChoice = "A" OR finalChoice = "a" {
            PRINT "ABORT...ABORT...ABORT!" AT (0, 26).
            WAIT 5.
            REBOOT.
        } ELSE {
            PRINT "Invalid input. Aborting..." AT (0, 26).
            WAIT 5.
            REBOOT.
        }
    } ELSE {
        PRINT "Error: No AM.MLP.FlatLaunchBaseSmall found" AT (0, 1).
        WAIT 5.
        REBOOT.
    }
    PRINT "Launch prep complete. Ready for liftoff!" AT (0, 27).
    WAIT 1.
    CLEARSCREEN.
}