# Category=Appliances
#
# Code for handling GreenBeanify-enabled appliances
#
# Currently only supports notifications on error and end of cycle for GE Washing machines and Dryers

if (state_now $washing_machine eq "endofcycle") {
	print_log "The load in the washing machine (" . $washing_machine->{'serial'} . ") is now complete.";
	speak "The load in the washing machine is now complete.";
}

 
if (state_now $dryer eq "endofcycle") {
	print_log "The load in the dryer (" . $dryer->{'serial'} . ") is now complete.";
	speak "The load in the dryer is now complete.";
}

