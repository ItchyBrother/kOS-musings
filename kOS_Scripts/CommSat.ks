CLEARSCREEN.
PARAMETER para1 IS "none".
// GLOBAL target_Ap    TO 0.
// GLOBAL target_Pe    TO 0.
// SET bypassmenu   TO FALSE.

//CORE:PART:GETMODULE("KOSProcessor"):DOEVENT("Open Terminal"). //comment out if you don't want terminal window to open.
PRINT "Satellite processor Active.".
//RCS ON.
//LOCK STEERING TO PROGRADE.
//WAIT UNTIL VANG(SHIP:FACING:VECTOR, PROGRADE:VECTOR) < 1.
//RCS OFF.

IF para1 = "none" {
    SET useMessaging TO TRUE.  // DEFAULT BEHAVIOR
    PRINT "Processor Messaging Active.".
} ELSE {
    SET useMessaging TO FALSE. // Any other Parameter other than "none" will set to FALSE.
    PRINT "Set parameter " + para1.
    PRINT "Bypassing Processor Messaging".
    PRINT "PRESS CTL+C if this is not what you want.".
    WAIT 10.
    SET target_Ap TO SHIP:ORBIT:APOAPSIS.
    SET target_Pe TO SHIP:ORBIT:PERIAPSIS.
    SET bypassmenu TO FALSE.
}

IF useMessaging {
//     // Clear old messages first
//     PRINT "Clearing old messages...".
//     LOCAL cleared IS 0.
//     UNTIL SHIP:MESSAGES:EMPTY {
//         LOCAL oldMsg IS SHIP:MESSAGES:POP.
//         SET cleared TO cleared + 1.
//     }
//     UNTIL CORE:MESSAGES:EMPTY {
//         LOCAL oldMsg IS CORE:MESSAGES:POP.
//         SET cleared TO cleared + 1.
//     }
//     IF cleared > 0 {
//         PRINT "  Cleared " + cleared + " old messages".
//     }

/////////////////// Recieving parameters from booster //////////////////
    PRINT "WAITING FOR MESSAGES.".
    WAIT UNTIL NOT CORE:MESSAGES:EMPTY OR NOT SHIP:MESSAGES:EMPTY.

    IF NOT CORE:MESSAGES:EMPTY {
        SET received TO CORE:MESSAGES:POP.
        PRINT "Message to Processor Received.".
    } ELSE { 
        SET received TO SHIP:MESSAGES:POP.
        PRINT "Message received from Vessel connection.".
    }
////////////////////////////////////////////////////////////////////////   

    SET msgtype TO received:CONTENT[0].
    SET msgparameters TO received:CONTENT:SUBLIST(1, received:CONTENT:LENGTH - 1).

    // Message types handling
    IF msgtype = "SEPARATION" {
        SET target_Ap    TO msgparameters[0].
        SET target_Pe    TO msgparameters[1].
        SET bypassmenu   TO msgparameters[2].
        WAIT 10.
        PRINT "Agena Separation!".
        STAGE.
        RCS ON.
        SET SHIP:CONTROL:FORE TO 1.
        WAIT 5.
        SET SHIP:CONTROL:FORE TO 0.
        RCS OFF.

    } ELSE IF msgtype = "DOCKALIGN" {
        PRINT "Received DOCKALIGN message from " + msgparameters[0].
        PRINT "Request: " + msgparameters[1].
        
        // Handle both same-vessel and inter-vessel messages
        LOCAL senderVessel IS "".
        IF received:SENDER:ISTYPE("Part") {
            SET senderVessel TO received:SENDER:SHIP.
        } ELSE {
            SET senderVessel TO received:SENDER.
        }
        
        // Prompt operator for approval
        PRINT " ".
        PRINT "================================================".
        PRINT "DOCKING ALIGNMENT REQUEST".
        PRINT "From: " + msgparameters[0].
        PRINT "================================================".
        PRINT "Approve approach? (Y/N)".
        
        TERMINAL:INPUT:CLEAR.
        LOCAL response IS "".
        UNTIL response = "Y" OR response = "y" OR response = "N" OR response = "n" {
            SET response TO TERMINAL:INPUT:GETCHAR().
            WAIT 0.1.
        }
        
        // Send response back to chase vessel
        LOCAL replyMsg IS LIST().
        IF response = "Y" OR response = "y" {
            SET replyMsg TO LIST(
                "APPROACH_APPROVED",
                SHIP:NAME,
                "Approach clearance granted",
                TIME:SECONDS
            ).
            PRINT "Clearance GRANTED - sending response.".
        } ELSE {
            SET replyMsg TO LIST(
                "APPROACH_DENIED",
                SHIP:NAME,
                "Approach clearance denied",
                TIME:SECONDS
            ).
            PRINT "Clearance DENIED - sending response.".
        }
        
        // Send reply
        LOCAL replySent IS FALSE.
        IF senderVessel:HASSUFFIX("CONNECTION") {
            IF senderVessel:CONNECTION:ISCONNECTED {
                senderVessel:CONNECTION:SENDMESSAGE(replyMsg).
                PRINT "Response sent to " + senderVessel:NAME.
                
                LOCAL deliveryTime IS senderVessel:CONNECTION:DELAY + 1.
                PRINT "Waiting " + ROUND(deliveryTime, 1) + "s for delivery...".
                WAIT deliveryTime.
                SET replySent TO TRUE.
            } ELSE {
                PRINT "WARNING: Sender not connected - cannot reply.".
            }
        } ELSE {
            PRINT "WARNING: Cannot send response - sender has no connection.".
        }
        
        // Only align if approved AND reply was sent
        IF (response = "Y" OR response = "y") AND replySent {
            SAS OFF.
            RCS ON.
            
            // Store sender vessel reference for alignment
            GLOBAL chaseVessel IS senderVessel.
            
            LOCK STEERING TO LOOKDIRUP(chaseVessel:POSITION, SHIP:FACING:TOPVECTOR).
            PRINT "Aligning to chase vessel: " + chaseVessel:NAME.
            
            WAIT UNTIL VANG(SHIP:FACING:VECTOR, chaseVessel:POSITION:NORMALIZED) < 5.
            PRINT "ALIGNED, READY FOR DOCKING.".
            
            // Maintain alignment - this will run until docking or script termination
            PRINT "Maintaining alignment until docking...".
            LOCAL dockingPorts IS SHIP:DOCKINGPORTS.
            LOCAL docked IS FALSE.

            UNTIL docked {
                // Check all docking ports for docked state
                FOR port IN dockingPorts {
                    IF port:STATE = "Docked" OR port:STATE:CONTAINS("Docked") {
                        SET docked TO TRUE.
                        PRINT "DOCKING DETECTED on port: " + port:TITLE.
                        BREAK.
                    }
                }
                
                // Also check if vessel count changed (alternative detection)
                IF NOT docked {
                    IF SHIP:PARTS:LENGTH <> SHIP:ROOTPART:SHIP:PARTS:LENGTH {
                        SET docked TO TRUE.
                        PRINT "DOCKING DETECTED via parts count change.".
                    }
                }
                
                WAIT 0.5.
            }

            // Docking confirmed - neutralize all controls
            PRINT "Docking complete - neutralizing controls.".
            SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
            RCS OFF.
            SAS OFF.
            UNLOCK STEERING.
            
            PRINT "Target vessel secured. Docking sequence complete.".
            PRINT "Target PROCESSOR WAIT, CTL+C to put in Standby mode.".
            WAIT UNTIL FALSE.
            
        } ELSE IF NOT replySent {
            PRINT "Could not send response - maintaining current state.".
        } ELSE {
            PRINT "Approach denied - maintaining current attitude.".
        }
        
        // Note: If you need the script to continue processing other messages,
        // remove the UNTIL FALSE loop above and let execution continue
        
    } ELSE {
        SET target_Ap    TO 0.
        SET target_Pe    TO 0.
        SET bypassmenu   TO FALSE.
        PRINT "Bypass Agena Separation!".
    }
        
}

// A complete kOS script to configure and insert an arbitrary orbit
// with user‑defined apoapsis, periapsis, and inclination, then execute the burn.

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 1) HELPER FUNCTIONS
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

// Prompt the user for a numeric value in the terminal
FUNCTION GetNumericInput {
    LOCAL inputString IS "".
    PRINT "Enter new value (press Enter when done): ".
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL mychar IS TERMINAL:INPUT:GETCHAR().
            IF mychar = TERMINAL:INPUT:RETURN {
                BREAK.
            } ELSE IF (mychar >= "0" AND mychar <= "9") OR mychar = "." {
                SET inputString TO inputString + mychar.
                PRINT "          " AT (TERMINAL:WIDTH - 20, TERMINAL:HEIGHT - 1).
                PRINT inputString AT (TERMINAL:WIDTH - 20, TERMINAL:HEIGHT - 1).
            }
        }
        WAIT 0.01.
    }
    IF inputString = "" {
        PRINT "No input provided, returning 0.".
        RETURN 0.
    }
    LOCAL numericValue IS inputString:TONUMBER(0).
    IF numericValue = 0 AND inputString <> "0" {
        PRINT "Invalid number entered, using 0.".
    }
    RETURN numericValue.
}

// Remove leading zeros for display
// Strip Padding
FUNCTION StripPadding {
    PARAMETER num.
    LOCAL numStr IS "" + num.
    UNTIL numStr:STARTSWITH("0") = FALSE {
        IF numStr:LENGTH > 1 {
            SET numStr TO numStr:SUBSTRING(1, numStr:LENGTH - 1).
        } ELSE {
            BREAK.
        }
    }
    RETURN numStr.
}

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 2) GLOBAL PARAMETERS & MENU
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

GLOBAL targetInc TO 0.      // desired inclination in degrees

FUNCTION ConfigureOrbit {
    UNTIL FALSE {
        CLEARSCREEN.
        PRINT "=== Orbit Insertion Setup ===".
        PRINT "1) Target Apoapsis Altitude : " + StripPadding(target_Ap) + " m".
        PRINT "2) Target Periapsis Altitude: " + StripPadding(target_Pe)  + " m".
        PRINT "3) Target Inclination       : " + StripPadding(targetInc) + "°".
        PRINT "4) Circularize at target Apoapsis".
        PRINT "5) Set Geostationary Orbit".
        PRINT "6) Set Semi-Geostationary Orbit".
        PRINT "R) Reset to defaults".
        PRINT "Any other key to continue.".
        LOCAL ch IS TERMINAL:INPUT:GETCHAR().
        IF ch = "1" {
            PRINT "Enter apoapsis altitude (m):".
            SET target_Ap TO GetNumericInput().
        } ELSE IF ch = "2" {
            PRINT "Enter periapsis altitude (m):".
            SET target_Pe TO GetNumericInput().
        } ELSE IF ch = "3" {
            PRINT "Enter inclination (deg):".
            SET targetInc TO GetNumericInput().
        } ELSE IF ch = "4" {
            // Circularize: Pe = Ap
            SET target_Pe TO target_Ap.
            PRINT "Set to circularize at " + target_Ap + " m.".
            WAIT 1.
        } ELSE IF ch = "5" {
            SET target_Ap TO 2863334.
            SET target_Pe TO 2863334.
            SET targetInc TO 0.
            PRINT "Geostationary orbit set.".
            WAIT 1.
        } ELSE IF ch = "6" {
            SET target_Ap TO 2863334.
            SET target_Pe TO 2863334 / 4.  // 1/4 height Pe
            SET targetInc TO 0.
            PRINT "Semi-Geostationary orbit set.".
            WAIT 1.
        } ELSE IF ch = "R" OR ch = "r" {
            SET target_Ap TO 200000.
            SET target_Pe  TO 100000.
            SET targetInc TO 0.
            PRINT "Defaults restored.".
            WAIT 1.
        } ELSE {
            BREAK.
        }
        WAIT 0.5.
    }
}

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 3) MAIN ROUTINE
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

IF NOT bypassMenu {
    ConfigureOrbit().
}

CLEARSCREEN.
PRINT ">> Inserting orbit: Ap=" + StripPadding(target_Ap) +
      " m, Pe=" + StripPadding(target_Pe) +
      " m, Inc=" + StripPadding(targetInc) + "°".
WAIT 1.
SWITCH TO 0.
// Safety check: raise Pe if below 70 km
IF SHIP:ORBIT:PERIAPSIS < 70000 {
    
    PRINT "Pe below safe orbit. Raising Pe before orbit insertion...".
    WAIT 5.
    SET tmp_Ap TO ROUND(SHIP:ORBIT:APOAPSIS).
    RUN circ(tmp_Ap, 72000, 0).
    WAIT 1.
    PRINT "Periapsis is now " + ROUND(SHIP:ORBIT:PERIAPSIS) AT (0, 3).
    WAIT 10.
}

// Hand off to circularization script
RUN circ(target_Ap, target_Pe, 0).
UNTIL ABS(SHIP:ORBIT:PERIAPSIS - target_Pe) <= 1000 AND ABS(SHIP:ORBIT:APOAPSIS - target_Ap) <= 1000 {
    RUN circ(target_Ap, target_Pe, 0).
    CLEARSCREEN.
    PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS) + " Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS).
    IF ABS(SHIP:ORBIT:PERIAPSIS - target_Pe) > 1000 OR ABS(SHIP:ORBIT:APOAPSIS - target_Ap) > 1000 {
         PRINT "Still not in the correct orbit.  Trying again.".
    }
    WAIT 10.
}
SWITCH TO 1.
CLEARSCREEN.
PRINT ">> Orbit insertion complete! <<" AT (0,1).
RCS OFF.
WAIT 10.
CLEARSCREEN.
PRINT "CPU is on, ready for your commands.".