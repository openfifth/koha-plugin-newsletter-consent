document.addEventListener("DOMContentLoaded", function(event) {
    $('#patronconsents form[action="/cgi-bin/koha/opac-patron-consent.pl"]').append('<div id="errorField" class="alert alert-warning d-none"></div>');
    $('#patronconsents form[action="/cgi-bin/koha/opac-patron-consent.pl"]').on('submit', function(event) {
        event.preventDefault();

        let borrowernumber        = $('input[name="borrowernumber"]').val();
        let check_gdpr_processing = ( $('input[name="check_GDPR_PROCESSING"]:checked').val() == '1' ) ? true :
                                    ( $('input[name="check_GDPR_PROCESSING"]:checked').val() == '0' ) ? false :
                                    undefined;
        let check_newsletter      = ( $('input[name="check_NEWSLETTER"]:checked').val() == '1' ) ? true :
                                    ( $('input[name="check_NEWSLETTER"]:checked').val() == '0' ) ? false :
                                    undefined;
        let body = {};

        if (check_gdpr_processing !== undefined) body.GDPR_PROCESSING = check_gdpr_processing;
        if (check_newsletter      !== undefined) body.NEWSLETTER      = check_newsletter;

        $.ajax({
            url:  '/api/v1/contrib/newsletterconsent/consents/' + borrowernumber,
            type: 'PUT',
            data: JSON.stringify(body),
            contentType: 'application/json; charset=utf-8',
            dataType: 'json'
        })
        .error(function(data) {
            var jqueryObj = $('#errorField');
            
            console.error(data.responseJSON.error);

            if (data.responseJSON) {
                jqueryObj.append('<p>Oh dear, that\'s gone horribly wrong! Please could you copy the block of code below, and email it to a librarian? It will help us improve our service. Thanks!<br /><pre>' + data.responseJSON.error + '</pre><br /><a href="">Refresh to see changes</a></p>');
            } else {
                jqueryObj.append('<p>Oh dear, that\'s gone horribly wrong! We haven\'t got much information other than the status code: <strong>' + data.status + '</strong>. Please could you email a librarian? It will help us improve our service. Thanks!<br /><a href="">Refresh to see changes</a></p>');
            }

            jqueryObj.removeClass('d-none');
        })
        .success(function() {
            $.ajax({
                url:  '/api/v1/contrib/newsletterconsent/consents/' + borrowernumber + '/sync_upstream',
                type: 'GET'
            })
            .error(function(data) {
                var jqueryObj = $('#errorField');

                console.error(data.responseJSON.error);

                if (data.responseJSON) {
                    if (data.responseJSON.error == 'no notice_email_address found') return window.location.reload();

                    jqueryObj.append('<p>Unable to sync consents. Your choice has been registered, but please get in touch with a librarian, and show them this error: <strong>' + data.responseJSON.error + '</strong>. This information will be needed to reflect your preferences effectively.</div><a href="">Refresh to see changes</a></p>');
                } else {
                    jqueryObj.append('<p>Unable to sync consents. Your choice has been registered, but please get in touch with a librarian, and show them this error: <strong>' + data.status + '</strong>. This information will be needed to reflect your preferences effectively.</div><a href="">Refresh to see changes</a></p>');
                }

                jqueryObj.removeClass('d-none');
            })
            .success(function() {
                return window.location.reload();
            });
        });

        return false;
    });
});
