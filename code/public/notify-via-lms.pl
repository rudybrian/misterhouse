#!/usr/bin/perl -w
##
## Send notifications via JSON interaction with LMS
##

# v0.02 9-9-2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Added $debug flag to suppress debugging messages when not testing. 
# 	Argument given will determine what this script will use for the notification audio. 
# 	Added more documentation for how to use this with Festival.
#	Use select instead of sleep and reduce delays when we know the notification audio duration.
#	Fixed loop counter for checking the mode during stream playback.
#	Does not modify synchronization state, so assumes we are playing to the syncgroup master to which others are already synchronised.
#	Does not power on players that are off.
#
# v0.01 9-7-2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
#	First working version using Google TTS

# # notes
#
# To use this with Festival, you can modify your siteinit.scm or other config to something
# like the following (modify the paths as appropriate for your system):
#  (Parameter.set 'Audio_Method 'Audio_Command)
#  (Parameter.set 'Audio_Required_Rate 22000)
#  (Parameter.set 'Audio_Required_Format 'wav)
#  (Parameter.set 'Audio_Command "sox $FILE -r 44100 /tmp/$$.wav; /usr/local/bin/notify-via-lms.pl /tmp/$$.wav; rm /tmp/$$.wav")
#
# See here for another CLI-based version supporting multiple squeezeboxes
# http://forums.indigodomo.com/viewtopic.php?p=43553&sid=5d53cbd4890d02058c4384fc66c0d78e#p43553
#

use strict;
use JSON -support_by_pp;
use HTTP::Request;
use LWP::UserAgent;


# Stuff that might need changing
my $debug = 0;
#my $debug = 1;
my $host_and_port = "localhost:9000";
#my $player_mac = "28:98:7b:d2:d8:d3"; # Galaxy tab
my $player_mac = "6c:f0:49:54:e2:98"; # Acheron
#my $player_mac = "3c:15:c2:e7:10:22"; # MacBook Pro


my $notification_audio = shift; # This can be a file or a URL
if (!defined $notification_audio) {
	die "Sorry, you must provide a file path or URL for the notification audio clip.";
}

my $original_state;

# List the attached players
#parse_json_response(post_to_lms("", '"players","0","10"'));

# get the current mode
$original_state->{"mode"} = parse_json_response(post_to_lms($player_mac, '"mode","?"'), "_mode");

# get the current repeat state
$original_state->{"repeat_state"} = parse_json_response(post_to_lms($player_mac, '"playlist","repeat","?"'), "_repeat");

# pause playback if needed
if ($original_state->{"mode"} eq "play") {
	#parse_json_response(post_to_lms($player_mac, '"pause","1"'));
	parse_json_response(post_to_lms($player_mac, '"pause","1","1"')); # fadeInSecs helps to eliminate the audio pop on resume
}

# get the current playback position
$original_state->{"time"} = parse_json_response(post_to_lms($player_mac, '"time","?"'), "_time");

#
# Consider simplifying the previous stuff with what is returned in the "status" command instead
#

print "Original state mode=" . $original_state->{"mode"} . ", repeat state=" . $original_state->{"repeat_state"} . ", time=" . $original_state->{"time"} . "\n" if $debug;

# save the current playlist to a temporary location
parse_json_response(post_to_lms($player_mac, '"playlist","save", "prenotification_playlist"'));

# set the playback to not repeat if repeat is enabled
if ($original_state->{"repeat_state"} != 0) {
	parse_json_response(post_to_lms($player_mac, '"playlist","repeat","0"'));
}

# play the notification audio
parse_json_response(post_to_lms($player_mac, '"playlist","play", "' . $notification_audio . '"'));

# Find out how long the notification audio is
my $notification_duration = parse_json_response(post_to_lms($player_mac, '"duration","?"'), "_duration");

if ($notification_duration == 0) {
	# this is probably a stream, so we need to watch the mode instead
	my $current_state;
	for (my $loop_count=0; $loop_count < 100; $loop_count++) {
		$current_state = parse_json_response(post_to_lms($player_mac, '"mode","?"'), "_mode");
		if ($current_state ne "play") {
			print "We are no longer playing, bailing out\n" if $debug; 
			last;
		} else {
			print "We are still playing, sleeping for 1 second.\n" if $debug;
			select(undef, undef, undef, 1.0);
		}
	}
} else {
	# wait for the notification to finish
	print "sleeping for " . ($notification_duration + 1) . " seconds.\n" if $debug; 
	select(undef, undef, undef, $notification_duration + 0.250);
}

# Resume the saved playlist and track we were playing 
#
# There is something goofy going on here, as only noplay seems to work, but leaves things in a funny state if set.
#
#parse_json_response(post_to_lms($player_mac, '"playlist","resume", "prenotification_playlist"'));
#parse_json_response(post_to_lms($player_mac, '"playlist","resume","prenotification_playlist","wipePlaylist:1 noplay:1"'));
#parse_json_response(post_to_lms($player_mac, '"playlist","resume","prenotification_playlist","noplay:1 wipePlaylist:1"'));
#parse_json_response(post_to_lms($player_mac, '"playlist","resume","prenotification_playlist","noplay:1"'));
#parse_json_response(post_to_lms($player_mac, '"playlist","resume","prenotification_playlist",["noplay:1"]'));
if ($original_state->{"mode"} eq "play") {
	# We may want to add a fadeInSecs value so this isn't so jarring
	parse_json_response(post_to_lms($player_mac, '"playlist","resume", "prenotification_playlist"'));
	# move the playback position on the track back to where we started
	parse_json_response(post_to_lms($player_mac, '"time","' . $original_state->{"time"} . '"'));
}
else {
	parse_json_response(post_to_lms($player_mac, '"playlist","resume","prenotification_playlist","noplay:1"'));
} 

# set the repeat state back to what it was before if set
if ($original_state->{"repeat_state"} != 0) {
	parse_json_response(post_to_lms($player_mac, '"playlist","repeat","' . $original_state->{"repeat_state"} . '"'));
}


print "Done!\n" if $debug;



###
# Just subs below here
###

# parse the JSON result in the response and optionally return the given extract value
sub parse_json_response {
	my ($response, $extract) = @_;
	print "response: $response\n" if $debug;

	my $json = new JSON;
	my $result;

	# these are some nice json options to relax restrictions a bit:
	my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($response);

	foreach my $tlc (keys %{$json_text->{"result"}}){
		print "\n$tlc\n" if $debug;
		if ($json_text->{"result"}->{$tlc} =~ /array/i) {
			for (my $i = 0; $i <= (scalar @{$json_text->{"result"}->{$tlc}} - 1); $i++) {
				print "->[$i]\n" if $debug;
				if ($json_text->{"result"}->{$tlc}->[$i] eq "") {
					print "skipping empty field\n" if $debug;
				}
				else {
					foreach my $cat (keys %{$json_text->{"result"}->{$tlc}->[$i]}) {
						if (defined $json_text->{"result"}->{$tlc}->[$i]->{$cat}) {
							print "\t$cat=" . $json_text->{"result"}->{$tlc}->[$i]->{$cat} . "\n" if $debug;
							if (defined $extract) {
								if ($tlc eq $extract) {
									$result = $json_text->{"result"}->{$tlc}->[$i]->{$cat};
								}
							}
						}
						else {
							print "\t$cat=null\n" if $debug;
						}
					}
				}
			}
		} else {
			# This is not an array so just print it
			print "\t" . $json_text->{"result"}->{$tlc} . "\n" if $debug;
			if (defined $extract) {
				if ($tlc eq $extract) {
					$result = $json_text->{"result"}->{$tlc};
				}
			}
		}
	}
	return $result;
}


# Send the command to the LMS server
sub post_to_lms {
	my ($client_id, $command) = @_;
	my $json_url = "http://$host_and_port/jsonrpc.js";
	# download the json page:
	print "Getting json $json_url\n" if $debug;
	my $request = new HTTP::Request('POST' => $json_url);
	$request->content_type("text/json");
	
	my $rjson = "{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[$command]]}";
	$request->content($rjson);

	print "POSTing $rjson to $json_url\n" if $debug;

	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);

	my $response =  $ua->request($request);
	return $response->content();
}
