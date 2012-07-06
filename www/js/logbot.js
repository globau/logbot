
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
function load_about_tab() {
  if (about_loaded)
    return;
  about_loaded = true;
  if (!current_channel)
    return;

  $.ajax({
    url: '?a=json&r=channel_last_updated&c=' + encodeURIComponent(current_channel)
  }).done(function(data) {
    if (data.last_updated) {
      $('#last_updated').html('Last updated ' + data.last_updated);
    } else {
      $('#last_updated').html('No events');
    }
  });

  $.ajax({
    url: '?a=json&r=channel_database_size&c=' + encodeURIComponent(current_channel)
  }).done(function(data) {
    $('#database_size').html(data.database_size);
  });

  $.ajax({
    url: '?a=json&r=channel_event_count&c=' + encodeURIComponent(current_channel)
  }).done(function(data) {
    $('#event_count').html(data.event_count);
  });

  $.ajax({
    url: '?a=json&r=channel_plot_hours&c=' + encodeURIComponent(current_channel),
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

  if (id == 'about_tab')
    load_about_tab();
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

