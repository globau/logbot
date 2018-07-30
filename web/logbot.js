$(function() {
    'use strict';
    var initialising = true;
    var current_channel = $('#channel').data('name');

    // cookie helper

    function set_cookie(name, value) {
        document.cookie = name + "=" + (value ? '1' : '0') + '; expires=Thu, 31 Dec 2037 23:59:58 GMT; path=/';
    }

    // always collapse the sidebar on tiny screens

    var is_tiny_screen = $('#not-tiny-screen:visible').length === 0;
    if (is_tiny_screen) {
        $('body').addClass('menu-c');
        set_cookie('menu-c', true);
    }

    // keyboard shortcuts

    $('body')
        .keyup(function(e) {
            // if a text input field has focus
            if (document.activeElement.nodeName === 'INPUT' &&
                document.activeElement.getAttribute('type') === 'text'
            ) {
                if (e.which === 27) {
                    // escape should clear field
                    $(document.activeElement).val('').keyup();
                }
                // and other shortcuts shouldn't work
                return;
            }

            if (e.which === 27) { // esc
                if ($('#settings-dialog:visible').length) {
                    // close settings
                    $('#settings-close').click();
                } else {
                    // toggle sidebar
                    $('#collapse-sidebar').click();
                }

            } else if (e.key === '#') {
                // # --> show channel list
                if (!$('body').hasClass('list')) {
                    $('#channel-list-action').click();
                }

            } else if (e.key === 'ArrowLeft') {
                // left-arrow --> previous date
                if (document.activeElement.nodeName !== 'BODY') {
                    return;
                }
                if ($('#skip-prev').length) {
                    $('#skip-prev')[0].click();
                } else if ($('#date-prev:not(.hidden)').length) {
                    $('#date-prev')[0].click();
                }

            } else if (e.key === 'ArrowRight') {
                // right-arrow --> next date
                if (document.activeElement.nodeName !== 'BODY') {
                    return;
                }
                if ($('#skip-next').length) {
                    $('#skip-next')[0].click();
                } else if ($('#date-next:not(.hidden)').length) {
                    $('#date-next')[0].click();
                }
            }
        });

    // collapse sidebar

    function set_sidebar_collapse_title() {
        $('#collapse-sidebar').attr('title',
            $('body').hasClass('menu-c') ?
            'Show Channels (Esc)' : 'Hide Channels (Esc)'
        );
    }

    $('#collapse-sidebar')
        .click(function() {
            $('body').toggleClass('menu-c');
            set_sidebar_collapse_title();
            set_cookie('menu-c', is_tiny_screen || $('body').hasClass('menu-c'));
        });

    set_sidebar_collapse_title();

    // highlight active channel
    if ($('body').hasClass('logs')) {
        var ch = current_channel.substring(1);
        var $ch = $('#ch-' + ch);
        if ($ch.length) {
            $ch.addClass('is-active');
        } else {
            // hidden channel, add to top of channel list
            var $li = $('#channel-menu li:first');
            if ($li.length) {
                $li = $li.clone();
                $li.find('a')
                    .addClass('is-active')
                    .attr('id', 'ch-' + ch)
                    .attr('href', '/' + ch)
                    .attr('title', $('#topic').text().trim())
                    .text(current_channel);
                $('#channel-menu').prepend($li);
            }
        }
    }

    // about

    $('#about')
        .click(function() {
            set_cookie('menu-c', false);
        });

    // nav - date

    function nav_to_date(ymd) {
        document.location = '/' + encodeURIComponent(current_channel.substring(1)) + '/' + ymd;
    }

    if (document.getElementById('date-icon')) {
        var nav_pika_config = {
            field: document.getElementById('date-icon'),
            maxDate: new Date(),
            onSelect: function(date) {
                var mm = (date.getMonth() + 1).toString();
                var dd = date.getDate().toString();
                var ymd = [date.getFullYear(), mm.length === 2 ? '' : '0', mm, dd.length === 2 ? '' : '0', dd].join('');
                nav_to_date(ymd);
            }
        };
        var ymd = $('#date').data('ymd') + '';
        if (ymd) {
            nav_pika_config.defaultDate = new Date(ymd.substr(0, 4), ymd.substr(4, 2) - 1, ymd.substr(6, 2));
            nav_pika_config.setDefaultDate = true;
        }
        new Pikaday(nav_pika_config);
    }

    // nav - last message
    $('#channel-end')
        .click(function(e) {
            e.preventDefault();
            $('html, body').animate({
                scrollTop: $(document).height()
            }, 250);
        });
    $(document).on('setting:hide-b', function(e, enabled) {
        if ($('.no-events:visible').length) {
            $('#channel-end')
                .attr('disabled', true)
                .attr('href', '');
        } else {
            $('#channel-end')
                .attr('disabled', undefined)
                .attr('href', '#end');
        }
    });

    // nav - network
    $('#current-network')
        .click(function(e) {
            e.preventDefault();
            if ($('#networks').hasClass('collapsed')) {
                $('#networks').removeClass('collapsed');
            } else {
                $('#networks').addClass('collapsed');
            }
        });

    // nav - topic

    function set_topic_visible(is_visible) {
        if (is_visible) {
            $('#channel-topic').attr('title', 'Hide Channel Topic');
            $('body').addClass('topic');
            $('#topic').show();
            set_cookie('topic', true);
        } else {
            $('#channel-topic').attr('title', 'Show Channel Topic');
            $('body').removeClass('topic');
            $('#topic').hide();
            set_cookie('topic', false);
        }
    }

    set_topic_visible($('body').hasClass('topic'));

    $('#channel-topic')
        .click(function(e) {
            e.preventDefault();
            set_topic_visible(!$('body').hasClass('topic'));
        });

    // search

    $('#search-submit')
        .click(function() {
            document.forms['nav-search'].submit();
        });

    if ($('body').hasClass('search')) {
        $('#search-nav')
            .prop('disabled', true);

        $('#search-query')
            .focus()
            .select();

        var search_pika_config = {
            maxDate: new Date(),
            keyboardInput: false,
            toString: function(d) {
                return [
                    d.getFullYear(),
                    ('0' + (d.getMonth() + 1)).slice(-2),
                    ('0' + d.getDate()).slice(-2)
                ].join('-');
            }
        };
        search_pika_config.field = document.getElementById('search-when-from');
        new Pikaday(search_pika_config);
        search_pika_config.field = document.getElementById('search-when-to');
        new Pikaday(search_pika_config);

        $(window).on('pageshow', function(e) {
            // replace name attributes that are cleared on submit
            $('#search-form input').each(function() {
                var $this = $(this);
                if ($this.data('name')) {
                    $this.attr('name', $this.data('name'));
                }
            });
        });
    }

    $('#search-channels')
        .chosen({
            no_results_text: 'No channels matching',
            placeholder_text_multiple: 'All channels',
            search_contains: true,
            display_selected_options: false
        });

    $('#search-channel-all, #search-channel-single, #search-channel-custom')
        .change(function() {
            if (!$(this).prop('checked')) {
                return;
            }
            if ($(this).attr('id') === 'search-channel-custom') {
                $('#search-channels').attr('disabled', false);
                $('#search-channel-multi').show();
                if (!initialising) {
                    $('#search-channels').trigger('chosen:open');
                }
            } else {
                $('#search-channel-multi').hide();
                $('#search-channels').attr('disabled', true);
            }
        })
        .change();

    $('#search-when-all, #search-when-recently, #search-when-custom')
        .change(function() {
            if (!$(this).prop('checked')) {
                return;
            }
            if ($(this).attr('id') === 'search-when-custom') {
                $('#search-when-from').attr('disabled', false);
                $('#search-when-to').attr('disabled', false);
                $('#search-when-range').show();
            } else {
                $('#search-when-range').hide();
                $('#search-when-from').attr('disabled', true);
                $('#search-when-to').attr('disabled', true);
            }
        })
        .change();

    $('#search-form-submit')
        .click(function() {
            $('#search-channel-all, #search-channel-custom, #search-when-recently, #search-using-ft')
                .each(function() {
                    var $this = $(this);
                    if ($this.prop('checked')) {
                        $this.data('name', $this.attr('name'));
                        $this.attr('name', '');
                    }
                });
            var $who = $('#search-who');
            if ($who.val() === '') {
                $who.data('name', $who.attr('name'));
                $who.attr('name', '');
            }
        });

    // channel list filter

    function update_filtered() {
        var filter = $('#filter').val().trim().toLowerCase();

        var filter_words = filter.split(/ +/);
        $('#channel-list li').each(function() {
            var $this = $(this);
            var this_text = $this.data('text');
            var match = true;
            for (var i = 0, l = filter_words.length; i < l; i++) {
                if (this_text.indexOf(filter_words[i]) === -1) {
                    match = false;
                    break;
                }
            }
            if (match) {
                $this.addClass('match');
            } else {
                $this.removeClass('match');
            }
        });

        var active_count = $('#active-channels li.match').length;
        var archived_count = $('#archived-channels li.match').length;

        if (active_count === 0) {
            $('#active-channels').hide();
        } else {
            $('#active-channels').show();
        }
        if (archived_count === 0) {
            $('#archived-channels').hide();
        } else {
            $('#archived-channels').show();
        }
        if (active_count === 0 && archived_count === 0) {
            $('#no-results').show();
        } else {
            $('#no-results').hide();
        }
    }

    function init_list() {
        $('#filter')
            .focus()
            .select()
            .keyup(update_filtered)
            .keypress(function(e) {
                if (e.which === 13) {
                    e.preventDefault();

                    var filter = $('#filter').val().trim().toLowerCase().replace(/^#/, '');
                    var exact_match = $('#active-channels a.channel[href="/' + CSS.escape(filter) + '"]');
                    if (exact_match.length) {
                        document.location = exact_match.attr('href');

                    } else if ($('#channel-list li.match').length === 1) {
                        document.location = $('#channel-list li.match a').attr('href');
                    }
                }
            });

        $(window).on('pageshow', function(e) {
            update_filtered();
            $('#filter').focus();
        });
    }

    $(document).on('list-preloaded', function() {
        $('#channel-list-action').on('click', function(e) {
            if (e.metaKey) {
                return;
            }
            e.preventDefault();
            e.stopPropagation();
            $('#main').html(localStorage.getItem('list-html'));
            $('body')
                .addClass('list')
                .removeClass('search');
            history.pushState({}, '', this.href);
            init_list();
        });
    });

    if ($('body').hasClass('list')) {
        init_list();
    } else {
        try {
            var list_id = $('#list-id').data('id');
            if (localStorage.getItem('list-id') !== list_id) {
                $.ajax({
                    url: '/_channels_body',
                    method: 'GET',
                    dataType: 'html',
                    success: function(html) {
                        localStorage.setItem('list-html', html);
                        localStorage.setItem('list-id', list_id);
                        $('body').trigger('list-preloaded');
                    }
                });
            } else {
                $('body').trigger('list-preloaded');
            }
        } catch (e) {
            console.error(e);
        }
    }

    // highlight

    function highlight($start, $end) {
        // clear highlights
        $('li.hl').removeClass('hl');

        var start_id = $start.attr('id');
        var end_id = $end.attr('id');

        // single row
        if (!end_id || start_id === end_id) {
            $start.addClass('hl');
            return [start_id];
        }

        // swap positions if end is before start
        if ($start.prevAll().filter('#' + end_id).length) {
            var tmp = end_id;
            end_id = start_id;
            start_id = tmp;
            tmp = $end;
            $start = $end;
            $end = tmp;
        }

        // iterate from start to end
        var id = start_id;
        var $el = $start;
        while (id !== end_id) {
            $el.addClass('hl');
            $el = $el.next();
            id = $el.attr('id');
            if (!id) {
                return [start_id];
            }
        }
        $el.addClass('hl');

        return [start_id, end_id];
    }

    function highlight_from_anchor(anchor) {
        var hl_hash = anchor.match('^#(c[0-9]+)(-(c[0-9]+))?$');
        if (!hl_hash) {
            return;
        }
        var $li = $('#' + hl_hash[1]);
        if ($li.length) {
            var range = highlight($li, $('#' + hl_hash[3]));
            var offset = $li.offset();
            $hl_anchor = $('#' + range[0]);
            $('html, body').animate({
                scrollTop: $li.offset().top - 40
            }, 50);
        }
    }

    var $hl_anchor = false;
    $('#logs .time')
        .click(function(e) {
            e.preventDefault();

            var $li = $(this).parent('li');
            var $current = $('li.hl');

            // if shift key is down highlight range
            if (e.shiftKey && $hl_anchor) {
                var range = highlight($hl_anchor, $li);
                var anchor = '#' + range[0] + (range[1] ? '-' + range[1] : '');
                history.pushState('', document.title, document.location.pathname + document.location.search + anchor);
                return;
            }

            if ($li.hasClass('hl')) {
                // deselect
                $current.removeClass('hl');
                $hl_anchor = false;
                history.pushState('', document.title, document.location.pathname + document.location.search);

            } else {
                // highlight just this row
                $current.removeClass('hl');
                $li.addClass('hl');
                $hl_anchor = $li;
                history.pushState('', document.title, document.location.pathname + document.location.search + '#' + $li.attr('id'));
            }
        });

    highlight_from_anchor(document.location.hash);

    $('#logs .text a, #logs .action a')
        .click(function(e) {
            if (this.hash && this.href.startsWith($('#logs').data('url')) && $(this.hash).length) {
                e.preventDefault();
                highlight_from_anchor(this.hash);
            }
        });

    // no-event messages

    $(document).on('setting:hide-b', function(e, enabled) {
        if (enabled) {
            $('#no-visible-events').show();
        } else {
            $('#no-visible-events').hide();
        }
    });

    // settings dialog

    function toggle_setting($setting, name) {
        var enabled = $('body')
            .toggleClass(name)
            .hasClass(name);
        set_cookie(name, enabled);
        $setting
            .find('input')
            .prop('checked', enabled);
        $(document).trigger('setting:' + name, [enabled]);
    }

    $('#settings')
        .click(function() {
            $('#settings-dialog').addClass('is-active');
        });

    $('#settings-dialog .modal-background, #settings-dialog .modal-close, #settings-close')
        .click(function(e) {
            e.preventDefault();
            $('#settings-dialog').removeClass('is-active');
        });

    $('.setting')
        .click(function() {
            var $this = $(this);
            toggle_setting($this, $this.data('setting'));
        });

    $('#settings-container .setting')
        .hover(
            function() {
                var $this = $(this);
                if (!$this.hasClass('not-implemented')) {
                    $(this).find('input').addClass('hover');
                }
            },
            function() {
                $(this).find('input').removeClass('hover');
            }
        );

    // relative time

    function time_ago(ss) {
        var mm = Math.round(ss / 60),
            hh = Math.round(mm / 60),
            dd = Math.round(hh / 24),
            mo = Math.round(dd / 30),
            yy = Math.round(mo / 12);
        if (ss < 10) return 'just now';
        if (ss < 45) return ss + ' seconds ago';
        if (ss < 90) return 'a minute ago';
        if (mm < 45) return mm + ' minutes ago';
        if (mm < 90) return 'an hour ago';
        if (hh < 24) return hh + ' hours ago';
        if (hh < 36) return 'a day ago';
        if (dd < 30) return dd + ' days ago';
        if (dd < 45) return 'a month ago';
        if (mo < 12) return mo + ' months ago';
        if (mo < 18) return 'a year ago';
        return yy + ' years ago';
    }

    function relative_timer() {
        var now = Math.floor(new Date().getTime() / 1000);
        $('.rel-time').each(function() {
            $(this).text(time_ago(now - $(this).data('time')));
        });
    }

    function handle_visibility_change() {
        if (document[hidden_event]) {
            relative_timer();
            if (!relative_timer_id) {
                relative_timer_id = window.setInterval(relative_timer, relative_timer_duration);
            }
        } else {
            relative_timer();
            if (!relative_timer_id) {
                relative_timer_id = window.setInterval(relative_timer, relative_timer_duration);
            }
        }
    }

    if ($('.rel-time').length) {
        var relative_timer_duration = 60000;
        var relative_timer_id = window.setInterval(relative_timer, relative_timer_duration);

        var hidden_event, visibility_change;

        if (typeof document.hidden !== "undefined") {
            hidden_event = "hidden";
            visibility_change = "visibilitychange";
        } else if (typeof document.webkitHidden !== "undefined") {
            hidden_event = "webkitHidden";
            visibility_change = "webkitvisibilitychange";
        }

        if (hidden_event) {
            document.addEventListener(visibility_change, handle_visibility_change);
        }
    }

    // channel stats

    function update_hours_plot() {
        $.ajax({
            url: base + 'hours',
            method: 'GET',
            dataType: 'json',
            success: function(series) {
                var $container = $('#hours-plot');

                $container
                    .text('')
                    .removeClass('loading');

                var plot = $.plot(
                    $container, [series], {
                        xaxis: {
                            ticks: 24,
                            tickFormatter: function(h) {
                                if (h == 0) return '12am';
                                if (h < 12) return h + 'am';
                                h -= 12;
                                if (h == 0) return '12pm';
                                return h + 'pm';
                            }
                        },
                        yaxis: {
                            show: false
                        },
                        grid: {
                            borderWidth: 0
                        },
                        colors: [$('#loc-container').css('background-color')]
                    }
                );

                var current_hh = $container.data('hh') * 1;
                var current_mm = $container.data('mm') * 1;

                var offset = plot.pointOffset({
                    x: current_hh + (current_mm / 60),
                    y: plot.getAxes().yaxis.datamax
                });
                var style = 'position:absolute;height:' + plot.height() + 'px;top:8px;left:' + offset.left + 'px';
                $container.append('<div id="hours-now" style="' + style + '">Now</div>');
            }
        });
    }

    if ($('body').hasClass('stats')) {
        var channel = $('#stats').data('channel');
        var base = channel ? 'stats/' : '_stats/';

        $.getJSON(base + 'meta', function(data) {
            $.each(data, function(name, value) {
                $('#' + name)
                    .text(value)
                    .removeClass('loading');
            });
            $('.loading-hide').removeClass('loading-hide');
        });

        update_hours_plot();
        $(document).on('setting:dark', update_hours_plot);

        if (channel) {
            $.ajax({
                url: base + 'nicks',
                method: 'GET',
                dataType: 'html',
                success: function(html) {
                    $('#nicks-plot')
                        .text('')
                        .removeClass('loading')
                        .html(html);
                }
            });
        }
    }

    $('.setting').each(function() {
        var $this = $(this);
        var name = $this.data('setting');
        $(document).trigger('setting:' + name, [$('body').hasClass(name)]);
    });

    initialising = false;
});
