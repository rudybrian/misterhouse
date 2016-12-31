
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
                if ( $object->can('state') ) {
                    my $can_onoff   = 0;
                    my $can_percent = 0;
                    my @states      = $object->get_states();
                    for my $state (@states) {
                        if ( "on" eq lc($state) ) {
                            $can_onoff = 1;
                        }
                        elsif ( "80\%" eq lc($state) ) {
                            $can_percent = 1;
                        }
                    }
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
        }
        elsif ( $reqname eq "IncrementPercentageRequest" ) {
        }
        elsif ( $reqname eq "DecrementPercentageRequest" ) {
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

