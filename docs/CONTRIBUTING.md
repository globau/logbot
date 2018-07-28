The very high level install steps for a development setup are:
- clone the logbot repo
- copy `etc/_sample.yml` to `etc/_development.yml`
- edit `etc/_development.yml` and set all the values as required
- install [cpanm](https://metacpan.org/pod/distribution/App-cpanminus/bin/cpanm]) and [local::lib](https://metacpan.org/pod/local::lib) Perl libraries at a **system level**
- install [sass](https://sass-lang.com/install)
- install [uglifyjs](https://www.npmjs.com/package/uglify-js)
- install [js-beautify](https://www.npmjs.com/package/js-beautify)
- install [jshint](http://jshint.com/install)
- run `cpanm --verbose --local-lib ~/perl5/ --notest --installdeps . --with-develop`
- run `./dev-server` to start the web server
- run `./logbot-irc development` to start the irc server
- run `./logbot-consumer development` to start the message->database consumer

`dev-server` will automatically run `dev-make` when web resources are updated.
If `dev-server` is not running you must run `dev-make` manually.  Some changes
require a full rebuild of the resources with `dev-make -B`.

Run `dev-precommit` before creating any pull requests; this will auto-format
perl, sass, and javascript, report possible perl or javascript issues, and
run `dev-make -B`.
