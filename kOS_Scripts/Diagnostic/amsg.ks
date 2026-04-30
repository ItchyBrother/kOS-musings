LIST PARTS IN allParts.
FOR p IN allParts {
    IF p:NAME:CONTAINS("Antenna") OR p:NAME:CONTAINS("antenna") {
        PRINT "Part: " + p:NAME + " | Title: " + p:TITLE.
        IF p:HASMODULE("ModuleDataTransmitter") {
            SET mymod TO p:GETMODULE("ModuleDataTransmitter").
            PRINT "  Available fields:".
            FOR field IN mymod:ALLFIELDS {
                PRINT "    " + field.
            }
        }
    }
}
WAIT 10.
CLEARSCREEN.
PRINT "Simple receiver started.".
PRINT "SHIP messages: " + SHIP:MESSAGES:LENGTH.
PRINT "CORE messages: " + CORE:MESSAGES:LENGTH.

FROM {LOCAL i IS 0.} UNTIL i > 30 STEP {SET i TO i + 1.} DO {
    PRINT i + ": SHIP=" + SHIP:MESSAGES:LENGTH + " CORE=" + CORE:MESSAGES:LENGTH.
    
    IF SHIP:MESSAGES:LENGTH > 0 {
        PRINT "SHIP MESSAGE FOUND!".
        SET msg TO SHIP:MESSAGES:POP.
        PRINT "Content: " + msg:CONTENT.
        BREAK.
    }
    
    IF CORE:MESSAGES:LENGTH > 0 {
        PRINT "CORE MESSAGE FOUND!".
        SET msg TO CORE:MESSAGES:POP.
        PRINT "Content: " + msg:CONTENT.
        BREAK.
    }
    
    WAIT 1.
}

PRINT "Test complete.".

// CLEARSCREEN.
// PRINT "Testing message reception...".

// // Manually add a test message to our own queue
// SHIP:CONNECTION:SENDMESSAGE(LIST("SELFTEST")).
// PRINT "Sent message to self.".
// WAIT 1.

// PRINT "SHIP messages: " + SHIP:MESSAGES:LENGTH.
// PRINT "CORE messages: " + CORE:MESSAGES:LENGTH.

// IF SHIP:MESSAGES:LENGTH > 0 {
//     PRINT "Self-message worked - queues are functional.".
//     SET msg TO SHIP:MESSAGES:POP.
//     PRINT "Content: " + msg:CONTENT.
// }