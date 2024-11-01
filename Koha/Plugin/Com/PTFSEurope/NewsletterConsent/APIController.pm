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
    my ( $self ) = @_;
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
    my ( $self ) = @_;
    my $c = shift->openapi->valid_input or return;

    my $patron    = $c->stash('koha.user');
    my $patron_id = $c->param('patron_id');

    ## block cross-patron usage
    unless ( $patron->borrowernumber == $patron_id ) {
        return $c->render(
            status  => 403,
            openapi => {
                error => "Checking other patron's consents is forbidden",
            },
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
    my ( $self ) = @_;
    my $c = shift->openapi->valid_input or return;

    my $patron   = $c->stash('koha.user');
    my $body     = $c->req->json;

    my $patron_id = $c->param('patron_id');

    ## block cross-patron usage
    unless ( $patron->borrowernumber == $patron_id ) {
        return $c->render(
            status  => 403,
            openapi => {
                error => "Changing other patron's consents is forbidden",
            },
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

=head3 get_sync_upstream

Controller function that handles passing a patron's consent to an api

=cut

sub get_sync_upstream {
    my ( $self ) = @_;
    my $c = shift->openapi->valid_input or return;

    my $patron                = $c->stash('koha.user');
    my $patron_id             = $c->param('patron_id');

    ## block cross-patron usage
    unless ( $patron->borrowernumber == $patron_id ) {
        return $c->render(
            status  => 403,
            openapi => {
                error => "Changing other patron's consents is forbidden",
            },
        );
    }

    return try {
        ## attempt to do the sync
        my $patron_sync = $self->process_sync_upstream( $patron );

        ## yipees ------
        ## yay! looks good
        return $c->render(
            status  => 200,
            openapi => $patron_sync,
        ) unless ( defined $patron_sync->{error} );

        ## uh-ohs ------
        ## no borrowernumber found or no notice_email_address found
        return $c->render(
            status  => 404,
            openapi => {
                error => $patron_sync->{error},
            },
        ) if( $patron_sync->{error} eq "no borrowernumber found" || $patron_sync->{error} eq "no notice_email_address found" );
    } catch {
        $c->unhandled_exception($_);
    }
}

=head3 process_sync_upstream

Method function that handles passing a patron's consent to an api

=cut

sub process_sync_upstream {
    my ( $self, $args ) = @_;
    my $plugin                = Koha::Plugin::Com::PTFSEurope::NewsletterConsent->new;
    my $patron                = $args; ## should be sent over from caller
    my $patron_consent_status = $patron->consent('NEWSLETTER')->given_on ? 1 : 0;

    ## check patron was sent
    return { error => 'no borrowernumber found' }
      unless ( defined $patron->borrowernumber );
    ## check patron has an email
    return { error => 'no notice_email_address found' }
      unless ( defined $patron->notice_email_address );

    ## determine if mailchimp & eshot are actually enabled
    my $enable_mailchimp = $plugin->retrieve_data('enable_mailchimp') ? 1 : 0;
    my $enable_eshot     = $plugin->retrieve_data('enable_eshot') ? 1 : 0;
    ## if neither are enabled, there is nothing to sync
    return {}
      unless ( $enable_mailchimp == 1 || $enable_eshot == 1 );
    
    ## righty, lets sync these consents -- mailchimp
    my $mailchimp_api_key = $plugin->retrieve_data('mailchimp_api_key') || '';

    ## righty, lets sync these consents -- eshot
    my $eshot_api_key = $plugin->retrieve_data('mailchimp_api_key') || '';

    return {
        patron_id       => $patron->borrowernumber,
        target_status   => ( $patron_consent_status ) ? Mojo::JSON->true : Mojo::JSON->false,
        mailchimp       => {
            enabled     => ( $enable_mailchimp ) ? Mojo::JSON->true : Mojo::JSON->false,
            sync_status => undef,
        },
        eshot          => {
            enabled     => ( $enable_eshot ) ? Mojo::JSON->true : Mojo::JSON->false,
            sync_status => undef,
        },
    };
}

1;
