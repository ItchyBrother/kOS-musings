LOCAL destpath TO "1:/KerbAgena.ks".
IF(STATUS = "PRELAUNCH") {
    CORE:PART:GETMODULE("KOSProcessor"):DOEVENT("Open Terminal").
    SWITCH TO 0.
    PRINT ("Volume swtich to archive.  STARTING KerbAgena in 5 seconds....").
    COPYPATH("0:/KerbAgena.ks", "1:/KerbAgena.ks").
    IF NOT EXISTS(destpath) {
        COPYPATH("0:/KerbAgena.ks", "1:/KerbAgena.ks").
        PRINT "BOOSTER PROGRAM COPIED SUCCESSFULLY.".
    } 
    SWITCH TO 1.
}
WAIT 5.
//TEST AGAIN to see if it is loaded internally.  If not, throw error.
IF NOT EXISTS(destpath) {
    PRINT "ERROR! Launch computer failure!!!".
    PRINT "ABORT!  ABORT!  ABORT!".
    SHUTDOWN.
}
PRINT "Internal computer active!".
RUN KerbAgena.