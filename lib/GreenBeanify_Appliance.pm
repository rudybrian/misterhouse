=head1 B<GreenBeanify_Appliance>

=head2 SYNOPSIS

Module for interfacing with a GreenBeanify-enabled GE appliance

=head2 CONFIGURATION

You need to define each appliance in your code or MHT as per the following example:

   CODE, require GreenBeanify_Appliance; #noloop
   CODE, $washing_machine = new GreenBeanify_Appliance('ZA12345G','Washing Machine'); #noloop
   CODE, $dryer = new GreenBeanify_Appliance('SA12345G','Dryer'); #noloop


The serial number is used to identify POST messages from the corresponding appliance. 


=head2 INHERITS

L<Generic_Item>

=head2 METHODS

=over

=cut

package GreenBeanify_Appliance;
use strict;

@GreenBeanify_Appliance::ISA = ('Generic_Item');

=item C<new()>

Instantiates a new object.

=cut

sub new {
	my ($class, $serial, $type) = @_;
	my $self = new Generic_Item();
	bless $self, $class;
	$$self{serial} = $serial;
	$$self{type} = $type;

	return $self;
}

=back

=head2 INI PARAMETERS

=head2 NOTES

=head2 AUTHOR

Brian Rudy <brudy@praecogito.com>

=head2 SEE ALSO

=head2 LICENSE

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut

1;
