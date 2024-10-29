package Koha::Plugin::Com::PTFSEurope::NewsletterConsent::APIController;

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Patrons;
use Koha::DateUtils qw{ dt_from_string };

=head1 NAME

Koha::Plugin::Com::PTFSEurope::NewsletterConsent::APIController

=head1 API

=head2 Methods

=head3 list

Controller function that handles listing available consents

=cut

sub list {
    my $c = shift->openapi->valid_input or return;

    my $consent_types = Koha::Patron::Consents->available_types;

    unless ($consent_types) {
        return $c->render(
            status  => 404,
            openapi => {
                error => "No consents defined.",
            },
        );
    }

    return $c->render(
        status  => 200,
        openapi => $consent_types,
    );
}

=head3 get

Controller function that handles getting a patron's consents

=cut

sub get {
    my $c      = shift->openapi->valid_input or return;
    my $patron = $c->stash('koha.user');
    my $body   = $c->req->json;

    my $patron_id = $c->param('patron_id');

    ## block cross-patron usage
    unless ( $patron->borrowernumber == $patron_id ) {
        return $c->render(
            status  => 403,
            openapi => {
                error => "Changing other patron's consents is forbidden"
            }
        );
    }

    return try {
        my $contents_rs = Koha::Patron::Consents->search({ borrowernumber => $patron->borrowernumber });
        ## regurgitate consents
        return $c->render(
            status  => 200,
            json    => $contents_rs,
        );
    } catch {
        $c->unhandled_exception($_);
    }
}

=head3 update

Controller function that handles updating a patron's consents

=cut

sub update {
    my $c      = shift->openapi->valid_input or return;
    my $patron = $c->stash('koha.user');
    my $body   = $c->req->json;

    my $patron_id = $c->param('patron_id');

    ## block cross-patron usage
    unless ( $patron->borrowernumber == $patron_id ) {
        return $c->render(
            status  => 403,
            openapi => {
                error => "Changing other patron's consents is forbidden"
            }
        );
    }

    my $consent_types = Koha::Patron::Consents->available_types;
    ## gather consent types
    my @consents;
    foreach my $consent_type ( sort keys %{$consent_types} ) {
        push @consents, $patron->consent($consent_type);
    }

    ## loop through found consent types
    foreach my $consent ( @consents ) {
        our $check = $body->{$consent->type} ? 1 : 0;
        
        ## skip missing consents
        next if not defined $body->{$consent->type};
        
        ## skip if unchanged
        next if $consent->given_on && $check || $consent->refused_on && !$check;
        
        ## store change\
        $consent->set({
            given_on   => $check ? dt_from_string() : undef,
            refused_on => $check ? undef : dt_from_string(),
            })->store;
    }

    return try {
        my $contents_rs = Koha::Patron::Consents->search({ borrowernumber => $patron->borrowernumber });
        ## regurgitate consents
        return $c->render(
            status  => 200,
            json    => $contents_rs,
        );
    } catch {
        $c->unhandled_exception($_);
    }
}

1;
