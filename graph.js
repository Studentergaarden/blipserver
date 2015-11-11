//var loki = new Boolean(false);
var loki = new Boolean(true);
var str_url = '';
if (loki == true){
  str_url = '/ajax/';
}else{
  str_url = '';
}

labels = ["Fensmarksgadefløjen", "Arresøgadefløjen"];
idServer = [1,2];

/*global jQuery:false, $:false */
/*jslint whitespace:false, indent:4, onevar:false, browser:true */
$('.livegraph').each( function(){
  var idValue = $(this).attr('value');

  var options = {
    lines: { show: true },
    xaxis: { mode: 'time' },
    yaxis: {
      min: 0,
      tickFormatter: function (val, axis) {
        return val.toFixed(axis.tickDecimals) + 'W';
      }
    },
    colors: [ 'red' ],
    legend: {position: "ne"}
  },
      data,
      label1 = labels[idValue],
      graph = $(this),
      text = document.getElementById('text'+idServer[idValue]),
      timezoneOffset = (new Date()).getTimezoneOffset() * 60000,
      preparePoint,
      fillGraph,
      callHome,
	  initReq,
      pollError,
      initError,
      onDataReceived,
      textUsage = document.getElementById('textUsage'+idServer[idValue]),
      getUsage,
      onUsageRecieved;

  preparePoint = function (point) {
    var stamp = point[0],
        ms = point[1];

    stamp -= ms / 2;

    /* hack to show times in local time */
    stamp -= timezoneOffset;

    point[0] = stamp;
    point[1] = 1000/600 * 3600000 / ms * 4;
  };

  fillGraph = function (values) {
    for (i in values) {
      preparePoint(values[i]);
    }

    data = values;

    $.plot(graph, [ {label:label1, data:data}],
           options);
    setTimeout(callHome, 10);
  };

  callHome = function () {
    $.ajax({
      url: str_url+'blip/'+idServer[idValue],
      method: 'GET',
      dataType: 'json',
      success: onDataReceived,
	  error: pollError
    });
  };

  pollError = function() {
    setTimeout(callHome, 20000);
  };

  initReq = function() {
	$.ajax({
      /* last 20min */
      url: str_url+'last/'+idServer[idValue]+'/1200000',
      method: 'GET',
      dataType: 'json',
      success: fillGraph
	});
  };

  initError = function() {
    setTimeout(initReq, 20000);
  };
  onDataReceived = function (point) {
    var stamp = point[0],
        ms = point[1],
        time = new Date(stamp);

    preparePoint(point);
    data.push(point);

    stamp = point[0] - 1200000; /* 20min */
    while (data[0][0] < stamp) {
      data.shift();
    }

    text.innerHTML = time.toString() + ' - ' + ms + 'ms -> ' + point[1].toFixed(0) + 'W';
    $.plot(graph, [ {label:label1, data:data}],
           options);
    setTimeout(getUsage, 5000); /* only update usage every 5 sec */
    setTimeout(callHome, 10);
  };

  getUsage = function () {
    var time = 24 * 3600000; /* last 24 hours */
    $.ajax({
      url: str_url+'usage/'+idServer[idValue]+'/'+time,
      method: 'GET',
      dataType: 'json',
      success: onUsageRecieved
    });
  };

  onUsageRecieved = function (point) {
    /* receive the number of blips during the last xx hours */
    var blips = point[0],
        usage = blips/600 * 4,
        price = usage*2;
    usage = usage.toFixed(2);
    price = price.toFixed(2);
    textUsage.innerHTML = '<b>Usage last 24 hours</b>: ' + usage  + ' kWh ' + '-> <b>price: </b>' + price + 'kr/day';
  };

  initReq();
  /* get usage immediately */
  // getUsage();
});


$('.weekgraph').each( function(){
  var idValue = $(this).attr('value');

  var endTime = (new Date()).getTime();
  startTime = endTime - 86400*7*1000;
  startTimeMonth = endTime - 86400*30*1000;
  startTimeYear = endTime - 86400*365*1000;

  var options = {
    lines: { show: true },
    xaxis: { mode: 'time' },
    yaxis: {
	  // skal nok være Date()
//	  panRange: [startTime, endTime],
      tickFormatter: function (val, axis) {
        return val.toFixed(axis.tickDecimals) + 'Wh';
      }
    },
    grid: {
      hoverable: true
    },
    colors: [ 'red' ],
    selection:{
      mode: "x"
    },
    pan: {
      interactive: true
    },
	zoom: {
	  interactive: false // standard
	}
  },
	  plot,
      data,
      label1 = labels[idValue],
      graph = $(this),//$('#graph'),
      timezoneOffset = (new Date()).getTimezoneOffset() * 60000,
      textUsage = document.getElementById('textWeekUsage'+idServer[idValue]),
      getUsage,
      onUsageRecieved,
      fillGraph;

  formatDate = function ( input ){
    var options = {
      month: "short",
      day: "numeric", hour: "2-digit", minute: "2-digit"
    };
    // LocaleTimeString uses the timezone. Input has already been
    // modified with timezone, thus we remove it again
    var d = new Date(input + timezoneOffset);
    return d.toLocaleTimeString("da-dk",options);
  };

  // tooltip - show value of points
  $("<div id='tooltip'></div>").css({
    position: "absolute",
    display: "none",
    border: "1px solid #fdd",
    padding: "2px",
    "background-color": "#fee",
    opacity: 0.80
  }).appendTo("body");
  graph.bind("plothover", function (event, pos, item) {
    if (item) {
      var x = item.datapoint[0],
          y = item.datapoint[1].toFixed(0);
      $("#tooltip").html(formatDate(x) + ': ' + y + ' Wh')
        .css({top: item.pageY+5, left: item.pageX+5})
        .fadeIn(200);
    } else {
      $("#tooltip").hide();
    }
  });

  // zoom to selected
  graph.bind("plotselected", function (event, ranges) {
    $.each(plot.getXAxes(), function(_, axis) {
      var opts = axis.options;
      opts.min = ranges.xaxis.from;
      opts.max = ranges.xaxis.to;
    });
    plot.setupGrid();
    plot.draw();
    plot.clearSelection();

  });
  // reset zoom
  graph.dblclick(function () {
	plot = $.plot(graph, [ {label:label1, data:data} ], options);
  });

  fillGraph = function (values) {
    newValues = [ ];
    for (i = 0; i < values.length - 1; i++) {
      newValues.push([values[i][0] - timezoneOffset,
                      values[i][2] * 1000/600 * 4]);
      newValues.push([values[i+1][0] - timezoneOffset,
                      values[i][2] * 1000/600 * 4]);
    }
    data = newValues;

    plot = $.plot(graph, [ {label:label1, data:data} ], options);
	// plot.getOptions().selection.mode = null;
  };



  getUsage = function () {
    var time = 7* 24 * 3600000; /* last week */
    $.ajax({
      url: str_url+'usage/'+idServer[idValue]+'/'+time,
      method: 'GET',
      dataType: 'json',
      success: onUsageRecieved
    });
  };

  onUsageRecieved = function (point) {
    /* receive the number of blips during the last xx hours */
    var blips = point[0],
        usage = blips/600 * 4,
        price = usage*2;
    usage = usage.toFixed(2);
    price = price.toFixed(2);
    textUsage.innerHTML = '<b>Usage last week</b>: ' + usage  + ' kWh ' + '-> <b>price: </b>' + price + 'kr/week';
  };


  /* get usage immediately */
  getUsage();
  $.ajax({
    url: str_url+'hourly/' + idServer[idValue] + '/' + startTime + '/' + endTime,
    method: 'GET',
    dataType: 'json',
    success: fillGraph
  });
});


$('.monthgraph').each( function(){
  var idValue = $(this).attr('value');

  var endTime = (new Date()).getTime();
  startTime = endTime - 3600000*24*30*3;
  interval = 3600000*24;
  count = 100;
  startTimeMonth = endTime - 86400*30*1000;
  startTimeYear = endTime - 86400*365*1000;

  var options = {
    lines: { show: true },
    xaxis: { mode: 'time',
			 timeformat: "%b %e(%a)",
			 dayNames: ["søn","man","tir","ons","tor","fre","lør"]},
    yaxis: {
      tickFormatter: function (val, axis) {
        return val.toFixed(axis.tickDecimals)/1000 + ' kWh';
      }
    },
    grid: {
      hoverable: true
    },
    colors: [ 'red' ],
    selection:{
      mode: "x"
    },
    pan: {
      interactive: true
    },
	zoom: {
	  interactive: false // standard
	}
  },
	  plot,
      data,
      label1 = labels[idValue],
      graph = $(this),//$('#graph'),
      timezoneOffset = (new Date()).getTimezoneOffset() * 60000,
      textUsage = document.getElementById('textWeekUsage'+idServer[idValue]),
      getUsage,
      onUsageRecieved,
      fillGraph;

  formatDate = function ( input ){
    var options = {
      month: "short",
      day: "numeric", hour: "2-digit", minute: "2-digit"
    };
    // LocaleTimeString uses the timezone. Input has already been
    // modified with timezone, thus we remove it again
    var d = new Date(input + timezoneOffset);
    return d.toLocaleTimeString("da-dk",options);
  };

  // tooltip - show value of points
  $("<div id='tooltip'></div>").css({
    position: "absolute",
    display: "none",
    border: "1px solid #fdd",
    padding: "2px",
    "background-color": "#fee",
    opacity: 0.80
  }).appendTo("body");
  graph.bind("plothover", function (event, pos, item) {
    if (item) {
      var x = item.datapoint[0],
          y = item.datapoint[1].toFixed(0);
      $("#tooltip").html(formatDate(x) + ': ' + y + ' Wh')
        .css({top: item.pageY+5, left: item.pageX+5})
        .fadeIn(200);
    } else {
      $("#tooltip").hide();
    }
  });

  // zoom to selected
  graph.bind("plotselected", function (event, ranges) {
    $.each(plot.getXAxes(), function(_, axis) {
      var opts = axis.options;
      opts.min = ranges.xaxis.from;
      opts.max = ranges.xaxis.to;
    });
    plot.setupGrid();
    plot.draw();
    plot.clearSelection();

  });
  // reset zoom
  graph.dblclick(function () {
	plot = $.plot(graph, [ {label:label1, data:data} ], options);
  });

  fillGraph = function (values) {
    newValues = [ ];
    for (i = 0; i < values.length - 1; i++) {
      newValues.push([values[i][0] - timezoneOffset + startTime,
                      values[i][1]* 1000/600 * 4]); // in kWh
      newValues.push([values[i+1][0] - timezoneOffset + startTime,
                      values[i][1]* 1000/600 * 4]);
    }
    data = newValues;

    plot = $.plot(graph, [ {label:label1, data:data} ], options);
	// plot.getOptions().selection.mode = null;
  };



  getUsage = function () {
    var time = 7* 24 * 3600000; /* last week */
    $.ajax({
      url: str_url+'usage/'+idServer[idValue]+'/'+time,
      method: 'GET',
      dataType: 'json',
      success: onUsageRecieved
    });
  };

  onUsageRecieved = function (point) {
    /* receive the number of blips during the last xx hours */
    var blips = point[0],
        usage = blips/600 * 4,
        price = usage*2;
    usage = usage.toFixed(2);
    price = price.toFixed(2);
    textUsage.innerHTML = '<b>Usage last week</b>: ' + usage  + ' kWh ' + '-> <b>price: </b>' + price + 'kr/week';
  };


  /* get usage immediately */
  getUsage();
  $.ajax({
    url: str_url+'aggregate_hourly/' + idServer[idValue] + '/' + startTime + '/' + interval + '/' + count,
    method: 'GET',
    dataType: 'json',
    success: fillGraph
  });
});
