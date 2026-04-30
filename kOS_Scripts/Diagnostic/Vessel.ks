PRINT "Scanning for vessels in current SOI...".
LOCAL mySOI IS SHIP:OBT:BODY.  // Your ship's SOI body (e.g., Kerbin).
PRINT "Your SOI: " + mySOI:NAME.

LOCAL soiVessels IS LIST().  // List to hold matching vessels.
LIST VESSELS IN allVessels.  // Get all vessels in the universe.
FOR ves IN allVessels {
    IF ves:OBT:BODY = mySOI AND ves:NAME <> SHIP:NAME {
        soiVessels:ADD(ves).
    }
}

IF soiVessels:LENGTH = 0 {
    PRINT "No other vessels found in this SOI.".
} ELSE {
    PRINT "Found " + soiVessels:LENGTH + " vessels in SOI:".
    FROM {LOCAL i IS 0.} UNTIL i >= soiVessels:LENGTH STEP {SET i TO i+1.} DO {
        LOCAL ves IS soiVessels[i].
        PRINT (i + 1) + ": " + ves:NAME + " (Distance: " + ROUND(SHIP:POSITION - ves:POSITION:MAG, 1) + "m, Status: " + ves:STATUS + ")".
    }
    
    PRINT "Enter number (1-" + soiVessels:LENGTH + ") to target a vessel, or 0 to cancel:".
    LOCAL inputStr IS TERMINAL:INPUT:GETCHAR().  // Simple input; assumes single digit for now.
    LOCAL choice IS inputStr:TONUMBER().
    
    IF choice >= 1 AND choice <= soiVessels:LENGTH {
        LOCAL selectedVes IS soiVessels[choice - 1].
        SET TARGET TO selectedVes.
        PRINT "Target set to: " + selectedVes:NAME.
    } ELSE {
        PRINT "Invalid or cancelled.".
    }
}
WAIT 0.  // Yield to allow target update.