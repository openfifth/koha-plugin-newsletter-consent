package Koha::Plugin::Com::PTFSEurope::NewsletterConsent;

use Modern::Perl;

use base qw{ Koha::Plugins::Base };

use Mojo::JSON qw{ decode_json };

our $VERSION     = "0.0.1";
my $consent_type = "NEWSLETTER";
my $consent_info = {
    title => {
        'en' => qq{Newsletter},
    },
    description => {
        'en' => qq{We would like to send you our regular newsletters. Please signify if you would like these bulletins delivered to your inbox.},
    },
};

our $metadata = {
    name            => 'Newsletter Consent',
    author          => 'Jake Deery',
    date_authored   => '2024-10-22',
    date_updated    => '2024-10-25',
    minimum_version => '23.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'A plugin that will allow borrowers to opt in or out of receiving marketing messages',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();

    return $self;
}

sub install {
    my ( $self ) = shift;

    C4::Context->dbh->do(
        qq{INSERT IGNORE INTO plugin_methods (plugin_class, plugin_method) VALUES (?,?)},
            undef, ref $self, 'patron_consent_type'
    );

    return 1;
}

sub uninstall {
    my ( $self ) = @_;
    C4::Context->dbh->do(
        qq{DELETE FROM plugin_data WHERE plugin_class LIKE ?},
            undef, ref $self
    );

    C4::Context->dbh->do(
        qq{DELETE FROM plugin_methods WHERE plugin_class LIKE ?},
            undef, ref $self
    );

    return 1;
}

sub configure {
    my ( $self ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## lets fetch the data
        $template->param(
            enable_mailchimp  => $self->retrieve_data('enable_mailchimp') ? 1 : 0,
            mailchimp_api_key => $self->retrieve_data('mailchimp_api_key') || '',
            enable_eshot      => $self->retrieve_data('enable_eshot') ? 1 : 0,
            eshot_api_key     => $self->retrieve_data('eshot_api_key') || '',
        );
        $self->output_html( $template->output() );
    } else {
        ## lets save the data
        $self->store_data( {
            enable_mailchimp  => scalar $cgi->param('enable_mailchimp') ? 1 : 0,
            mailchimp_api_key => $cgi->param('mailchimp_api_key'),
            enable_eshot      => scalar $cgi->param('enable_eshot') ? 1 : 0,
            eshot_api_key     => $cgi->param('eshot_api_key'),
        } );
        $self->go_home();
    }
}

sub api_routes {
    my ( $self ) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;
    
    return 'newsletterconsent';
}

sub static_routes {
    my ( $self ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub opac_js {
    my ( $self ) = @_;

    return q{ <script src="/api/v1/contrib/newsletterconsent/static/static_files/consents.js"></script> };
}

sub patron_consent_type {
    my ( $self ) = @_;

    return [ $consent_type, $consent_info ],
}

1;
