// KOS Script for Rocket Launch Orbital Flight (Atlas Centaur)
// Version 1.0 - Updated for orbitMode parameter and integrated circularization logic

RUNONCEPATH("0:/lib/utils.ks").

// Mode 0 - Prelaunch
CLEARSCREEN.
GLOBAL MODE IS 0.
SET holdTime TO 0.

//PROCESSOR("CommSat"):ACTIVATE().
// Recieving message from the Satellite computer that it is working //
//     WAIT UNTIL NOT CORE:MESSAGES:EMPTY.
//     SET received TO CORE:MESSAGES:POP.
//     PRINT "Message " + received:RECEIVEDAT + ": " + received:CONTENT.
////////////////////////////////////////////////////////////////////////     

//PROCESSOR("CommSat"):DEACTIVATE().
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

// Mode 2 - Ascent including Max Q
SET MODE TO 2.
PRINT "Mode 2 - Ascent and Gravity turn".
// Pitch briefly to avoid launch complex

LOCK STEERING TO HEADING(90, 87). // 3 degrees east from vertical
PRINT "Launch Pad Avoidance Maneuver.".
WAIT 2.
LOCK STEERING TO HEADING(90, 90).
WAIT 0.1.  //Allow physic tick.

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
SET sustainerEngine TO 0.

FOR eng IN allEngines {
    IF eng:NAME = "liquidEngine.v2" {  // These are the modified LT-V30 engines.
        boosterEngines:ADD(eng).
    }
    IF eng:NAME = "liquidEngine2.v2" { 
        SET sustainerEngine to eng.
    }
}

// Capture initial fuel for booster phase
SET initialFuel TO SHIP:LIQUIDFUEL.
SET throttleDownStarted TO FALSE.

UNTIL FALSE {
    // Calculate fuel percentage remaining
    SET currentFuel TO SHIP:LIQUIDFUEL.
    SET fuelPercent TO (currentFuel / initialFuel) * 100.
    
    // Phase 2 pitch control: 45° ➝ 5° between 30–45 km
    IF SHIP:ALTITUDE >= 30000 {
        SET pitchAngle TO 45 - ((SHIP:ALTITUDE - 30000) * (40 / 15000)). // 45 to 5
        IF pitchAngle < 5 { SET pitchAngle TO 5. }
        LOCK STEERING TO HEADING(myAzimuth, pitchAngle).
        PRINT "Pitch: " + ROUND(pitchAngle, 1) + "°" AT (0, 20).
    }

    // Booster throttle-down: triggered at 25% fuel remaining
    IF fuelPercent <= 40 AND NOT throttleDownStarted {
        SET throttleDownStarted TO TRUE.
        SET throttleDownTime TO TIME:SECONDS.
        PRINT "Booster throttle-down initiated at " + ROUND(fuelPercent, 1) + "% fuel".
    }
    
    IF throttleDownStarted {
        SET elapsedTime TO TIME:SECONDS - throttleDownTime.
        // Throttle from 100% to 0% over 5 seconds
        SET scaleFactor TO MAX(0, 1 - (elapsedTime / 5)).
        SET scalePercent TO scaleFactor * 100.
        FOR b IN boosterEngines {
            SET b:THRUSTLIMIT TO scalePercent.
        }
        PRINT "Throttling boosters to " + ROUND(scalePercent, 1) + "%" AT (0, 21).
    }
    
    PRINT "Booster fuel remaining: " + ROUND(fuelPercent, 1) + "%" AT (0, 22).
    
    // Separate boosters 3 seconds after throttle down started
    IF throttleDownStarted AND (TIME:SECONDS - throttleDownTime) >= 3 {
        BREAK.
    }

    WAIT 0.1.
}

//Booster shutdown and jettison
AG10 ON. // Booster shutdown
WAIT 0.1.
PRINT "Booster shutdown".
UNTIL STAGE:NUMBER < 6 {
    Staging(2).
}
PRINT "Booster Jettison".

WAIT UNTIL sustainerEngine:FLAMEOUT.
LOCK THROTTLE TO 0.
    UNTIL STAGE:NUMBER < 5 {
    Staging(0.2).

    //AG9 ON.  //STAGE Second Stage and activate engines.
    }
RCS ON.
WAIT 3.
LOCK THROTTLE TO 1.

// Mode 4 - Orbit Circularization and MECO
SET MODE TO 4.
PRINT "Mode 4 - MECO phase.".

SWITCH TO 0.
// If set higher than 300 km temp setting target Ap to 1/3 height and Pe to 100 km.
IF target_Ap > 300000  {
    SET temp_Ap TO target_Ap - (target_Ap * .33).
    SET temp_Pe TO 100000.
} ELSE {
    SET temp_Ap TO target_Ap.
    SET temp_Pe TO target_Pe.
}

IF SHIP:ALTITUDE > 50000{ 
    UNTIL STAGE:NUMBER < 4 {
        Staging(0.1).
    }  
}
PRINT "Payload faring jettison!" AT (0, 16).

run once circ (temp_Ap, temp_Pe, orbitMode).
 
// Lock steering to prograde for the maneuver
LOCK STEERING TO PROGRADE.

// Shut down Centaur engines (assuming AG9 toggles it off)
ToggleEngine(9, TRUE).   //Called from util.ks
CLEARSCREEN.
PRINT "*************************************" AT (0,9).
//PRINT "Cleaning up orbit." AT (0,10).
PRINT "Ap:       " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0,11).
PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0,12).
PRINT "Shutting Centaur Stage engines." AT (0,14).

WAIT 5.

PRINT ">>>>> ASCENT PROGRAM ENDED <<<<<" AT (0, 20).
// Final clean up.
//SHUTDOWN.

// Staging Function
FUNCTION Staging {
    PARAMETER holdTime.
    WAIT holdTime.
    WAIT UNTIL STAGE:READY. 
    STAGE.
    WAIT 0.1.
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
        } ELSE IF choice = "9" {
            IF bypassmenu = "FALSE" {
                SET bypassmenu TO "TRUE".
            } ELSE {
                SET bypassmenu TO "FALSE".
            }
            PRINT "By Pass Menu to: "   + bypassmenu.
        } ELSE IF choice = "A" OR choice = "a" {
            SET target_Ap TO 2863334.
            SET target_Pe TO 2863334.
            SET targetInc TO 0.
            PRINT "Geostationary orbit set.".
            WAIT 1.
        } ELSE IF choice = "B" OR choice = "b" {
            SET target_Ap TO 2863334.
            SET target_Pe TO 2863334 / 4.  // 1/4 height Pe
            SET targetInc TO 0.
            PRINT "Semi-Geostationary orbit set.".
            WAIT 1.    
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
    GLOBAL target_Ap TO 200000.        // Target Apoapsis
    GLOBAL target_Pe TO 190000.         // Target Periapsis
    GLOBAL myLiftOff TO 3.             // Stages until liftoff
    GLOBAL orbitMode TO 2.             // Orbit mode: 0=Coast, 1=Throttle, 2=Continuous
    GLOBAL bypassmenu TO TRUE.         // Set to FALSE to use menu/TRUE to bypass.
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
    PRINT "9. By Pass Satellite orbit menu: " + bypassmenu.
    PRINT "A. Set to GeoStationary.".
    PRINT "B. Set to Semi-GeoStationary.".
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
        SET lvDrainPart TO SHIP:PARTSTAGGED("LVDrain")[0].
        SET fuelMod TO 0.
        SET drainCapsule TO 0.
        SET drainLV TO 0.
        FOR mod IN basePart:MODULES {
            IF mod = "ModuleResourceConverter" {
                SET fuelMod TO basePart:GETMODULE(mod).
                PRINT "Assigned Fueling System on base" AT (0, 5).
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
        IF fuelMod = 0 { //OR drainCapsule = 0 {
            PRINT "Error: Missing Fueling System or DrainCapsule" AT (0, 8).
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
        PRINT "Press 'S' to start fueling" AT(0, 10). PRINT "'0' to toggle fueling on/off" AT (0, 11). PRINT "'9' to abort" AT (0, 12).
        PRINT "Initial LF: " + ROUND(SHIP:LIQUIDFUEL,2) + " OX: " + ROUND(SHIP:OXIDIZER,2) + " Mono: " + ROUND(SHIP:MONOPROPELLANT,2) AT (0, 14).
        WAIT UNTIL TERMINAL:INPUT:HASCHAR.
        LOCAL startKey IS TERMINAL:INPUT:GETCHAR().
        IF startKey = "S" OR startKey = "s" {
            fuelMod:DOACTION("Start Fueling", TRUE).
            PRINT "Fueling System started" AT (0, 15).
        } ELSE {
            PRINT "Fueling not started. Aborting..." AT (0, 15).
            WAIT 5.
            REBOOT.
        }
        UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
            SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / lfCap) * 100).
            SET oxPercent TO ROUND((SHIP:OXIDIZER / oxCap) * 100).
            
            IF monoCap = 0 {
                SET monoPercent TO "N/A".
            } ELSE {
                SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / monoCap) * 100).
            }
            PRINT "Fueling: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 16).
            PRINT "Percentages - LF: " + lfPercent + "%  OX: " + oxPercent + "%  Mono: " + monoPercent + "%" AT (0, 17).
            IF TERMINAL:INPUT:HASCHAR {
                SET key TO TERMINAL:INPUT:GETCHAR().
                IF key = "0" {
                    fuelMod:DOACTION("Toggle Fueling", TRUE).
                    PRINT "Fueling toggled (on/off)" AT (0, 18).
                }
                IF key = "9" {
                    fuelMod:DOACTION("Stop Fueling", TRUE).
                    PRINT "Fueling aborted" AT (0, 18).
                    BREAK.
                }
            }
            WAIT 0.5.
        }
        fuelMod:DOACTION("Stop Fueling", TRUE).
        PRINT "Fueling complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 19).
        PRINT "Enter 'D' to detank, 'P' to proceed to launch" AT (0, 20).
        LOCAL choice IS TERMINAL:INPUT:GETCHAR().
        IF choice = "D" OR choice = "d" {
            PRINT "Starting detanking..." AT (0, 22).
            //drainCapsule:DOACTION("drain", TRUE).
            IF drainLV <> 0 { drainLV:DOACTION("drain", TRUE). }
            PRINT "Detanking started" AT (0, 23).
            UNTIL SHIP:LIQUIDFUEL <= 0 AND SHIP:OXIDIZER <= 0 AND SHIP:MONOPROPELLANT <= 0 {
                PRINT "Detanking: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 24).
                IF TERMINAL:INPUT:HASCHAR {
                    SET key TO TERMINAL:INPUT:GETCHAR().
                    IF key = "0" {
                        //drainCapsule:DOACTION("toggle draining", TRUE).
                        IF drainLV <> 0 { drainLV:DOACTION("toggle draining", TRUE). }
                        PRINT "Detanking toggled (on/off)" AT (0, 25).
                    }
                    IF key = "9" {
                        //drainCapsule:DOACTION("stop draining", TRUE).
                        IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
                        PRINT "Detanking aborted" AT (0, 25).
                        BREAK.
                    }
                }
                WAIT 0.5.
            }
           // drainCapsule:DOACTION("stop draining", TRUE).
            IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
            PRINT "Detanking complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 25).
            PRINT "Press 'P' to proceed after detanking" AT (0, 26).
            WAIT UNTIL TERMINAL:INPUT:GETCHAR() = "P" OR TERMINAL:INPUT:GETCHAR() = "p".
        }
        PRINT "Press 'P' to proceed, 'A' to abort or any other key to Shutdown." AT (0, 27).
        LOCAL finalChoice IS TERMINAL:INPUT:GETCHAR().
        IF finalChoice = "P" OR finalChoice = "p" {
            PRINT "Proceeding to countdown..." AT (0, 28).
        } ELSE IF finalChoice = "A" OR finalChoice = "a" {
            PRINT "ABORT...ABORT...ABORT!" AT (0, 28).
            WAIT 5.
            REBOOT.
        } ELSE {
            PRINT "Shutting down..." AT (0, 28).
            WAIT 5.
            SHUTDOWN.
        }
    } ELSE {
        PRINT "Error: No AM.MLP.FlatLaunchBaseSmall found" AT (0, 1).
        WAIT 5.
        REBOOT.
    }
    PRINT "Launch prep complete. Ready for liftoff!" AT (0, 29).
    WAIT 5.
    CLEARSCREEN.
}