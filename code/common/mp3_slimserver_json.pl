# Category=Music
#
#@ This script controls the Slimserver software
#@ This version has been modified in order to optionaly and transparently direct mh/slimserver
#@ music to networked computers, using their own players
#@ surch as Winamp, as another way to distribute music streams into different destinations,
#@ and to display the related clients/slimserver activity in the Tk Log window.
#@
#@ Also It has been tested with SliMP3 hardware on x86 Linux, but should work
#@ with Squeezebox as well as on any platform.
#@
#@ Enable common/mp3.pl to manage MP3's.
#@
#@ Set slimserver_server parms and slimserver_player parms
#@ to the slimserver host:web port, and player to the MAC address or client name.
#@ Defaults are to localhost:9000 but slimserver_player parm is required to be filled or blank.
#@
#@
#@ The multiplayer option Works by leaving empty the mh.ini slimserver_player parm (client name or 
#@ MAC address), if so it will automatically retrieve the first remote client ID, reedirecting the 
#@ slimserver service to that client.
#@
#@ As requirements:
#@
#@ Install the software player on each remote client (Winamp)
#@ Install this mp3_slimserver.pl
#@ Install the slimserver itself 
#@ Finally you need to manually let each of your players find the slimserver stream by executing
#@ (example Winamp to slimserver IP and port): 
#@   Open your Remote Winamp-> Play-> Location->then type http://your_server_IP:9000/stream.mp3
#@   Your Winamp Player will be ready to stream from slimserver
#@
#@ The only Drawbacks: The play,Prev,Next commands on the remote player 
#@ must be issued using the misterhouse mp3 web interface, 
#@ the response to a command takes as much as 8 seconds and can't control volume.
#@ The Pros: It is a rather simple (even wireless) unexpensive and effective way to distribute
#@  your mp3 jukebox music to several PCs.
#@
#@ Don't forget to set mp3_dir to point to both the playlists and the music dirs
#@ If slimserver runs on a diff machine, I believe the paths need to
#@ be the same for both machines to these dirs.
#@
=begin comment

 mp3_slimserver_json.pl

 Slimserver is for SliMP3 and Squeezebox products from
 http://www.slimdevices.com.

 Original author: Paul Estes
 Hacked from mp3_winamp.pl
 V1.0 30 Nov 03 - created
 Modify by Raul Rodriguez July 25th,2004
 V2.0 8-29-2014 - Brian Rudy: port of original mp3_slimserver to using the JSON interface 
                  available in Logitech Media Server
 Known bugs:
 History and recovery playlists show up in the playlist on mh
 Playlists with apostrophes don't work
 Probably others

=cut


use Mp3Player;

$jukebox = new Mp3Player;
$lms_json_control = new Process_Item;


sub mp3_play {
	my $file = shift;
	my $host = $config_parms{slimserver_host};
	$host = 'localhost:9000' unless $host;
	my $client_id = $config_parms{slimserver_player};
	print_log "Player ID for playing slimserver " . $client_id;
	print_log "mp3 play: $file";
	$file =~ s/ /\%20/g;
	unless ($file =~ m/^http/) {
		$file = "file:\/\/" . $file;
	}
	my $url = "http://$host";
	print_log "Setting $host slimserver to play $file" if $Debug{'slimserver'};
	my $json = "\'{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[\"playlist\", \"play\", \"$file\"]]}\'";
	my $cmd;
	$cmd = qq[get_url $url/jsonrpc.js -post $json -content_type "text/json"]; 
	print_log "Running $cmd" if $Debug{'slimserver'};
	set $lms_json_control $cmd;
	start $lms_json_control;
}

sub mp3_queue {
	my $file = shift;
	my $host = $config_parms{slimserver_host};
	$host = 'localhost:9000' unless $host;
	my $client_id = $config_parms{slimserver_player};
	print_log "Player ID for slimserver " . $client_id;
	print_log "mp3 queue: $file";
	$file =~ s/ /\%20/g;
	unless ($file =~ m/^http/) {
		$file = "file:\/\/" . $file;
	}
	my $url = "http://$host";
	print_log "Setting $host slimserver to add $file" if $Debug{'slimserver'};
	my $json = "\'{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[\"playlist\", \"add\", \"$file\"]]}\'";
	my $cmd;
	$cmd = qq[get_url $url/jsonrpc.js -post $json -content_type "text/json"]; 
	print_log "Running $cmd" if $Debug{'slimserver'};
	set $lms_json_control $cmd;
	start $lms_json_control;
}

sub mp3_clear {
	my $host = $config_parms{slimserver_host};
	$host = 'localhost:9000' unless $host;
	my $client_id = $config_parms{slimserver_player};
	print_log "Player ID for slimserver " . $client_id;
	print_log "mp3 playlist cleared";
	#my $url = "http://$host/status.txt?p0=playlist&p1=clear&player=$client_ip";
        #print "slimserver request: $url\n" if $Debug{'slimserver'};
	#get $url;
	my $url = "http://$host";
	print_log "Setting $host slimserver to clear" if $Debug{'slimserver'};
	my $json = "\'{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[\"playlist\", \"clear\"]]}\'";
	my $cmd;
	$cmd = qq[get_url $url/jsonrpc.js -post $json -content_type "text/json"]; 
	print_log "Running $cmd" if $Debug{'slimserver'};
	set $lms_json_control $cmd;
	start $lms_json_control;
}

sub mp3_get_playlist {
# This doesn't work yet
    return 0;
}

sub mp3_get_playlist_pos {
    # don't know how to do this 
    return 0;
}

# noloop=start      This directive allows this code to be run on startup/reload
my $mp3_states = "Play,Stop,Pause,Next Song,Previous Song,Volume up,Volume down";
my %slim_commands = ('play' => '"play"', 'stop' => '"stop"',
		'pause' => '"pause","1"', 'next song' => '"playlist","index","+1"',
		'previous song' => '"playlist","index","-1"', 'volume up' => '"mixer","volume","+5"',
		'volume down' => '"mixer","volume","-5"');
$v_slimserver_control = new Voice_Cmd("Set the house mp3 player to [$mp3_states]");
# noloop=stop

sub mp3_control {
	my $command = shift;
	$command = $slim_commands{lc($command)} if $slim_commands{lc($command)};

	my $host = $config_parms{slimserver_host};
	$host = 'localhost:9000' unless $host;
	my $client_id = $config_parms{slimserver_player};
	print_log "Player ID for slimserver " . $client_id;
	my $url = "http://$host";
	print_log "Setting $host slimserver to $command" if $Debug{'slimserver'};
	my $json = "\'{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$client_id\",[$command]]}\'";
	my $cmd;
	$cmd = qq[get_url $url/jsonrpc.js -post $json -content_type "text/json"]; 
	print_log "Running $cmd" if $Debug{'slimserver'};
	set $lms_json_control $cmd;
	start $lms_json_control;
}

if ($state = said $v_slimserver_control) {
       respond "app=mp3 $state";
       mp3_control($state);
}
