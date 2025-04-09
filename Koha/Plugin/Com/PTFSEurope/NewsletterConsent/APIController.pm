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

use LWP::UserAgent;
use HTTP::Request;
use Mojo::JSON qw{ encode_json };
use MIME::Base64;

use Koha::Patrons;
use Koha::DateUtils qw{ dt_from_string };


=head1 NAME

Koha::Plugin::Com::PTFSEurope::NewsletterConsent::APIController

=cut

=head1 API

=head2 Methods

=head3 list

Controller function that handles listing available consents

=cut

sub list {
    my ( $self ) = @_;
    my $c        = shift->openapi->valid_input or return;

    my $consent_types = Koha::Patron::Consents->available_types;

    return $c->render(
        status  => 404,
        openapi => {
            error => 'No consents defined.',
        },
    ) unless( $consent_types );

    return $c->render(
        status  => 200,
        openapi => $consent_types,
    );
}


=head3 get

Controller function that handles getting a patron's consents

=cut

sub get {
    my ( $self, $args ) = @_;
    my $c               = shift->openapi->valid_input or return;

    my $patron = Koha::Patrons->find( $c->param('patron_id') );

    return $c->render_resource_not_found("Patron")
        unless $patron;

    return try {
        my $contents_rs = Koha::Patron::Consents->search( { borrowernumber => $patron->borrowernumber } );
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
    my $c        = shift->openapi->valid_input or return;

    my $patron = Koha::Patrons->find( $c->param('patron_id') );
    my $body   = $c->req->json;

    return $c->render_resource_not_found("Patron")
        unless $patron;

    my $consent_types = Koha::Patron::Consents->available_types;
    ## gather consent types
    my @consents;
    foreach my $consent_type ( sort keys %{$consent_types} ) {
        push @consents, $patron->consent($consent_type);
    }

    ## loop through found consent types
    foreach my $consent ( @consents ) {
        my $check = ( $body->{$consent->type} ) ? 1 : 0;
        
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
        my $contents_rs = Koha::Patron::Consents->search( { borrowernumber => $patron->borrowernumber } );
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
    my $c        = shift->openapi->valid_input or return;

    my $patron_id = $c->param('patron_id');
    my $patron    = Koha::Patrons->find( $patron_id );

    ## store patron in object
    $self->{sync_patron} = $patron;

    ## block cross-patron usage
    return $c->render(
        status  => 403,
        openapi => {
            error => 'Changing other patron\'s consents is forbidden',
        },
    ) unless( $patron->borrowernumber == $patron_id );

    return try {
        ## attempt to do the sync
        my $patron_sync = $self->process_sync_upstream();

        ## yipees ------
        ## yay! looks good
        return $c->render(
            status  => 200,
            openapi => $patron_sync,
        ) unless( defined $patron_sync->{error} );

        ## uh-ohs ------
        ## no borrowernumber found or no notice_email_address found
        return $c->render(
            status  => 404,
            openapi => {
                error => $patron_sync->{error},
            },
        ) if( $patron_sync->{error} eq 'no borrowernumber found' || $patron_sync->{error} eq 'no notice_email_address found' );

        ## everything else
        return $->render(
            status => 500,
            openapi => {
                error => $patron_sync->{error},
            },
        );
        return 
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
    my $patron                = $self->{sync_patron};
    my $patron_consent_status = $patron->consent('NEWSLETTER')->given_on;

    ## check patron was sent
    return { error => 'no borrowernumber found' }
        unless( defined $patron->borrowernumber );
    ## check patron has an email
    return { error => 'no notice_email_address found' }
        unless( defined $patron->notice_email_address );

    ## determine if mailchimp & eshot are actually enabled
    my $enable_mailchimp = $plugin->retrieve_data('enable_mailchimp');
    my $enable_eshot     = $plugin->retrieve_data('enable_eshot');
    ## if neither are enabled, there is nothing to sync
    return {} unless( $enable_mailchimp == 1 || $enable_eshot == 1 );

    ## prepare a user agent for the requests
    $self->{ua} = LWP::UserAgent->new;

    ## righty, lets sync these consents -- mailchimp
    my ($is_mailchimp_synced, $mailchimp_sync_msg) = $self->process_sync_mailchimp()
        if( $enable_mailchimp );

    ## righty, lets sync these consents -- eshot
    my ($is_eshot_synced, $eshot_sync_msg) = $self->process_sync_eshot()
        if( $enable_eshot );

    ## we're done
    return {
        patron_id         => $patron->borrowernumber,
        target_status     => ( $patron_consent_status ) ? Mojo::JSON->true : Mojo::JSON->false,
        mailchimp         => {
            enabled       => ( $enable_mailchimp ) ? Mojo::JSON->true : Mojo::JSON->false,
            sync_achieved => ( $is_mailchimp_synced ) ? Mojo::JSON->true : Mojo::JSON->false,
            message       => ( $mailchimp_sync_msg ) ? $mailchimp_sync_msg : "",
        },
        eshot             => {
            enabled       => ( $enable_eshot ) ? Mojo::JSON->true : Mojo::JSON->false,
            sync_achieved => ( $is_eshot_synced ) ? Mojo::JSON->true : Mojo::JSON->false,
            message       => ( $eshot_sync_msg ) ? $eshot_sync_msg : "",
        },
    };
}


=head3 process_sync_mailchimp

Method function that handles passing a patron's consent to mailchimp

=cut

sub process_sync_mailchimp {
    my ( $self, $args ) = @_;
    my $plugin                = Koha::Plugin::Com::PTFSEurope::NewsletterConsent->new;
    my $patron                = $self->{sync_patron};
    my $patron_consent_status = ( $patron->consent('NEWSLETTER')->given_on ) ? 'subscribed' : 'unsubscribed';
    my @enabled_branches      = split /\t/, $plugin->retrieve_data('eshot_branches') || undef;

    ## get api details
    my $mailchimp_api_key = $plugin->retrieve_data('mailchimp_api_key');
    my $mailchimp_list_id = $plugin->retrieve_data('mailchimp_list_id');

    ## if the key or list ids are missing, we can't continue
    return ( undef, 'missing_api_key_or_list_id' )
        unless( $mailchimp_api_key && $mailchimp_list_id );

    ## figure what to do if branch limitations are enabled
    my $len_enabled_branches   = @enabled_branches;
    my $count_enabled_branches = 0;

    for my $enabled_branch ( @enabled_branches ) {
        $count_enabled_branches++
            if ( $patron->branchcode eq $enabled_branch );
    }

    $count_enabled_branches++
      if ( $len_enabled_branches < 1 );

    ## act on above
    if( $count_enabled_branches < 1 ) {
        return ( undef, 'no_matching_branches' );
    }

    ## ascertain dc from api key
    $mailchimp_api_key =~ /\S+-(.+)/i;
    my $mailchimp_dc   =  $1;
    my $baseurl        =  qq{https://$mailchimp_dc.api.mailchimp.com/3.0};

    ## prep the body
    my $body = encode_json({
        members         => [
            {
                email_address => $patron->notice_email_address,
                status        => $patron_consent_status,
            },
        ],
        sync_tags       => Mojo::JSON->false,
        update_existing => Mojo::JSON->true,
    });

    ## begin request
    my $request = HTTP::Request->new( 'POST', $baseurl . '/lists/' . $mailchimp_list_id );

    $request->header( 'User-Agent'  => 'perl/"$^V' );
    $request->header( 'Content-Type'  => 'application/json' );
    $request->header( 'Authorization' => 'Basic ' . encode_base64( qq{anon:$mailchimp_api_key} ) );
    $request->content($body);

    my $response = $self->{ua}->request( $request );

    ## some basic logic about return code
    return ( 1, undef ) if( $response->{_rc} =~ /2[0-9]{2,}/i );
    return ( undef, "bad_response" );

}


=head3 process_sync_eshot

Method function that handles passing a patron's consent to eShot

=cut

sub process_sync_eshot {
    my ( $self, $args ) = @_;
    my $plugin                = Koha::Plugin::Com::PTFSEurope::NewsletterConsent->new;
    my $patron                = $self->{sync_patron};
    my $patron_consent_status = ( $patron->consent('NEWSLETTER')->given_on ) ? 'subscribed' : 'unsubscribed';
    my @enabled_branches      = split /\t/, $plugin->retrieve_data('eshot_branches') || undef;

    ## get api details
    my $eshot_api_key = $plugin->retrieve_data('eshot_api_key');

    ## if the key is missing, we can't continue
    return ( undef, 'missing_api_key' )
        unless( $eshot_api_key );

    ## figure what to do if branch limitations are enabled
    my $len_enabled_branches   = @enabled_branches;
    my $count_enabled_branches = 0;

    for my $enabled_branch ( @enabled_branches ) {
        $count_enabled_branches++
            if ( $patron->branchcode eq $enabled_branch );
    }

    $count_enabled_branches++
      if ( $len_enabled_branches < 1 );

    ## act on above
    if( $count_enabled_branches < 1 ) {
        return ( undef, 'no_matching_branches' );
    }

    ## change this to correct endpoint url
    my $baseurl = qq{https://rest-api.e-shot.net};

    ## prep the body
    my $body = encode_json({
        SubaccountID => 2,
        Email        => $patron->notice_email_address,
    });

    ## begin request
    my $request;
    $request = HTTP::Request->new( 'POST', $baseurl . '/Contacts/ResubscribeEmail' )
        if $patron_consent_status eq 'subscribed';
    $request = HTTP::Request->new( 'POST', $baseurl . '/Contacts/UnsubscribeEmail' )
        if $patron_consent_status eq 'unsubscribed';

    $request->header( 'User-Agent'  => 'perl/"$^V' );
    $request->header( 'Content-Type'  => 'application/json' );
    $request->header( 'Authorization' => 'Token ' . $eshot_api_key );
    $request->content($body);

    my $response = $self->{ua}->request( $request );

    ## some basic logic about return code
    return ( 1, undef ) if( $response->{_rc} =~ /2[0-9]{2,}/i );
    return ( undef, "bad_response" );

}

1;
