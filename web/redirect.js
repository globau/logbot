// need to redirect in javascript to keep the hash

// simple redirect; no line anchor
if (document.location.hash === '') {
    document.location = document.body.getAttribute('data-redirect-to');
}

var url = new URL(document.location);
var action = url.searchParams.get('a') || 'browse';
var start = url.searchParams.get('s');
var end = url.searchParams.get('e') || start;

// simple redirect if not channel browsing, or browsing for a single date
if ((action !== 'browse') || (start && (start === end))) {
    document.location = document.body.getAttribute('data-redirect-to') + document.location.hash;
}

// need to lookup the date from the comment id.  shift hash to query-string so
// server can lookup and reidrect.
url.searchParams.set('cid', url.hash.substring(1));
url.hash = '';
document.location = url.toString();
