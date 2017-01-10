
#
# Interfaces with the Alexa Smart Home (ConnectedHome) API via AWS Lambda.
#
# Currently supports Discovery and Control functions for a
# fixed set of devices in a group
#
# Brian Rudy (brudyNO@SPAMpraecogito.com)
#

use vars qw(%Http $HTTP_BODY $HTTP_REQUEST %HTTP_ARGV);

use JSON-support_by_pp;
use Data::GUID;
use strict;

my $list_name      = "Lights";
my $module_version = "0.1";

#my $results = "$ENV{HTTP_QUERY_STRING}\n";

# We should make sure we have received something JSON in the POST body before continuing

my $json = new JSON;

# these are some nice json options to relax restrictions a bit:
my $json_text =
  $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote
  ->allow_barekey->decode( $ENV{HTTP_QUERY_STRING} );

my $guid = Data::GUID->new;

if ( defined $json_text->{"header"}->{"namespace"} ) {
    if ( $json_text->{"header"}->{"namespace"} eq
        "Alexa.ConnectedHome.Discovery" )
    {
        # Handle discovery stuff here
        if ( $json_text->{"header"}->{"name"} eq "DiscoverAppliancesRequest" ) {

            # compose the response to send back
            my $response_data = {
                header => {
                    messageId      => lc( $guid->as_string ),
                    name           => "DiscoverAppliancesResponse",
                    namespace      => "Alexa.ConnectedHome.Discovery",
                    payloadVersion => "2"
                }
            };
            my @objects = &list_objects_by_type($list_name);
            @objects = &list_objects_by_group($list_name) unless @objects;
            my @appliances;
            for my $item ( sort @objects ) {
                next unless $item;
                my $object = &get_object_by_name($item);

                next if $object->{hidden};
                if ( $object->can('state') || $object->can('state_level') ) {
                    my ( $can_onoff, $can_percent ) =
                      checkSupportedStates($object);
                    my $stripped_appianceId = $object->{object_name};
                    $stripped_appianceId =~ s/\$//g;
                    my $appliance = {
                        applianceId => $stripped_appianceId,
                        friendlyDescription =>
                          toFriendlyName( $object->{object_name} ),
                        friendlyName =>
                          toFriendlyName( $object->{object_name} ),
                        isReachable      => JSON::true,
                        manufacturerName => "MisterHouse",
                        modelName        => "MisterHouse",
                        additionalApplianceDetails =>
                          { fullApplianceId => $object->{object_name} },
                        version => "Ver-$module_version"
                    };
                    if ( $can_onoff && $can_percent ) {
                        $appliance->{"actions"} = [
                            "incrementPercentage", "decrementPercentage",
                            "setPercentage",       "turnOn",
                            "turnOff"
                        ];
                    }
                    elsif ($can_onoff) {
                        $appliance->{"actions"} = [ "turnOn", "turnOff" ];
                    }
                    elsif ($can_percent) {
                        $appliance->{"actions"} = [
                            "incrementPercentage", "decrementPercentage",
                            "setPercentage"
                        ];
                    }
                    push @appliances, $appliance;
                }
            }
            push @{ $response_data->{"payload"}->{"discoveredAppliances"} },
              @appliances;

            my $response = "HTTP/1.0 200 OK\n";
            $response .= "Content-Type: application/json\n\n";
            $response .= encode_json $response_data;
            return $response;
        }
    }
    elsif (
        $json_text->{"header"}->{"namespace"} eq "Alexa.ConnectedHome.Control" )
    {
        # Do control stuff here
        my $response_data = {
            header => {
                messageId      => lc( $guid->as_string ),
                namespace      => "Alexa.ConnectedHome.Control",
                payloadVersion => "2"
            },
            payload => {}
        };
        my $obj =
          &get_object_by_name(
            $json_text->{"payload"}->{"appliance"}->{"applianceId"} );
        my $reqname = $json_text->{"header"}->{"name"};

        if ( $reqname eq "TurnOnRequest" ) {
            set $obj ON;
            $response_data->{"header"}->{"name"} = "TurnOnConfirmation";
        }
        elsif ( $reqname eq "TurnOffRequest" ) {
            set $obj OFF;
            $response_data->{"header"}->{"name"} = "TurnOffConfirmation";
        }
        elsif ( $reqname eq "SetPercentageRequest" ) {

            # First check if we support percentage requests
            my ( $can_onoff, $can_percent ) = checkSupportedStates($obj);
            if ($can_percent) {

                # Set the object to the nearest available percentage state
                set $obj &findNearestPercent( $obj,
                    $json_text->{"payload"}->{"percentageState"}->{"value"} );
                $response_data->{"header"}->{"name"} =
                  "SetPercentageConfirmation";
            }
            else {
                # This device is unable to do percent requests, generate an error
            }
        }
        elsif ( $reqname eq "IncrementPercentageRequest" ) {

            # First check if we support percentage requests
            my ( $can_onoff, $can_percent ) = checkSupportedStates($obj);
            if ($can_percent) {

                # Set the object to the nearest available percentage state
                set $obj &findNearestPercent( $obj,
                    "+"
                      . $json_text->{"payload"}->{"deltaPercentage"}->{"value"}
                );
                $response_data->{"header"}->{"name"} =
                  "IncrementPercentageConfirmation";
            }
            else {
                # This device is unable to do percent requests, generate an error
            }
        }
        elsif ( $reqname eq "DecrementPercentageRequest" ) {

            # First check if we support percentage requests
            my ( $can_onoff, $can_percent ) = checkSupportedStates($obj);
            if ($can_percent) {

                # Set the object to the nearest available percentage state
                set $obj &findNearestPercent( $obj,
                    "-"
                      . $json_text->{"payload"}->{"deltaPercentage"}->{"value"}
                );
                $response_data->{"header"}->{"name"} =
                  "DecrementPercentageConfirmation";
            }
            else {
                # This device is unable to do percent requests, generate an error
            }
        }
        elsif ( $reqname eq "SetTargetTemperatureRequest" ) {
        }
        elsif ( $reqname eq "IncrementTargetTemperatureRequest" ) {
        }
        elsif ( $reqname eq "DecrementTargetTemperatureRequest" ) {
        }
        else {
            # This doesn't match a name we were expecting, Generate an error
        }

        # Roll up the resoponse and send it back to Amazon
        my $response = "HTTP/1.0 200 OK\n";
        $response .= "Content-Type: application/json\n\n";
        $response .= encode_json $response_data;
        return $response;
    }
    elsif (
        $json_text->{"header"}->{"namespace"} eq "Alexa.ConnectedHome.System" )
    {
        if ( $json_text->{"header"}->{"name"} eq "HealthCheckRequest" ) {
            my $response_data = {
                header => {
                    messageId      => lc( $guid->as_string ),
                    name           => "HealthCheckResponse",
                    namespace      => "Alexa.ConnectedHome.System",
                    payloadVersion => "2"
                },
                payload => {
                    description => "The system is currently healthy",
                    isHealthy   => JSON::true
                }
            };

            # Roll up the resoponse and send it back to Amazon
            my $response = "HTTP/1.0 200 OK\n";
            $response .= "Content-Type: application/json\n\n";
            $response .= encode_json $response_data;
            return $response;
        }
        else {
            # Not sure what this is. Generate an error.
        }
    }
    else {
        # We have received something unexpected. Generate an error
    }
}
elsif ( $json_text->{"session"}->{"application"}->{"applicationId"} ) {
    if (
        $json_text->{"request"}->{"intent"}->{"slots"}->{"command"}->{"value"} )
    {
        my $cmd1 =
          &phrase_match1(
            $json_text->{"request"}->{"intent"}->{"slots"}->{"command"}
              ->{"value"} );
        &process_external_command( $cmd1, 1, 'alexa', 'speak' );
    }

    my $response_data = {
        version           => "Ver-$module_version",
        sessionAttributes => { blahblah => { something => "interesting" } },
        response          => {
            outputSpeech => {
                type => "PlainText",
                text => "string"
            },
            card => {
                type    => "Simple",
                title   => "string",
                content => "string"
            },
            reprompt => {
                outputSpeech => {
                    type => "PlainText",
                    text => ""
                }
            },
            shouldEndSession => JSON::true
        }
    };

    # Roll up the resoponse and send it back to Amazon
    my $response = "HTTP/1.0 200 OK\n";
    $response .= "Content-Type: application/json\n\n";
    $response .= encode_json $response_data;
    return $response;
}
else {
    # We have received something unexpected. Generate an error
}

# Find the nearest percentage value to that requested
sub findNearestPercent {
    my ( $obj, $percent ) = @_;
    if ( $obj->can('state_level') ) {
        if ( $percent =~ m/^[+-]/g ) {
            $percent += 100 + $obj->state_level();
            $percent = 100 if $percent >= 100;
            $percent = 0   if $percent <= 0;
        }
        $percent = sprintf( "%d", $percent );
        return $percent;
    }
    else {
        if ( $percent =~ m/^[+-]/g ) {
            my $current_percent = $obj->state();
            $current_percent = 100 if ( lc $current_percent eq 'on' );
            $current_percent = 0   if ( lc $current_percent eq 'off' );
            $current_percent =~ s/\%//g;
            $percent += $current_percent;
            $percent = 100 if $percent >= 100;
            $percent = 0   if $percent <= 0;
        }
        $percent = sprintf( "%d", $percent );
        my @states         = $obj->get_states();
        my @numeric_states = @states;
        for my $state (@numeric_states) {
            $state = 100 if ( lc $state eq 'on' );
            $state = 0   if ( lc $state eq 'off' );
            $state =~ s/\%//g;
        }
        my $itr = 0;
        foreach my $number (@numeric_states) {
            $itr++ and next if $percent >= $number;
        }
        return $states[ $itr - 1 ];
    }
}

# Check the supported states for the given object
sub checkSupportedStates {
    my ($obj)       = @_;
    my $can_onoff   = 0;
    my $can_percent = 0;
    my @states      = $obj->get_states();
    for my $state (@states) {
        if ( "on" eq lc($state) ) {
            $can_onoff = 1;
        }
        elsif ( "60\%" eq lc($state) ) {
            $can_percent = 1;
        }
    }
    if ( $obj->can('state_level') ) {
        $can_percent = 1;
    }
    return $can_onoff, $can_percent;
}

# Convert the device name into a friendly name
sub toFriendlyName {
    my ($in_name) = @_;
    $in_name =~ s/[_-]/ /g;
    $in_name =~ s/\$//g;
    $in_name =~ s/([0-9])/ $1/g;
    return $in_name;
}

# Die, outputting HTML error page
# If no $title, use global $errtitle, or else default title
sub HTMLdie {
    my ( $msg, $title ) = @_;
    $title = ( $title || "CGI Error" );
    print <<EOF ;
HTTP/1.0 500 OK
Content-Type: text/html

<html>
<head>
<title>$title</title>
</head>
<body>
<h1>$title</h1>
<h3>$msg</h3>
</body>
</html>
EOF

    return;
}

