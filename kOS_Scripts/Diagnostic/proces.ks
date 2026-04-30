// THIS IS A TEST TO SEE IF WE CAN SEND A MESSAGE TO THE AGENA 
// AND IT RESPONSE.

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

SET docktarget TO VESSEL("Agena"):CONNECTION.
PRINT "Target vessel: " + VESSEL("Agena"):NAME.
PRINT "Is connected: " + docktarget:ISCONNECTED.

SET SatConfig TO LIST("DOCKALIGN", 0, 0, TRUE).
docktarget:SENDMESSAGE(SatConfig). 
PRINT "Command Sent to Agena".

// CLEARSCREEN.
// SET agena TO VESSEL("Agena").
// PRINT "Target: " + agena:NAME.
// PRINT "Connected: " + agena:CONNECTION:ISCONNECTED.

// // Check sender's own messages first
// PRINT "My SHIP messages: " + SHIP:MESSAGES:LENGTH.
// PRINT "My CORE messages: " + CORE:MESSAGES:LENGTH.

// PRINT "Sending message...".
// agena:CONNECTION:SENDMESSAGE(LIST("TEST", "Hello")).
// PRINT "SENDMESSAGE executed.".

// // Try reading Agena's message queue from the sender
// PRINT "Checking Agena's status...".
// PRINT "Agena loaded: " + agena:LOADED.
// PRINT "Agena unpacked: " + agena:UNPACKED.