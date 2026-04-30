// Print a message to indicate the boot process has started
PRINT "Booting up kOS system...".
WAIT 2.

//TESTING FOR SATURN IB processor, if exsist we deactivate and run launch script, if not we 
//provide a clean prompt for the capsule.
SET SATPROC TO "SATV".

IF SHIP:STATUS = "PRELAUNCH" AND SHIP:PARTSTAGGED(SATPROC):LENGTH > 0 {
    //Deactivating SIVB booster processor.
    PROCESSOR("SATV"):DEACTIVATE().
    PRINT "SIVB STAGE PROCESSOR DEACTIVATED.".
    WAIT 5.
    SWITCH TO 0.
    RUN SatV.

} ELSE {
    //PROCESSOR("SATV"):DEACTIVATE().
    CLEARSCREEN.
    SWITCH TO 0.
    PRINT "SHIP PROCESSOR READY.".
}
