package Koha::Plugin::Com::PTFSEurope::NewsletterConsent;

use Modern::Perl;

use base qw{ Koha::Plugins::Base };

use Koha::Libraries;
use Koha::Encryption;

use JSON;
use JSON::Validator::Schema::OpenAPIv2;

our $VERSION  = '1.0.3';
our $metadata = {
    name            => 'Newsletter Consent',
    author          => 'Jake Deery',
    date_authored   => '2024-10-22',
    date_updated    => '2024-12-20',
    minimum_version => '24.11.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'A plugin that will allow borrowers to opt in or out of receiving marketing messages',
};

our $consent_type = 'NEWSLETTER';
our $consent_info = {
    title       => { 'en' => qq{Newsletter}, },
    description => {
        'en' =>
            qq{We would like to send you our regular newsletters. Please signify if you would like these bulletins delivered to your inbox.},
    },
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
    my ($self) = shift;
    return 1;
}

sub uninstall {
    my ($self) = @_;
    return 1;
}

sub configure {
    my ($self) = @_;
    my $cgi    = $self->{'cgi'};
    my $json   = JSON->new->allow_nonref;

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );
        my $branches = Koha::Libraries->search();

        ## lets fetch the lists
        my @mailchimp_branches =
            ( $self->retrieve_data('mailchimp_branches') )
            ? split /\t/, $self->retrieve_data('mailchimp_branches')
            : undef;

        my @eshot_branches =
            ( $self->retrieve_data('eshot_branches') )
            ? split /\t/, $self->retrieve_data('eshot_branches')
            : undef;

        my @govdelivery_branches =
            ( $self->retrieve_data('govdelivery_branches') )
            ? split /\t/, $self->retrieve_data('govdelivery_branches')
            : undef;

        ## lets create some vars
        my $enable_mailchimp        = $self->retrieve_data('enable_mailchimp');
        my $mailchimp_api_key       = $self->retrieve_data('mailchimp_api_key');
        my $mailchimp_list_id       = $self->retrieve_data('mailchimp_list_id');
        my $enable_eshot            = $self->retrieve_data('enable_eshot');
        my $eshot_api_key           = $self->retrieve_data('eshot_api_key');
        my $eshot_group_id          = $self->retrieve_data('eshot_group_id');
        my $enable_govdelivery      = $self->retrieve_data('enable_govdelivery');
        my $govdelivery_account_id  = $self->retrieve_data('govdelivery_account_id');
        my $govdelivery_topic_id    = $self->retrieve_data('govdelivery_topic_id');
        my $govdelivery_user_login  = $self->retrieve_data('govdelivery_user_login');
        my $govdelivery_user_passwd = $self->retrieve_data('govdelivery_user_passwd');

        ## lets fetch the data
        $template->param(
            branches                => $branches,
            enable_mailchimp        => ($enable_mailchimp) ? 1 : 0,
            mailchimp_branches      => \@mailchimp_branches,
            mailchimp_api_key       => $self->decode_secret($mailchimp_api_key),
            mailchimp_list_id       => $mailchimp_list_id,
            enable_eshot            => ($enable_eshot) ? 1 : 0,
            eshot_branches          => \@eshot_branches,
            eshot_api_key           => $self->decode_secret($eshot_api_key),
            eshot_group_id          => $eshot_group_id,
            enable_govdelivery      => ($enable_govdelivery) ? 1 : 0,
            govdelivery_branches    => \@govdelivery_branches,
            govdelivery_account_id  => $govdelivery_account_id,
            govdelivery_topic_id    => $govdelivery_topic_id,
            govdelivery_user_login  => $govdelivery_user_login,
            govdelivery_user_passwd => $self->decode_secret($govdelivery_user_passwd),
        );
        $self->output_html( $template->output() );
    } else {
        ## lets prep the lists
        my $mailchimp_branches =
            ( $cgi->multi_param('mailchimp_branches') )
            ? join qq{\t}, $cgi->multi_param('mailchimp_branches')
            : undef;

        my $eshot_branches =
            ( $cgi->multi_param('eshot_branches') )
            ? join qq{\t}, $cgi->multi_param('eshot_branches')
            : undef;

        my $govdelivery_branches =
            ( $cgi->multi_param('govdelivery_branches') )
            ? join qq{\t}, $cgi->multi_param('govdelivery_branches')
            : undef;

        ## lets create some vars
        my $enable_mailchimp        = $cgi->param('enable_mailchimp');
        my $mailchimp_api_key       = $cgi->param('mailchimp_api_key');
        my $mailchimp_list_id       = $cgi->param('mailchimp_list_id');
        my $enable_eshot            = $cgi->param('enable_eshot');
        my $eshot_api_key           = $cgi->param('eshot_api_key');
        my $eshot_group_id          = $cgi->param('eshot_group_id');
        my $enable_govdelivery      = $cgi->param('enable_govdelivery');
        my $govdelivery_account_id  = $cgi->param('govdelivery_account_id');
        my $govdelivery_topic_id    = $cgi->param('govdelivery_topic_id');
        my $govdelivery_user_login  = $cgi->param('govdelivery_user_login');
        my $govdelivery_user_passwd = $cgi->param('govdelivery_user_passwd');

        ## lets save the data
        $self->store_data(
            {
                enable_mailchimp        => scalar $enable_mailchimp ? 1 : 0,
                mailchimp_branches      => $mailchimp_branches,
                mailchimp_api_key       => scalar $mailchimp_api_key ? $self->encode_secret($mailchimp_api_key) : undef,
                mailchimp_list_id       => $mailchimp_list_id,
                enable_eshot            => scalar $enable_eshot ? 1 : 0,
                eshot_branches          => $eshot_branches,
                eshot_api_key           => scalar $eshot_api_key ? $self->encode_secret($eshot_api_key) : undef,
                eshot_group_id          => $eshot_group_id,
                enable_govdelivery      => scalar $enable_govdelivery ? 1 : 0,
                govdelivery_branches    => $govdelivery_branches,
                govdelivery_account_id  => $govdelivery_account_id,
                govdelivery_topic_id    => $govdelivery_topic_id,
                govdelivery_user_login  => $govdelivery_user_login,
                govdelivery_user_passwd => scalar $govdelivery_user_passwd
                ? $self->encode_secret($govdelivery_user_passwd)
                : undef,
            }
        );
        $self->go_home();
    }
}

sub api_routes {
    my ($self) = @_;

    my $spec_file = $self->mbf_path('openapi.yaml');
    my $schema    = JSON::Validator::Schema::OpenAPIv2->new->resolve($spec_file);
    my $spec      = $schema->bundle->data;

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'newsletterconsent';
}

sub static_routes {
    my ($self) = @_;

    my $spec_file = $self->mbf_path('staticapi.yaml');
    my $schema    = JSON::Validator::Schema::OpenAPIv2->new->resolve($spec_file);
    my $spec      = $schema->bundle->data;

    return $spec;
}

sub opac_head {
    my ($self) = @_;

    return '<link rel="stylesheet" href="/api/v1/contrib/newsletterconsent/static/static_files/consents.css" />';
}

sub opac_js {
    my ($self) = @_;

    return '<script src="/api/v1/contrib/newsletterconsent/static/static_files/consents.js"></script>';
}

sub patron_consent_type {
    my ($self) = @_;

    return [ $consent_type, $consent_info ];
}

sub encode_secret {
    my ( $self, $secret ) = @_;

    return Koha::Encryption->new->encrypt_hex($secret)
        if ($secret);
}

sub decode_secret {
    my ( $self, $secret ) = @_;

    return Koha::Encryption->new->decrypt_hex($secret)
        if ($secret);
}

1;
