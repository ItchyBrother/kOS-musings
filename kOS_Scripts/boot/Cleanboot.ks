//Cleanboot KOS Script
//This script will launch the terminal automatically and
//switch to the archive.

IF(STATUS = "PRELAUNCH") {
    CORE:PART:GETMODULE("KOSProcessor"):DOEVENT("Open Terminal").
    SWITCH to 0.
    PRINT ("Volume swtich to archive.  Awaiting your command.").
}