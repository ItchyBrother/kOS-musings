// Diagnostic script to output modules, actions, and events for AM.MLP.FlatLaunchBaseSmall and related parts
CLEARSCREEN.
PRINT "Diagnosing modules for AM.MLP.FlatLaunchBaseSmall and related parts...".

// Open a file to save output
LOCAL outputFile IS "0:/flatbase_diagnostic.txt".
IF EXISTS(outputFile) { DELETEPATH(outputFile). }
LOG "Diagnosing modules for AM.MLP.FlatLaunchBaseSmall and related parts..." TO outputFile.

// Function to get resource levels
FUNCTION getResourceLevels {
    LOCAL ec IS 0. LOCAL lf IS 0. LOCAL ox IS 0. LOCAL mono IS 0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "ElectricCharge" { SET ec TO res:AMOUNT. }
        IF res:NAME = "LiquidFuel" { SET lf TO res:AMOUNT. }
        IF res:NAME = "Oxidizer" { SET ox TO res:AMOUNT. }
        IF res:NAME = "MonoPropellant" { SET mono TO res:AMOUNT. }
    }
    RETURN LIST(ec, lf, ox, mono).
}

// Function to test and log module actions/events
FUNCTION testModule {
    PARAMETER part, partName, moduleName, moduleIndex, yOffset.
    PRINT "Testing " + partName + " Module [" + moduleIndex + "]: " + moduleName AT (0, yOffset).
    LOG "Testing " + partName + " Module [" + moduleIndex + "]: " + moduleName TO outputFile.
    IF part:HASMODULE(moduleName) {
        SET mymod TO part:GETMODULE(moduleName).
        LOCAL actions IS mymod:ALLACTIONNAMES.
        LOCAL events IS mymod:ALLEVENTNAMES.
        LOCAL actionString IS "None".
        LOCAL eventString IS "None".
        IF actions:LENGTH > 0 {
            SET actionString TO actions:JOIN(", ").
        }
        IF events:LENGTH > 0 {
            SET eventString TO events:JOIN(", ").
        }
        PRINT "Available actions: " + actionString AT (0, yOffset + 1).
        PRINT "Available events: " + eventString AT (0, yOffset + 2).
        LOG "Available actions: " + actionString TO outputFile.
        LOG "Available events: " + eventString TO outputFile.
        LOCAL startResources IS getResourceLevels().
        PRINT "Resources - EC: " + ROUND(startResources[0], 2) + " LF: " + ROUND(startResources[1], 2) + " OX: " + ROUND(startResources[2], 2) + " Mono: " + ROUND(startResources[3], 2) AT (0, yOffset + 3).
        LOG "Resources - EC: " + ROUND(startResources[0], 2) + " LF: " + ROUND(startResources[1], 2) + " OX: " + ROUND(startResources[2], 2) + " Mono: " + ROUND(startResources[3], 2) TO outputFile.
        PRINT "Enter action/event number (0-" + (actions:LENGTH + events:LENGTH - 1) + "), 'N' for next, 'Q' to quit" AT (0, yOffset + 4).
        IF actions:LENGTH > 0 {
            FOR i IN RANGE(0, actions:LENGTH) {
                PRINT "[" + i + "] Action: " + actions[i] AT (0, yOffset + 5 + i).
            }
        }
        IF events:LENGTH > 0 {
            FOR i IN RANGE(0, events:LENGTH) {
                PRINT "[" + (actions:LENGTH + i) + "] Event: " + events[i] AT (0, yOffset + 5 + actions:LENGTH + i).
            }
        }
        UNTIL FALSE {
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL input IS TERMINAL:INPUT:GETCHAR().
                IF input = "N" OR input = "n" {
                    PRINT "Moving to next module..." AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                    LOG "Moving to next module..." TO outputFile.
                    BREAK.
                } ELSE IF input = "Q" OR input = "q" {
                    PRINT "Quitting test..." AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                    LOG "Quitting test..." TO outputFile.
                    RETURN FALSE.
                } ELSE IF input:TONUMBER(-1) >= 0 AND input:TONUMBER(-1) < actions:LENGTH + events:LENGTH {
                    LOCAL index IS input:TONUMBER().
                    LOCAL newResources IS getResourceLevels().
                    IF index < actions:LENGTH {
                        mymod:DOACTION(actions[index], TRUE).
                        PRINT "Triggered action: " + actions[index] AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                        LOG "Triggered action: " + actions[index] TO outputFile.
                    } ELSE {
                        mymod:DOEVENT(events[index - actions:LENGTH]).
                        PRINT "Triggered event: " + events[index - actions:LENGTH] AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                        LOG "Triggered event: " + events[index - actions:LENGTH] TO outputFile.
                    }
                    WAIT 1. // Allow time for resource changes
                    SET newResources TO getResourceLevels().
                    PRINT "Resource change - EC: " + ROUND(newResources[0] - startResources[0], 2) + " LF: " + ROUND(newResources[1] - startResources[1], 2) + " OX: " + ROUND(newResources[2] - startResources[2], 2) + " Mono: " + ROUND(newResources[3] - startResources[3], 2) AT (0, yOffset + 6 + actions:LENGTH + events:LENGTH).
                    LOG "Resource change - EC: " + ROUND(newResources[0] - startResources[0], 2) + " LF: " + ROUND(newResources[1] - startResources[1], 2) + " OX: " + ROUND(newResources[2] - startResources[2], 2) + " Mono: " + ROUND(newResources[3] - startResources[3], 2) TO outputFile.
                    SET startResources TO newResources.
                    WAIT 0.5.
                    PRINT " " AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                    PRINT " " AT (0, yOffset + 6 + actions:LENGTH + events:LENGTH).
                } ELSE {
                    PRINT "Invalid input, try again" AT (0, yOffset + 5 + actions:LENGTH + events:LENGTH).
                }
                WAIT 0.1.
            }
        }
        RETURN TRUE.
    } ELSE {
        PRINT "Module " + moduleName + " not accessible" AT (0, yOffset + 1).
        LOG "Module " + moduleName + " not accessible" TO outputFile.
        PRINT "Press 'N' for next, 'Q' to quit" AT (0, yOffset + 2).
        UNTIL FALSE {
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL input IS TERMINAL:INPUT:GETCHAR().
                IF input = "N" OR input = "n" {
                    BREAK.
                } ELSE IF input = "Q" OR input = "q" {
                    RETURN FALSE.
                }
                WAIT 0.1.
            }
        }
        RETURN TRUE.
    }
}

// Test modules on AM.MLP.FlatLaunchBaseSmall
IF SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall"):LENGTH > 0 {
    SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
    CLEARSCREEN.
    PRINT "Testing modules on AM.MLP.FlatLaunchBaseSmall..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN basePart:ALLMODULES {
        IF continueTesting {
            SET continueTesting TO testModule(basePart, "AM.MLP.FlatLaunchBaseSmall", moduleName, moduleIndex, 1).
            SET moduleIndex TO moduleIndex + 1.
            CLEARSCREEN.
        }
    }
    IF moduleIndex = 0 {
        PRINT "No modules found on AM.MLP.FlatLaunchBaseSmall" AT (0, 1).
        LOG "No modules found on AM.MLP.FlatLaunchBaseSmall" TO outputFile.
    }
} ELSE {
    PRINT "Error: No AM.MLP.FlatLaunchBaseSmall part found." AT (0, 1).
    LOG "Error: No AM.MLP.FlatLaunchBaseSmall part found." TO outputFile.
}

// Test ModuleResourceDrain on CapsuleDrain
IF SHIP:PARTSTAGGED("CapsuleDrain"):LENGTH > 0 {
    SET drainPart TO SHIP:PARTSTAGGED("CapsuleDrain")[0].
    CLEARSCREEN.
    PRINT "Testing ModuleResourceDrain on CapsuleDrain..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN drainPart:ALLMODULES {
        IF moduleName = "ModuleResourceDrain" AND continueTesting {
            SET continueTesting TO testModule(drainPart, "CapsuleDrain", moduleName, moduleIndex, 1).
            SET moduleIndex TO moduleIndex + 1.
            CLEARSCREEN.
        }
    }
    IF moduleIndex = 0 {
        PRINT "No ModuleResourceDrain found on CapsuleDrain" AT (0, 1).
        LOG "No ModuleResourceDrain found on CapsuleDrain" TO outputFile.
    }
} ELSE {
    PRINT "Error: No CapsuleDrain part found." AT (0, 1).
    LOG "Error: No CapsuleDrain part found." TO outputFile.
}

// Test ModuleResourceDrain on LVDrain
IF SHIP:PARTSTAGGED("LVDrain"):LENGTH > 0 {
    SET drainPart TO SHIP:PARTSTAGGED("LVDrain")[0].
    CLEARSCREEN.
    PRINT "Testing ModuleResourceDrain on LVDrain..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN drainPart:ALLMODULES {
        IF moduleName = "ModuleResourceDrain" AND continueTesting {
            SET continueTesting TO testModule(drainPart, "LVDrain", moduleName, moduleIndex, 1).
            SET moduleIndex TO moduleIndex + 1.
            CLEARSCREEN.
        }
    }
    IF moduleIndex = 0 {
        PRINT "No ModuleResourceDrain found on LVDrain" AT (0, 1).
        LOG "No ModuleResourceDrain found on LVDrain" TO outputFile.
    }
} ELSE {
    PRINT "Error: No LVDrain part found." AT (0, 1).
    LOG "Error: No LVDrain part found." TO outputFile.
}

// Test ModuleAnimateGenericExtra on AM.MLP.LaunchStandCrewWalkwayMercury
IF SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewWalkwayMercury"):LENGTH > 0 {
    SET walkwayPart TO SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewWalkwayMercury")[0].
    CLEARSCREEN.
    PRINT "Testing ModuleAnimateGenericExtra on AM.MLP.LaunchStandCrewWalkwayMercury..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN walkwayPart:ALLMODULES {
        IF moduleName = "ModuleAnimateGenericExtra" AND continueTesting {
            SET continueTesting TO testModule(walkwayPart, "AM.MLP.LaunchStandCrewWalkwayMercury", moduleName, moduleIndex, 1).
            SET moduleIndex TO moduleIndex + 1.
            CLEARSCREEN.
        }
    }
    IF moduleIndex = 0 {
        PRINT "No ModuleAnimateGenericExtra found on AM.MLP.LaunchStandCrewWalkwayMercury" AT (0, 1).
        LOG "No ModuleAnimateGenericExtra found on AM.MLP.LaunchStandCrewWalkwayMercury" TO outputFile.
    }
} ELSE {
    PRINT "Error: No AM.MLP.LaunchStandCrewWalkwayMercury part found." AT (0, 1).
    LOG "Error: No AM.MLP.LaunchStandCrewWalkwayMercury part found." TO outputFile.
}

PRINT "Diagnostic complete. Output saved to 0:/flatbase_diagnostic.txt." AT (0, 0).
LOG "Diagnostic complete." TO outputFile.
WAIT UNTIL FALSE.