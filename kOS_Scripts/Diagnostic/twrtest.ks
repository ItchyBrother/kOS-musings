// test_tower_raw.ks
CLEARSCREEN.
PRINT "Testing Tower Animation for AM.MLP.LaunchStandCrewElevatorGemini".

// Get the elevator part
LOCAL walkwayPart IS SHIP:PARTSNAMED("AM.MLP.LaunchStandCrewElevatorGemini")[0].
IF NOT walkwayPart:ISTYPE("Part") {
    PRINT "Error: No AM.MLP.LaunchStandCrewElevatorGemini part found".
    WAIT 5.
    REBOOT.
}

// Log all modules
PRINT "All modules on part:".
LOCAL moduleIndex IS 0.
FOR mod IN walkwayPart:MODULES {
    PRINT "  Module " + moduleIndex + ": " + mod.
    SET moduleIndex TO moduleIndex + 1.
}

// Try raw access to MODULES[4]
LOCAL towerModule IS 0.
IF walkwayPart:MODULES:LENGTH > 4 {
    LOCAL modName IS walkwayPart:MODULES[4].
    PRINT "Attempting to access module at index 4: " + modName.
    IF modName = "ModuleAnimateGenericExtra" OR modName = "ModuleAnimateGeneric" {
        SET towerModule TO walkwayPart:GETMODULE(modName).
        PRINT "Selected module at index 4:".
        LOCAL animName IS "".
        IF towerModule:HASFIELD("animationName") {
            SET animName TO towerModule:GETFIELD("animationName").
            PRINT "  animationName: " + animName.
        } ELSE {
            PRINT "  animationName: [Not found]".
        }
        PRINT "  Events: " + towerModule:ALLEVENTNAMES.
        PRINT "  Actions: " + towerModule:ALLACTIONNAMES.
    } ELSE {
        PRINT "Error: Module at index 4 is " + modName + ", not ModuleAnimateGenericExtra".
    }
} ELSE {
    PRINT "Error: Only " + walkwayPart:MODULES:LENGTH + " modules found, need at least 5".
}

IF towerModule = 0 {
    PRINT "Error: Could not access tower module, falling back to elevator test...".
    IF walkwayPart:MODULES:LENGTH > 2 AND walkwayPart:MODULES[2] = "ModuleAnimateGenericExtra" {
        SET towerModule TO walkwayPart:GETMODULE(walkwayPart:MODULES[2]).
        PRINT "Selected elevator module at index 2 (GeminiElevCar):".
        LOCAL animName IS "".
        IF towerModule:HASFIELD("animationName") {
            SET animName TO towerModule:GETFIELD("animationName").
            PRINT "  animationName: " + animName.
        } ELSE {
            PRINT "  animationName: [Not found]".
        }
        PRINT "  Events: " + towerModule:ALLEVENTNAMES.
        PRINT "  Actions: " + towerModule:ALLACTIONNAMES.
    }
}

IF towerModule = 0 {
    PRINT "Error: No suitable module found".
    WAIT 5.
    REBOOT.
}

// Test tower animation
PRINT "Attempting to raise tower...".
IF towerModule:ALLEVENTNAMES:CONTAINS("raise tower") OR towerModule:ALLEVENTNAMES:CONTAINS("Raise Tower") {
    towerModule:DOEVENT("raise tower").
} ELSE IF towerModule:ALLEVENTNAMES:CONTAINS("lower tower") OR towerModule:ALLEVENTNAMES:CONTAINS("Lower Tower") {
    towerModule:DOEVENT("lower tower").
} ELSE {
    PRINT "No tower events found, trying elevator...".
    IF towerModule:ALLEVENTNAMES:CONTAINS("Elevator Car Down") {
        towerModule:DOEVENT("Elevator Car Down").
    }
}
WAIT 5.
PRINT "Attempting to lower tower...".
IF towerModule:ALLEVENTNAMES:CONTAINS("lower tower") OR towerModule:ALLEVENTNAMES:CONTAINS("Lower Tower") {
    towerModule:DOEVENT("lower tower").
} ELSE IF towerModule:ALLEVENTNAMES:CONTAINS("raise tower") OR towerModule:ALLEVENTNAMES:CONTAINS("Raise Tower") {
    towerModule:DOEVENT("raise tower").
} ELSE {
    PRINT "No tower events found, trying elevator...".
    IF towerModule:ALLEVENTNAMES:CONTAINS("Elevator Car Up") {
        towerModule:DOEVENT("Elevator Car Up").
    }
}
WAIT 5.
PRINT "Toggling tower...".
IF towerModule:ALLACTIONNAMES:CONTAINS("Toggle Tower") OR towerModule:ALLACTIONNAMES:CONTAINS("toggle tower") {
    towerModule:DOACTION("Toggle Tower", TRUE).
} ELSE {
    PRINT "No toggle tower action found, trying elevator...".
    IF towerModule:ALLACTIONNAMES:CONTAINS("Toggle Elevator Car") {
        towerModule:DOACTION("Toggle Elevator Car", TRUE).
    }
}
WAIT 5.
PRINT "Tower animation test complete.".