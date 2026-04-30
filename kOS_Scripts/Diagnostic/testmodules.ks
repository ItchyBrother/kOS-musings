// Interactive diagnostic script to test module actions/events
CLEARSCREEN.
PRINT "Testing modules for launch preparation...".

// Open a file to save output
LOCAL outputFile IS "0:/test_output.txt".
IF EXISTS(outputFile) { DELETEPATH(outputFile). }
LOG "Testing modules for launch preparation..." TO outputFile.

// Function to test ModuleGenerator actions
FUNCTION testGeneratorModule {
    PARAMETER part, partName, moduleIndex, yOffset, moduleRef.
    PRINT "Testing " + partName + " ModuleGenerator [" + moduleIndex + "]" AT (0, yOffset).
    LOG "Testing " + partName + " ModuleGenerator [" + moduleIndex + "]" TO outputFile.
    SET mymod TO moduleRef.
    LOCAL actions IS mymod:ALLACTIONNAMES.
    PRINT "Available actions: " + actions:JOIN(", ") AT (0, yOffset + 1).
    LOG "Available actions: " + actions:JOIN(", ") TO outputFile.
    PRINT "Press 'A' to activate, 'T' to toggle, 'S' to shutdown, 'N' to next module, 'Q' to quit" AT (0, yOffset + 2).
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL key IS TERMINAL:INPUT:GETCHAR().
            IF key = "A" OR key = "a" AND mymod:HASACTION("activate generator") {
                mymod:DOACTION("activate generator", TRUE).
                PRINT "Activated generator" AT (0, yOffset + 3).
                LOG "Activated generator" TO outputFile.
            } ELSE IF key = "T" OR key = "t" AND mymod:HASACTION("toggle generator") {
                mymod:DOACTION("toggle generator", TRUE).
                PRINT "Toggled generator" AT (0, yOffset + 3).
                LOG "Toggled generator" TO outputFile.
            } ELSE IF key = "S" OR key = "s" AND mymod:HASACTION("shutdown generator") {
                mymod:DOACTION("shutdown generator", TRUE).
                PRINT "Shutdown generator" AT (0, yOffset + 3).
                LOG "Shutdown generator" TO outputFile.
            } ELSE IF key = "N" OR key = "n" {
                PRINT "Moving to next module..." AT (0, yOffset + 3).
                LOG "Moving to next module..." TO outputFile.
                BREAK.
            } ELSE IF key = "Q" OR key = "q" {
                PRINT "Quitting test..." AT (0, yOffset + 3).
                LOG "Quitting test..." TO outputFile.
                RETURN FALSE.
            } ELSE {
                PRINT "Invalid input, try again" AT (0, yOffset + 3).
            }
            WAIT 0.5.
            PRINT " " AT (0, yOffset + 3). // Clear last message
        }
        WAIT 0.1.
    }
    RETURN TRUE.
}

// Function to test ModuleAnimateGenericExtra actions/events
FUNCTION testElevatorModule {
    PARAMETER part, partName, moduleIndex, yOffset, moduleRef.
    PRINT "Testing " + partName + " ModuleAnimateGenericExtra [" + moduleIndex + "]" AT (0, yOffset).
    LOG "Testing " + partName + " ModuleAnimateGenericExtra [" + moduleIndex + "]" TO outputFile.
    SET mymod TO moduleRef.
    LOCAL actions IS mymod:ALLACTIONNAMES.
    LOCAL events IS mymod:ALLEVENTNAMES.
    PRINT "Available actions: " + actions:JOIN(", ") AT (0, yOffset + 1).
    PRINT "Available events: " + events:JOIN(", ") AT (0, yOffset + 2).
    LOG "Available actions: " + actions:JOIN(", ") TO outputFile.
    LOG "Available events: " + events:JOIN(", ") TO outputFile.
    PRINT "Press 'T' to toggle elevator car, 'U' for elevator car up, 'N' to next module, 'Q' to quit" AT (0, yOffset + 3).
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL key IS TERMINAL:INPUT:GETCHAR().
            IF key = "T" OR key = "t" AND mymod:HASACTION("toggle elevator car") {
                mymod:DOACTION("toggle elevator car", TRUE).
                PRINT "Toggled elevator car" AT (0, yOffset + 4).
                LOG "Toggled elevator car" TO outputFile.
            } ELSE IF key = "U" OR key = "u" AND mymod:HASEVENT("elevator car up") {
                mymod:DOEVENT("elevator car up").
                PRINT "Triggered elevator car up" AT (0, yOffset + 4).
                LOG "Triggered elevator car up" TO outputFile.
            } ELSE IF key = "N" OR key = "n" {
                PRINT "Moving to next module..." AT (0, yOffset + 4).
                LOG "Moving to next module..." TO outputFile.
                BREAK.
            } ELSE IF key = "Q" OR key = "q" {
                PRINT "Quitting test..." AT (0, yOffset + 4).
                LOG "Quitting test..." TO outputFile.
                RETURN FALSE.
            } ELSE {
                PRINT "Invalid input, try again" AT (0, yOffset + 4).
            }
            WAIT 0.5.
            PRINT " " AT (0, yOffset + 4). // Clear last message
        }
        WAIT 0.1.
    }
    RETURN TRUE.
}

// Test AM.MLP.TitanIILaunchStand generators
IF SHIP:PARTSNAMED("AM.MLP.TitanIILaunchStand"):LENGTH > 0 {
    SET basePart TO SHIP:PARTSNAMED("AM.MLP.TitanIILaunchStand")[0].
    CLEARSCREEN.
    PRINT "Testing generators on AM.MLP.TitanIILaunchStand..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN basePart:ALLMODULES {
        IF moduleName = "ModuleGenerator" AND continueTesting {
            IF basePart:HASMODULE("ModuleGenerator") {
                SET mymod TO basePart:GETMODULE("ModuleGenerator").
                SET continueTesting TO testGeneratorModule(basePart, "AM.MLP.TitanIILaunchStand", moduleIndex, 1, mymod).
                SET moduleIndex TO moduleIndex + 1.
                CLEARSCREEN.
            }
        }
    }
    IF moduleIndex = 0 {
        PRINT "No ModuleGenerator found on AM.MLP.TitanIILaunchStand" AT (0, 1).
        LOG "No ModuleGenerator found on AM.MLP.TitanIILaunchStand" TO outputFile.
    }
} ELSE {
    PRINT "Error: No AM.MLP.TitanIILaunchStand part found." AT (0, 1).
    LOG "Error: No AM.MLP.TitanIILaunchStand part found." TO outputFile.
}

// Test AM.MLP.LaunchStandCrewElevatorGemini elevator modules
IF SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewElevatorGemini"):LENGTH > 0 {
    SET walkwayPart TO SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewElevatorGemini")[0].
    CLEARSCREEN.
    PRINT "Testing elevator modules on AM.MLP.LaunchStandCrewElevatorGemini..." AT (0, 0).
    SET moduleIndex TO 0.
    SET continueTesting TO TRUE.
    FOR moduleName IN walkwayPart:ALLMODULES {
        IF moduleName = "ModuleAnimateGenericExtra" AND continueTesting {
            IF walkwayPart:HASMODULE("ModuleAnimateGenericExtra") {
                SET mymod TO walkwayPart:GETMODULE("ModuleAnimateGenericExtra").
                SET continueTesting TO testElevatorModule(walkwayPart, "AM.MLP.LaunchStandCrewElevatorGemini", moduleIndex, 1, mymod).
                SET moduleIndex TO moduleIndex + 1.
                CLEARSCREEN.
            }
        }
    }
    IF moduleIndex = 0 {
        PRINT "No ModuleAnimateGenericExtra found on AM.MLP.LaunchStandCrewElevatorGemini" AT (0, 1).
        LOG "No ModuleAnimateGenericExtra found on AM.MLP.LaunchStandCrewElevatorGemini" TO outputFile.
    }
} ELSE {
    PRINT "Error: No AM.MLP.LaunchStandCrewElevatorGemini part found." AT (0, 1).
    LOG "Error: No AM.MLP.LaunchStandCrewElevatorGemini part found." TO outputFile.
}

PRINT "Testing complete. Output saved to 0:/test_output.txt." AT (0, 0).
LOG "Testing complete." TO outputFile.
WAIT UNTIL FALSE.