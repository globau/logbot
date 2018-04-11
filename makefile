.POSIX:
.SUFFIXES:

define sass
	sass --style compressed "web/$1.sass" "web/build/$2.min.css"
endef

define scss
	sass --style compressed "web/$1.scss" "web/build/$2.min.css"
endef

define css
	sass --style compressed "web/$1.css" "web/build/$2.min.css"
endef

define js
	uglifyjs "web/$1.js" --compress --mangle --output "web/build/$2.min.js"
endef

EXT_JS=web/build/jquery.min.js web/build/pikaday.min.js web/build/chosen.min.js web/build/flot.min.js
EXT_CSS=web/build/pikaday.min.css web/build/hind.min.css web/build/chosen.min.css
REDIR_EXT_JS=web/build/url.min.js

all: \
	web/public/static/logbot.min.js \
	web/public/static/logbot.min.css \
	web/public/static/redirect.min.js \
	web/public/static/redirect.min.css \
	web/build/inline-svg.updated \
	web/public/static/logbot-favicon.svg

clean:
	rm -f web/build/*.min.{js,css} web/public/static/*.min.{js,css} web/public/static/logbot-favicon.svg

.PHONY: all clean

# redirect

web/public/static/redirect.min.js: web/build/redirect.min.js $(REDIR_EXT_JS)
	cat $(REDIR_EXT_JS) web/build/redirect.min.js > web/public/static/redirect.min.js

web/build/redirect.min.js: web/redirect.js
	$(call js,redirect,redirect)

web/build/url.min.js: web/URL/url.js
	$(call js,URL/url,url)

web/public/static/redirect.min.css: web/build/redirect.min.css
	cp web/build/redirect.min.css web/public/static/redirect.min.css

web/build/redirect.min.css: web/redirect.sass
	$(call sass,redirect,redirect)

# javascript

web/public/static/logbot.min.js: web/build/logbot.min.js $(EXT_JS)
	cat $(EXT_JS) web/build/logbot.min.js > web/public/static/logbot.min.js

web/build/logbot.min.js: web/logbot.js
	$(call js,logbot,logbot)

web/build/jquery.min.js: web/jquery/jquery-3.2.1.min.js
	$(call js,jquery/jquery-3.2.1.min,jquery)

web/build/pikaday.min.js: web/pikaday/pikaday.js
	$(call js,pikaday/pikaday,pikaday)

web/build/chosen.min.js: web/chosen/chosen.jquery.js
	$(call js,chosen/chosen.jquery,chosen)

web/build/flot.min.js: web/flot/jquery.flot.js
	$(call js,flot/jquery.flot,flot)

# css

web/public/static/logbot.min.css: web/build/logbot.min.css $(EXT_CSS)
	perl -pi -e 'BEGIN { $$/ = undef } s#/\*.*?\*/##gs' web/build/*.min.css
	cat $(EXT_CSS) web/build/logbot.min.css > web/public/static/logbot.min.css

web/build/logbot.min.css: web/logbot.sass
	$(call sass,logbot,logbot)

web/build/pikaday.min.css: web/pikaday/pikaday.scss
	$(call scss,pikaday/pikaday,pikaday)

web/build/chosen.min.css: web/chosen/chosen.css
	$(call css,chosen/chosen,chosen)
	cp web/chosen/*.png web/public/static

web/build/hind.min.css: web/hind/hind.sass
	$(call sass,hind/hind,hind)
	cp web/hind/*.ttf web/public/static

# templates

web/build/inline-svg.updated: web/svg/*.svg web/svg/font-awesome/*.svg web/templates/*.html.ep web/templates/layouts/*.html.ep
	./dev-inline-svg --inline
	touch web/build/inline-svg.updated

# svg

web/public/static/logbot-favicon.svg: web/svg/favicon.svg
	cp web/svg/favicon.svg web/public/static/logbot-favicon.svg

