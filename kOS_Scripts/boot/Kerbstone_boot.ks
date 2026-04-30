// Kerstone.ks

// Print a message to indicate the boot process has started
PRINT "Booting up kOS system...".

// Define the path to your main script
SET mainScriptPath TO "0:/KerbstoneR3.ks".

// Check if the main script exists
IF EXISTS(mainScriptPath) {
    PRINT "Main script found at " + mainScriptPath.
    PRINT "Press 'R' to run the script or 'A' to abort.".
    
    // Wait for user input
    SET userInput TO TERMINAL:INPUT:GETCHAR().
    
    IF userInput = "R" OR userInput = "r" {
        PRINT "Running main script...".
        RUNPATH(mainScriptPath).
    } ELSE IF userInput = "A" OR userInput = "a" {
        PRINT "Script execution aborted by user.".
    } ELSE {
        PRINT "Invalid input. Boot process halted.".
    }
} ELSE {
    PRINT "ERROR: Main script not found at " + mainScriptPath + ". Please check the script location.".
}

// This line will only be reached if the main script doesn't run or doesn't exist
PRINT "Boot process completed or halted due to error.".