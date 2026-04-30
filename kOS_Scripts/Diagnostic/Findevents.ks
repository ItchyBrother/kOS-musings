prepareLaunch().

// Launch Preparation Function
FUNCTION prepareLaunch {
    CLEARSCREEN.
    PRINT "Launch Preparation Script" AT (0, 0).

    // Get the base part (AM.MLP.TitanIILaunchStand)
    LOCAL baseParts IS SHIP:PARTSNAMED("AM.MLP.TitanIILaunchStand").
    IF baseParts:LENGTH = 0 {
        PRINT "Error: No AM.MLP.TitanIILaunchStand part found" AT (0, 1).
        WAIT 5.
        REBOOT.
    }
    SET basePart TO baseParts[0].
    PRINT "Found base part: " + basePart:NAME AT (0, 1).

    // Activate generators
    LOCAL genCount IS 0.
    LOCAL genModules IS LIST().
    FOR moduleName IN basePart:ALLMODULES {
        IF moduleName = "ModuleGenerator" {
            SET mymod TO basePart:GETMODULE(moduleName).
            genModules:ADD(mymod).
            SET genCount TO genCount + 1.
            IF mymod:HASACTION("activate generator") {
                mymod:DOACTION("activate generator", TRUE).
                PRINT "Activated generator " + genCount + " on " + basePart:NAME AT (0, 2 + genCount).
            } ELSE IF mymod:HASEVENT("activate generator") {
                mymod:DOEVENT("activate generator").
                PRINT "Activated generator " + genCount + " (event) on " + basePart:NAME AT (0, 2 + genCount).
            } ELSE {
                PRINT "Generator " + genCount + " already active or no action/event found" AT (0, 2 + genCount).
            }
        }
    }

    // Find fueling and drain modules
    LOCAL fuelMod IS 0.
    LOCAL drainLV IS 0.
    LOCAL drainLV2 IS 0.
    FOR moduleName IN basePart:ALLMODULES {
        IF moduleName = "ModuleResourceConverter" {
            SET fuelMod TO basePart:GETMODULE(moduleName).
            PRINT "Assigned FuelingSystem on base" AT (0, 5).
            // List actions for debugging
            PRINT "Fueling actions: " + fuelMod:ALLACTIONNAMES:JOIN(", ") AT (0, 6).
        }
    }

    IF SHIP:PARTSTAGGED("2StageDrain"):LENGTH > 0 {
        SET lvDrainPart2 TO SHIP:PARTSTAGGED("2StageDrain")[0].
        FOR moduleName IN lvDrainPart2:ALLMODULES {
            IF moduleName = "ModuleResourceDrain" {
                SET drainLV2 TO lvDrainPart2:GETMODULE(moduleName).
                PRINT "Assigned DrainCapsule (Mono) on drainLV2" AT (0, 7).
                PRINT "DrainLV2 actions: " + drainLV2:ALLACTIONNAMES:JOIN(", ") AT (0, 8).
            }
        }
    }

    IF SHIP:PARTSTAGGED("LVDrain"):LENGTH > 0 {
        SET lvDrainPart TO SHIP:PARTSTAGGED("LVDrain")[0].
        FOR moduleName IN lvDrainPart:ALLMODULES {
            IF moduleName = "ModuleResourceDrain" {
                SET drainLV TO lvDrainPart:GETMODULE(moduleName).
                PRINT "Assigned DrainLV (LF/OX) on drainLV" AT (0, 9).
                PRINT "DrainLV actions: " + drainLV:ALLACTIONNAMES:JOIN(", ") AT (0, 10).
            }
        }
    }

    IF fuelMod = 0 OR drainLV2 = 0 OR drainLV {
        PRINT "Error: Missing FuelingSystem or DrainCapsule" AT (0, 11).
        PRINT "fuelMod = " + fuelMod AT (0, 12).
        PRINT "drainLV = " + drainLV AT (0, 13).
        PRINT "drainLV2 = " + drainLV2 AT (0, 14).
        WAIT 120.
        REBOOT.
    }

    // Get resource capacities
    LOCAL lfCap IS 0. LOCAL oxCap IS 0. LOCAL monoCap IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "LiquidFuel" { SET lfCap TO res:CAPACITY. }
        IF res:NAME = "Oxidizer" { SET oxCap TO res:CAPACITY. }
        IF res:NAME = "MonoPropellant" { SET monoCap TO res:CAPACITY. }
    }
    PRINT "Capacities - LF: " + ROUND(lfCap) + " OX: " + ROUND(oxCap) + " Mono: " + ROUND(monoCap) AT (0, 14).

    // Fueling control
    PRINT "Press 'S' to start fueling, '0' to toggle, '9' to abort" AT (0, 15).
    PRINT "Initial LF: " + ROUND(SHIP:LIQUIDFUEL, 2) + " OX: " + ROUND(SHIP:OXIDIZER, 2) + " Mono: " + ROUND(SHIP:MONOPROPELLANT, 2) AT (0, 16).
    WAIT UNTIL TERMINAL:INPUT:HASCHAR.
    LOCAL startKey IS TERMINAL:INPUT:GETCHAR().
    IF startKey = "S" OR startKey = "s" {
        IF fuelMod:HASACTION("Start Fueling") {
            fuelMod:DOACTION("Start Fueling", TRUE).
            PRINT "FuelingSystem started" AT (0, 17).
        } ELSE {
            PRINT "Error: 'Start Fueling' action not available" AT (0, 17).
            WAIT 5.
            REBOOT.
        }
    } ELSE {
        PRINT "Fueling not started. Aborting..." AT (0, 17).
        WAIT 5.
        REBOOT.
    }

    UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
        SET lfPercent TO ROUND((SHIP:LIQUIDFUEL / lfCap) * 100).
        SET oxPercent TO ROUND((SHIP:OXIDIZER / oxCap) * 100).
        SET monoPercent TO ROUND((SHIP:MONOPROPELLANT / monoCap) * 100).
        PRINT "Fueling: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 18).
        PRINT "Percentages - LF: " + lfPercent + "%  OX: " + oxPercent + "%  Mono: " + monoPercent + "%" AT (0, 19).
        IF TERMINAL:INPUT:HASCHAR {
            SET key TO TERMINAL:INPUT:GETCHAR().
            IF key = "0" AND fuelMod:HASACTION("Toggle Fueling") {
                fuelMod:DOACTION("Toggle Fueling", TRUE).
                PRINT "Fueling toggled (on/off)" AT (0, 20).
            }
            IF key = "9" AND fuelMod:HASACTION("Stop Fueling") {
                fuelMod:DOACTION("Stop Fueling", TRUE).
                PRINT "Fueling aborted" AT (0, 20).
                BREAK.
            }
        }
        WAIT 0.5.
    }
    IF fuelMod:HASACTION("Stop Fueling") {
        fuelMod:DOACTION("Stop Fueling", TRUE).
    }
    PRINT "Fueling complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL, 2) + " OX: " + ROUND(SHIP:OXIDIZER, 2) + " Mono: " + ROUND(SHIP:MONOPROPELLANT, 2) AT (0, 21).

    // Detanking control
    PRINT "Enter 'D' to detank, 'P' to proceed to tower control" AT (0, 22).
    LOCAL choice IS TERMINAL:INPUT:GETCHAR().
    IF choice = "D" OR choice = "d" {
        PRINT "Starting detanking..." AT (0, 23).
        IF drainLV2:HASACTION("Start Drain") {
            drainLV2:DOACTION("Start Drain", TRUE).
            PRINT "Detanking started (drainLV2)" AT (0, 24).
        }
        IF drainLV <> 0 AND drainLV:HASACTION("Start Drain") {
            drainLV:DOACTION("Start Drain", TRUE).
            PRINT "Detanking started (drainLV)" AT (0, 25).
        }
        UNTIL SHIP:LIQUIDFUEL <= 0 AND SHIP:OXIDIZER <= 0 AND SHIP:MONOPROPELLANT <= 0 {
            PRINT "Detanking: LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 26).
            IF TERMINAL:INPUT:HASCHAR {
                SET key TO TERMINAL:INPUT:GETCHAR().
                IF key = "0" AND drainLV2:HASACTION("Toggle Drain") {
                    drainLV2:DOACTION("Toggle Drain", TRUE).
                    IF drainLV <> 0 AND drainLV:HASACTION("Toggle Drain") {
                        drainLV:DOACTION("Toggle Drain", TRUE).
                    }
                    PRINT "Detanking toggled (on/off)" AT (0, 27).
                }
                IF key = "9" AND drainLV2:HASACTION("Stop Drain") {
                    drainLV2:DOACTION("Stop Drain", TRUE).
                    IF drainLV <> 0 AND drainLV:HASACTION("Stop Drain") {
                        drainLV:DOACTION("Stop Drain", TRUE).
                    }
                    PRINT "Detanking aborted" AT (0, 27).
                    BREAK.
                }
            }
            WAIT 0.5.
        }
        IF drainLV2:HASACTION("Stop Drain") {
            drainLV2:DOACTION("Stop Drain", TRUE).
        }
        IF drainLV <> 0 AND drainLV:HASACTION("Stop Drain") {
            drainLV:DOACTION("Stop Drain", TRUE).
        }
        PRINT "Detanking complete. Final LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT) AT (0, 28).
        PRINT "Press 'P' to proceed to tower control" AT (0, 29).
        WAIT UNTIL TERMINAL:INPUT:GETCHAR() = "P" OR TERMINAL:INPUT:GETCHAR() = "p".
    }

    // Crew tower control
    LOCAL walkwayParts IS SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewElevatorGemini").
    IF walkwayParts:LENGTH > 0 {
        SET walkwayPart TO walkwayParts[0].
        LOCAL towerModule IS 0.
        LOCAL moduleIndex IS 0.
        FOR moduleName IN walkwayPart:ALLMODULES {
            IF moduleName = "ModuleAnimateGenericExtra" {
                SET mymod TO walkwayPart:GETMODULE(moduleName).
                IF mymod:ALLFIELDS:CONTAINS("animationName") AND mymod:GETFIELD("animationName") = "GeminiElevRetract" {
                    SET towerModule TO mymod.
                    PRINT "Found tower module: ModuleAnimateGenericExtra[" + moduleIndex + "] (GeminiElevRetract)" AT (0, 30).
                    PRINT "Tower events: " + mymod:ALLEVENTNAMES:JOIN(", ") AT (0, 31).
                    BREAK.
                }
            }
            SET moduleIndex TO moduleIndex + 1.
        }
        IF towerModule = 0 {
            PRINT "Error: Could not find ModuleAnimateGenericExtra with animationName = GeminiElevRetract" AT (0, 30).
            PRINT "Try right-clicking the tower in-game to initialize events" AT (0, 31).
            WAIT 5.
            REBOOT.
        }
        PRINT "Press 'R' to raise tower, 'L' to lower tower, 'P' to proceed, 'A' to abort" AT (0, 32).
        LOCAL towerChoice IS TERMINAL:INPUT:GETCHAR().
        IF towerChoice = "R" OR towerChoice = "r" {
            IF towerModule:HASEVENT("Raise Tower") {
                towerModule:DOEVENT("Raise Tower").
                PRINT "Raised tower on " + walkwayPart:NAME AT (0, 33).
            } ELSE {
                PRINT "Error: 'Raise Tower' event not available" AT (0, 33).
            }
        } ELSE IF towerChoice = "L" OR towerChoice = "l" {
            IF towerModule:HASEVENT("Lower Tower") {
                towerModule:DOEVENT("Lower Tower").
                PRINT "Lowered tower on " + walkwayPart:NAME AT (0, 33).
            } ELSE {
                PRINT "Error: 'Lower Tower' event not available" AT (0, 33).
            }
        } ELSE IF towerChoice = "P" OR towerChoice = "p" {
            PRINT "Skipping tower control, proceeding..." AT (0, 33).
        } ELSE IF towerChoice = "A" OR towerChoice = "a" {
            PRINT "ABORT...ABORT...ABORT!" AT (0, 33).
            WAIT 5.
            REBOOT.
        } ELSE {
            PRINT "Invalid input. Aborting..." AT (0, 33).
            WAIT 5.
            REBOOT.
        }
    } ELSE {
        PRINT "Error: No AM.MLP.LaunchStandCrewElevatorGemini found" AT (0, 30).
        WAIT 5.
        REBOOT.
    }

    PRINT "Launch prep complete. Ready for liftoff!" AT (0, 34).
    WAIT 1.
    CLEARSCREEN.
}