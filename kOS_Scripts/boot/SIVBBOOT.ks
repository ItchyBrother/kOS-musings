//SIVBBOOT file.
CLEARSCREEN.
PRINT "Booting up kOS system...".
SWITCH TO 0.
WAIT 30.
//STAGE.
AG9 OFF.  // TURN ON KE-1 ENGINE (J2).
AG8 ON. // TURN OFF ULLAGE MOTORS.  

// Checking for mission config file
LOCAL SIVBChoice IS 0.
IF EXISTS("mission.txt") {
    PRINT "Found mission parameter." AT (0, 1).
    SET SIVBChoice TO OPEN ("mission.txt"):READALL:STRING:TONUMBER(0).
    DELETE ("mission.txt").  // Clean-up.
}

// If there is not config, prompt.
IF SIVBChoice = 0 {
    PRINT "S-IVB staged - now independent vessel" AT (0, 1).
    PRINT "Please select which program to run:" AT (0, 4).
    PRINT "(1) for deorbit OR (2) for Mun impact." AT (0, 6).
    SET SIVBChoice TO TERMINAL:INPUT:GETCHAR().
}

IF SIVBChoice = 1 {
    PRINT "Running Deorbit." AT (0, 10).
    WAIT 5.
    RUNPATH ("0:/Atlas/kAtlasStage.ks").
} ELSE IF SIVBChoice = 2 {
    PRINT "Running Mun Impact" AT (0, 10).
    WAIT 5.
    RUNPATH ("0:/sivbimpact.ks").
} ELSE {
    PRINT "Invalid input, rebooting."  AT (0, 10).
    WAIT 5.
    REBOOT.
}

//END PROGRAM.