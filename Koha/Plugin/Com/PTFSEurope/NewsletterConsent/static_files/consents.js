document.addEventListener("DOMContentLoaded", function(event) {
    // create hidden alert for possible errors
    $('form[action="/cgi-bin/koha/opac-patron-consent.pl"]').append('<div id="errorField" class="alert alert-warning d-none"></div>');

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
        .error(function(data) {
            var jqueryObj = $('#errorField');

            // two responses - one for JSON, and one for HTML
            if(data.responseJSON) {
                jqueryObj.append('<p>Oh dear, that\'s gone horribly wrong! Please could you copy the block of code below, and email it to a librarian? It will help us improve our service. Thanks!<br /><pre>' + data.responseJSON.error + '</pre><br /><a href="">Refresh to see changes</a></p>');
                jqueryObj.removeClass('d-none');
            } else {
                jqueryObj.append('<p>Oh dear, that\'s gone horribly wrong! We haven\'t got much information other than the status code: <strong>' + data.status + '</strong>. Please could you email a librarian? It will help us improve our service. Thanks!<br /><a href="">Refresh to see changes</a></p>');
                jqueryObj.removeClass('d-none');
            }
        })
        .success(function(data) {
            // now lets sync with the apis upstream
            $.ajax({
                url:  '/api/v1/contrib/newsletterconsent/consents/' + borrowernumber + '/sync_upstream',
                type: 'GET'
            })
            .error(function(data) {
                var jqueryObj = $('#errorField');

                jqueryObj.append('<p>Unable to sync consents. Your choice has been registered, but please get in touch with a librarian, and show them this error: <strong>' + data.responseJSON.error + '</strong>. This information will be needed to reflect your preferences effectively.</div><a href="">Refresh to see changes</a></p>');
            })
            .success(function(data) {
                // redirect
                return window.location.reload();
            });
        });

        // how'd we end up here?
        return false;
    });
});
