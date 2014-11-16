#!/usr/bin/perl -w
##
## Send notifications via JSON interaction with LMS
##

#
# v0.03 09-15-2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Added proper Getopt handling
# 	Added support for device sync
# 	Added ability to specify player
# 	Added ability to exclude players
# 	Added proper help text
# 	Added ability to override default number of players
#
# v0.02 09-09-2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
# 	Added $parms{debug} flag to suppress debugging messages when not testing. 
# 	Argument given will determine what this script will use for the notification audio. 
# 	Added more documentation for how to use this with Festival.
#	Use select instead of sleep and reduce delays when we know the notification audio duration.
#	Fixed loop counter for checking the mode during stream playback.
#	Does not modify synchronization state, so assumes we are playing to the syncgroup master to which others are already synchronised.
#	Does not power on players that are off.
#
# v0.01 09-07-2014 Brian Rudy (brudyNO@SPAMpraecogito.com)
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

my ($Pgm_Path, $Pgm_Name);
BEGIN {
    ($Pgm_Path, $Pgm_Name) = $0 =~ /(.*)[\\\/](.*)\.?/;
    ($Pgm_Name) = $0 =~ /([^.]+)/, $Pgm_Path = '.' unless $Pgm_Name;
    eval "use lib '$Pgm_Path/../lib', '$Pgm_Path/../lib/site'"; # So perl2exe works
}

use JSON -support_by_pp;
use HTTP::Request;
use LWP::UserAgent;
use Getopt::Long;

my %parms;
if (!&GetOptions(\%parms, 'h', 'help', 'debug', 
		'player=s', 'username=s', 'password=s', 'sync', 'lmshost=s',
		'exclude=s@', 'maxplayers=i') or
	!@ARGV or $parms{h} or $parms{help}) {
	
	print<<eof;

	$Pgm_Name instructs a Logitech Media Server instance to play the given notification audio.

Usage:

	$Pgm_Name [-debug] [-player 'player MAC'] [-sync] url_or_file_path

	-debug:	Enable verbose debugging.

	-player 'player MAC':	Send the audio to the given player MAC. When -sync is enabled
				this will be the sync group master.

	-username 'username':	The username to use when authentication is enabled
	-password 'password':	The password to use when authentication is enabled

	-sync:	Sync the players before playing the notification audio. If -player is defined
		the given player will be sync group master. If it is undefined, the first active 
		player will be used for the sync group master.

	-exclude 'mac1':	If sync is enabled, exclude the given player(s) from being 
				added to the sync group and playing the notification audio.

	-lmshost 'host:port':	Override the default of localhost:9000

	-maxplayers 'val':	Override the default of 10 players

	url_or_file_path can be a URL or a file path (must be the absolute file path)

eof
	exit;
}

# Stuff that might need changing
$parms{lmshost} = "localhost:9000" unless $parms{lmshost};
$parms{maxplayers} = 10 unless $parms{maxplayers};
my $player_mac = $parms{player} if $parms{player};
my $notification_audio = shift; # This can be a file or a URL
my $original_state;
my $players;

if ($parms{sync}) {
	# List the attached players
	$players = parse_json_response(post_to_lms("", '"players","0","' . ($parms{maxplayers} - 1) . '"'), "players_loop", "AoH");

	# Some helpful stuff while debugging
	if ($parms{debug}) {
		print "Found " . ($#{$players} + 1) . " players\n";
		foreach my $href (@$players) {
			print "{\n";
			foreach my $key (keys %$href) {
				if (defined $href->{$key}) {
					print "\t$key=" . $href->{$key} . "\n";
				} else {
					print "\t$key=NULL\n";
				}
			}
			print "}\n";
		}
	}
	
	# Now get the current state of all players
	for my $index (0 .. $#{$players}) {
		my $player_vals = parse_json_response(post_to_lms($players->[$index]{playerid}, '"status","0","2"'),"","hashes");
		# print out what we got back
		foreach my $key (keys %$player_vals) {
			print "$key=" . $player_vals->{$key} . "\n" if $parms{debug};
			# Copy each of the hash values into the $players hash reference for easier access
			$players->[$index]{$key} = $player_vals->{$key};
		}
	}

	# Setup player synch
	my $master;
	for my $index (0 .. $#{$players}) {
		# determine who should be in the sync group
		if ($parms{exclude}) {
			if (scalar grep $players->[$index]{playerid} eq $_, @{$parms{exclude}}) {
				print "Skipping " . $players->[$index]{playerid} . 
					" since we have been instructed to exclude it.\n" if $parms{debug};
				next;
			}
		}

		# Save the current playlist and stop playback
		if ($players->[$index]{"mode"} eq "play") {
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"pause","1","1"')); # fadeInSecs helps to eliminate the audio pop on resume
		}
		
		parse_json_response(post_to_lms($players->[$index]{playerid}, '"playlist","save", "prenotification_playlist_' . $index . '"'));

		# Assign the sync group master
		if ($parms{player}) {
			$master = $parms{player};
		} elsif (!defined $master) {
			$master = $players->[$index]{playerid};
		}

		print "Setting up player sync\n" if $parms{debug};
		# break any existing synchronization, and setup a new one
		unless ($players->[$index]{playerid} eq $master) {
			if (defined $players->[$index]{sync_master}) {
				if ($players->[$index]{sync_master} eq $master) {
					print "Nothing to do here. $master is already the sync_master\n" if $parms{debug};
					next;
				}
			}
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"sync","-"'));
			parse_json_response(post_to_lms($master, '"sync","' . $players->[$index]{playerid} . '"'));
		} else {
			print "Nothing to do here. We ($master) are the sync_master\n" if $parms{debug};
		}
	}
	$player_mac = $master;
	print "Player sync setup complete. Continuing...\n" if $parms{debug};
} else {
	my $player_vals = parse_json_response(post_to_lms($player_mac, '"status","0","2"'),"","hashes");

	# get the current mode
	$original_state->{"mode"} = $player_vals->{mode};

	# get the current repeat state
	$original_state->{"repeat_state"} = $player_vals->{"playlist repeat"};

	# get the current playback position
	$original_state->{"time"} = $player_vals->{"time"};

	# pause playback if needed
	if ($original_state->{"mode"} eq "play") {
		parse_json_response(post_to_lms($player_mac, '"pause","1","1"')); # fadeInSecs helps to eliminate the audio pop on resume
	}

	print "Original state mode=" . $original_state->{"mode"} . ", repeat state=" . $original_state->{"repeat_state"} . ", time=" . $original_state->{"time"} . "\n" if $parms{debug};

	# save the current playlist to a temporary location
	parse_json_response(post_to_lms($player_mac, '"playlist","save", "prenotification_playlist"'));
}


# set the playback to not repeat
parse_json_response(post_to_lms($player_mac, '"playlist","repeat","0"'));

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
			print "We are no longer playing, bailing out\n" if $parms{debug}; 
			last;
		} else {
			print "We are still playing, sleeping for 1 second.\n" if $parms{debug};
			select(undef, undef, undef, 1.0);
		}
	}
} else {
	# wait for the notification to finish
	print "sleeping for " . ($notification_duration + 1) . " seconds.\n" if $parms{debug}; 
	select(undef, undef, undef, $notification_duration + 1);
}

# Restore the previous states
if ($parms{sync}) {
	for my $index (0 .. $#{$players}) {
		# determine who should be in the sync group
		if ($parms{exclude}) {
			if (scalar grep $players->[$index]{playerid} eq $_, @{$parms{exclude}}) {
				print "Not clearing sync for " . $players->[$index]{playerid} . 
					" since we have been instructed to exclude it.\n" if $parms{debug};
				next;
			}
		}
		# Break sync
		parse_json_response(post_to_lms($players->[$index]{playerid}, '"sync","-"'));
	}
	for my $index (0 .. $#{$players}) {
		if ($parms{exclude}) {
			if (scalar grep $players->[$index]{playerid} eq $_, @{$parms{exclude}}) {
				print "Skipping settings restoration for " . $players->[$index]{playerid} . 
					" since we have been instructed to exclude it.\n" if $parms{debug};
				next;
			}
		}
		# Restore sync to state it was in before the notification playback
		if ($players->[$index]{sync_master}) {
			parse_json_response(post_to_lms($players->[$index]{sync_master}, '"sync","' . $players->[$index]{playerid} . '"'));
		}

		# Resume our playlist
		if ($players->[$index]{mode} eq "play") {
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"playlist","resume", "prenotification_playlist_' . $index . '"'));
			# move the playback position on the track back to where we started
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"time","' . $players->[$index]{"time"} . '"'));
		} else {
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"playlist","resume", "prenotification_playlist_' . $index . '","noplay:1"'));
		}
		
		# set the repeat state back to what it was before if set
		if ($players->[$index]{"playlist repeat"} != 0) {
			parse_json_response(post_to_lms($players->[$index]{playerid}, '"playlist","repeat","' . $players->[$index]{"playlist repeat"} . '"'));
		}
	}
} else {
	# Resume the saved playlist and track we were playing 
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
}

print "Done!\n" if $parms{debug};



###
# Just subs below here
###

# parse the JSON result in the response and optionally return the given extract value
sub parse_json_response {
	my ($response, $extract, $mode) = @_;
	print "response: $response\n" if $parms{debug};

	my $json = new JSON;
	my $result;
	my @AoH;
	my %hashes;

	# these are some nice json options to relax restrictions a bit:
	my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($response);

	foreach my $tlc (keys %{$json_text->{"result"}}){
		print "\n$tlc\n" if $parms{debug};
		if ($json_text->{"result"}->{$tlc} =~ /array/i) {
			for (my $i = 0; $i <= (scalar @{$json_text->{"result"}->{$tlc}} - 1); $i++) {
				print "->[$i]\n" if $parms{debug};
				if ($json_text->{"result"}->{$tlc}->[$i] eq "") {
					print "skipping empty field\n" if $parms{debug};
				}
				else {
					if (defined $mode) {
						if (($mode eq "AoH") && ($tlc eq $extract))  {
							push @AoH, $json_text->{"result"}->{$tlc}->[$i];
						}
					} 
					else {
						foreach my $cat (keys %{$json_text->{"result"}->{$tlc}->[$i]}) {
							if (defined $json_text->{"result"}->{$tlc}->[$i]->{$cat}) {
								print "\t$cat=" . $json_text->{"result"}->{$tlc}->[$i]->{$cat} . "\n" if $parms{debug};
								if (defined $extract) {
									if ($tlc eq $extract) {
										$result = $json_text->{"result"}->{$tlc}->[$i]->{$cat};
									}
								}
							}
							else {
								print "\t$cat=null\n" if $parms{debug};
							}
						}
					}
				}
			}
		} else {
			# This is not an array so just print it
			print "\t" . $json_text->{"result"}->{$tlc} . "\n" if $parms{debug};
			if (defined $extract) {
				if ($tlc eq $extract) {
					$result = $json_text->{"result"}->{$tlc};
				}
			}
			if (defined $mode) { 
				if (($mode eq "hashes")) {
					$hashes{$tlc} = $json_text->{"result"}->{$tlc};
				}
			}
		}
	}
	if (defined $mode) {
		if ($mode eq "AoH"){
			return \@AoH;
		} elsif ($mode eq "hashes") {
			return \%hashes;
		}
	} else {
		return $result;
	}
}


# Send the command to the LMS server
sub post_to_lms {
	my ($client_id, $command) = @_;
	my $json_url = "http://" . $parms{lmshost} . "/jsonrpc.js";
	# download the json page:
	print "Getting json $json_url\n" if $parms{debug};
	my $request = new HTTP::Request('POST' => $json_url);
	$request->content_type("text/json");
	
	my $rjson = "{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[$command]]}";
	$request->content($rjson);

	print "POSTing $rjson to $json_url\n" if $parms{debug};

	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);

	my $response =  $ua->request($request);
	return $response->content();
}
