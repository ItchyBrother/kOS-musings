// Titan.ks

// Print a message to indicate the boot process has started
PRINT "Booting up kOS system...".
WAIT 2.

//TESTING FOR Titan processor, if exsist we deactivate and run Titan script, if not we 
//provide a clean prompt for the capsule.
SET Titanpros TO "Titan".

IF SHIP:PARTSTAGGED(Titanpros):LENGTH > 0 {
    //Deactivating Titan booster processor.
    PROCESSOR("Titan"):DEACTIVATE().
    PRINT "TITAN SECOND STAGE PROCESSOR DEACTIVATED.".
    WAIT 5.
    SWITCH TO 0.
    RUN GTitan.

} ELSE {
    CLEARSCREEN.
    PRINT "SHIP PROCESSOR READY.".
}
