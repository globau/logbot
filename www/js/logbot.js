
// about

function init_about() {
  $(document).ready(function() {
    $('#about_channels .channel').hover(
      function() {
        $($(this).find('a')[0]).css('text-decoration', 'underline');
        $(this).find('.dates').show();
      },
      function() {
        $($(this).find('a')[0]).css('text-decoration', 'none');
        $(this).find('.dates').hide();
      }
    );
  });
}

// channels

function init_channels() {
  $('#channel_select').chosen();
}

function channel_changed() {
  var channel = $('#channel_select').val();
  window.location.href = '/?c=' + encodeURIComponent(channel);
}

// tabs

var tabs = new Array();
var tab_titles = new Array();
function add_tab(id) {
  tabs[tabs.length] = $('#' + id);
  tab_titles[tab_titles.length] = $('#' + id + '_title');
}

var current_channel = false;
function init_tabs(channel) {
  current_channel = channel;
  // browse
  Calendar.setup( { inputField: "start_date", ifFormat: "%e %b %Y", button: "start_date_cal" });
  Calendar.setup( { inputField: "end_date", ifFormat: "%e %b %Y", button: "end_date_cal" });
  Calendar.setup( { inputField: "search_start_date", ifFormat: "%e %b %Y", button: "search_start_date_cal" });
  Calendar.setup( { inputField: "search_end_date", ifFormat: "%e %b %Y", button: "search_end_date_cal" });
}

var about_loaded = false;
var plot = false;
function show_about_tab() {
  $('#events').addClass('hidden');

  if (about_loaded)
    return;
  about_loaded = true;
  if (!current_channel)
    return;

  $.ajax({
    url: 'index.cgi?a=json&r=channel_data&c=' + encodeURIComponent(current_channel)
  }).done(function(data) {
    if (data.last_updated) {
      $('#first_updated').text('Logging started ' + data.first_updated);
      $('#last_updated').text('Last updated ' + data.last_updated);
      $('#event_count').text(data.event_count);
    } else {
      $('#first_updated').text('No events');
      $('#last_updated').text('No events');
      $('#event_count').text('0');
    }
    $('#database_size').text(data.database_size);
  });

  $.ajax({
    url: 'index.cgi?a=json&r=channel_plot_hours&c=' + encodeURIComponent(current_channel),
    method: 'GET',
    dataType: 'json',
    success: function(series) {
      var hours_plot = $('#hours_plot');
      plot = $.plot(
        hours_plot,
        [ series ],
        {
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
          }
        }
      );

      var offset = plot.pointOffset({ x: current_hh + (current_mm / 60), y: plot.getAxes().yaxis.datamax });
      var height = plot.height() - (offset.top / 2);
      var style = 'position:absolute;height:' + height + 'px;top:' + offset.top + 'px;left:' + offset.left + 'px';
      hours_plot.append('<div id="hours_now" style="' + style + '">Now</div>');
    }
  });

  if ($('#nicks_plot').length == 0)
    return;

  $.ajax({
    url: 'index.cgi?a=json&r=channel_plot_nicks&c=' + encodeURIComponent(current_channel),
    method: 'GET',
    dataType: 'json',
    success: function(series) {
      var tbl = document.createElement('table');
      tbl.id = 'top_nicks';

      for (var i = 0, il = series.data.length; i < il; i++) {
        var row = series.data[i];
        var tr = document.createElement('tr');

        var cell = document.createElement('td');
        cell.className = 'top_nicks_nick';
        $(cell).text(row.nick);
        tr.appendChild(cell);

        cell = document.createElement('td');
        cell.className = 'top_nicks_count';
        $(cell).text(row.count).commify();
        tr.appendChild(cell);

        cell = document.createElement('td');
        cell.className = 'top_nicks_bar';
        cell.width = '100%';
        var bar = document.createElement('div');
        bar.style.background = '#f8e7b3';
        bar.style.color = '#f8e7b3';
        bar.style.width = (row.count / series.data[0].count * 100) + '%';
        $(bar).text('-');
        cell.appendChild(bar);
        tr.appendChild(cell);

        tbl.appendChild(tr);
      }
      $('#nicks_plot').text('');
      $('#nicks_plot').append(tbl);
    }
  });
}

function hide_about_tab() {
  $('#events').removeClass('hidden');
}

function switch_tab(id) {
  var idx = -1;
  for (var i = 0, l = tabs.length; i < l; i++) {
    if (tabs[i].attr('id') == id) {
      idx = i;
      break;
    }
  }
  if (idx == -1)
    return;

  for (var i = 0, l = tabs.length; i < l; i++) {
    if (i == idx) {
      tabs[i].removeClass('hidden');
      tab_titles[i].addClass('tab_selected');
    } else {
      tabs[i].addClass('hidden');
      tab_titles[i].removeClass('tab_selected');
    }
  }

  if (id == 'about_tab') {
    show_about_tab();
  } else {
    hide_about_tab();
    if (id == 'search_tab') {
      $('#query').focus();
    }
  }
}

// browse

var current_hilite_tr;
function hash_hilite() {
  if (!document.location.hash) return;
  var el = document.getElementById(document.location.hash.substr(1));
  if (!el) return;
  var tr = el.parentNode.parentNode;
  if (tr.nodeName != 'TR') return;
  if (current_hilite_tr)
    current_hilite_tr.className = '';
  current_hilite_tr = tr;
  current_hilite_tr.className = 'hilite';
}

function nav_date(ymd, date) {
  var el = $('#d' + ymd);
  if (el.length) {
    var bg = el.css('background-color');
    $('html, body').animate({ scrollTop: el.offset().top }, 250);
    el.animate({ backgroundColor: '#ffff9c' }, 250)
    window.setTimeout(function() {
      el.animate({ backgroundColor: bg }, 250)
    }, 250);
    return false;
  }
}

$(document).ready(function() {
  // switch tab
  if (document.location.hash) {
    switch_tab(document.location.hash.replace(/^#/, '') + '_tab');
  }

  hash_hilite();
});

// util

// https://github.com/hiroaki/jquery-commify
(function($){
    $.fn.commify = function(){
        var _commify = function (matched,cap){
                if( matched.match(/\..*\./) || matched.match(/,/) ){
                    return matched;
                }
                while(cap != (cap = cap.replace(/^(-?\d+)(\d{3})/, '$1,$2')));
                return cap;
            };

        $(this).each(function(){
            $(this).contents().each(function (){
                if( this.nodeType == 3 ){ // if text node
                    $(this).replaceWith( $(this).text().replace(/([0-9\.,]+)/g, _commify ) );
                }
            });
        });
        return this;
    };
})(jQuery);
