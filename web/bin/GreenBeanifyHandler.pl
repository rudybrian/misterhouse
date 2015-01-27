
#
# GreenBeanifyHandler.pl
#
#
# Requires: JSON (pp), LWP, HTTP::Request
#
# v0.1 10-02-2014 (brudyNO@SPAMpraecogito.com)
# 	First working version.
#

use JSON -support_by_pp;

# Send a 200 if things worked, otherwise give an error.
my $results;

$results .= "$ENV{HTTP_QUERY_STRING}\n";

my $json = new JSON;
# these are some nice json options to relax restrictions a bit:
my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($ENV{HTTP_QUERY_STRING});

if (defined $json_text->{"GreenBeanify"}) {
	# This is the data we are looking for, now do something with it.
	my $device = find_device($json_text->{"GreenBeanify"}->{"serialNumber"});
	if ($device != 0) {
		if ($json_text->{"GreenBeanify"}->{"messageType"} eq "laundry.endOfCycle") {
			if ($json_text->{"GreenBeanify"}->{"data"}->{"text"} eq "End of cycle") {
				# Update the device state
				print_log("Setting " . $json_text->{"GreenBeanify"}->{"serialNumber"} . " to endOfCycle");
				$device->set("endOfCycle", "GreenBeanifyHandler");
				$results = "HTTP/1.0 200 OK\n";
				$results .= "Content-Type: text/html\n\n";
				$results .= "laundry.endOfCycle confirmed\n";
			}
		} else {
			$results = "HTTP/1.0 200 OK\n";
			$results .= "Content-Type: text/html\n\n";
			$results .= "Looks good\n";
		}
	} else {
		$results = "HTTP/1.0 500 Unknown Device\n";
		$results .= "Content-Type: text/html\n\n";
		$results .= "Unknown device " . $json_text->{"GreenBeanify"}->{"serialNumber"} . "\n";
	}
} else {
	$results = "HTTP/1.0 400 Bad Request\n";
	$results .= "Content-Type: text/html\n\n";
	$results .= "Invalid update\n";
}

return $results;


# Find the given device (if defined)
sub find_device {
	my ($serial) = @_;
	my @GBAItems = (&list_objects_by_type('GreenBeanify_Appliance'));
	foreach (@GBAItems) {
		my $obj = &get_object_by_name($_);
		# check the object's serial number property for a match
		if (lc($obj->{serial}) eq lc($serial)) {
			return $obj;
		}
	}

	# There was no matching object found. Print an aerror and bail out.
	return 0;
}
