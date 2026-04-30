SWITCH to 0.
LOCAL destpath TO "1:/CommSat.ks".
LOCAL boosterFound is FALSE.

WAIT 10.
IF NOT EXISTS(destpath) {
    COPYPATH("0:/CommSat.ks", "1:/CommSat.ks").
    PRINT "SAT PROGRAM SUCCESSFULLY COPIED.".
} ELSE {
    CLEARSCREEN.
    PRINT "*************************************".
    PRINT "    SAT program aleady loaded!".
    PRINT "*************************************".
    WAIT 10.
}
WAIT 0.1.
SWITCH to 1.
IF NOT EXISTS(destpath) {
    PRINT "SAT COMPUTER FAILURE".
    PRINT "FILE NOT FOUND ON SAT.".
    PRINT "LIKELY DISK SPACE ISSUE.".
    PRINT "ABORT!  ABORT!  ABORT!".
    PRINT " ".
    PRINT "USING GROUND BASE FILE.".
    SWITCH TO 0.

}

SET msg TO "CommSAT alive!".
SET boosterFound TO FIND_PROCESSOR_BY_NAME("KAtlas").

IF boosterFound {
    IF booster:CONNECTION:SENDMESSAGE(msg) {
        PRINT "Message Sent.".
    } ELSE {
        PRINT "ERROR!".
    } 
    WAIT 2.
    PRINT "Starting CommSAT sender on vessel: " + SHIP:NAME.
    RUN CommSat.
} ELSE {
    PRINT "KAtlas CPU not found. Press to (S)kip?".
    PRINT "or Press (D) for Docking.".
    LOCAL decide IS FALSE.
    UNTIL decide {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL key IS TERMINAL:INPUT:GETCHAR().
                IF key = "S" or key = "s" {
                    PRINT "Skipping...".
                    SET decide TO TRUE.
                    WAIT 0.1.
                    RUN CommSat(FALSE).
                }  
                IF key = "D" or key = "d" {
                    PRINT "Process Docking...".
                    SET decide to TRUE.
                    WAIT 0.1.
                    RUN CommSat.
                }
        } 
    }
}


// Small helper to (re)scan for the processor by name/tag:
FUNCTION FIND_PROCESSOR_BY_NAME {
  PARAMETER targetName.
  LOCAL procs IS LIST().
  LIST PROCESSORS IN procs.                         // all kOS CPUs we can see
  FOR pr IN procs {
    // Most installs expose a name/tag on the processor:
    IF pr:NAME = targetName OR pr:TAG = targetName {
      SET booster TO pr.
      RETURN TRUE.
    }.
  }.
  RETURN FALSE.
}.