document.addEventListener("DOMContentLoaded", function(event) {
    // catch form and do stuff
    $('form[action="/cgi-bin/koha/opac-patron-consent.pl"]').on('submit', function(event) {
        // hold the form first
        event.preventDefault();

        // vars
        let borrowernumber        = $('input[name="borrowernumber"]').val();
        // the two vars below must be undefined if no change is intended
        let check_gdpr_processing = ( $('input[name="check_GDPR_PROCESSING"]:checked').val() == '1' ) ? true :
                                    ( $('input[name="check_GDPR_PROCESSING"]:checked').val() == '0' ) ? false : undefined;
        let check_newsletter      = ( $('input[name="check_NEWSLETTER"]:checked').val() == '1' ) ? true :
                                    ( $('input[name="check_NEWSLETTER"]:checked').val() == '0' ) ? false : undefined;
        // this is what we'll eventually send to the api
        let body = {};

        // build our body
        if(check_gdpr_processing !== undefined) body.GDPR_PROCESSING = check_gdpr_processing;
        if(check_newsletter      !== undefined) body.NEWSLETTER      = check_newsletter;

        // lets update the consents via the api
        $.ajax({
            url:  '/api/v1/contrib/newsletterconsent/consents/' + borrowernumber,
            type: 'PUT',
            data: JSON.stringify(body),
            contentType: 'application/json; charset=utf-8',
            dataType: 'json'
        })
        .done(function(data) {
            // now lets sync with the apis upstream
            $.ajax({
                url:  '/api/v1/contrib/newsletterconsent/consents/' + borrowernumber + '/sync_upstream',
                type: 'GET'
            })
            .done(function(data) {
                //return window.location.reload();
            });
        });

        // how'd we end up here?
        return false;
    });
});
