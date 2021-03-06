$(document).ready(function() {
	
	$('.next, .prev').live('click', function(){
			$.getScript(this.href, function(){

			});
			return false
	})

	refreshIntervalId = slide()

	$('#pages li').live('click', function(){
		scroll($(this).index())
		clearInterval(refreshIntervalId);	
	})

})

function slide() {
		var i = 0
		var num_pages = 4
    id = setInterval(function () {
			i = (i + 1) % num_pages;
			scroll(i);
    }, 6000); // repeat forever, polling every 3 seconds
		return id
}

function scroll(i) {
		$('#pages li').removeClass('active')
		$($("#pages li")[i]).addClass('active')

		$('ul.text li').removeClass('active')
		$($("ul.text li")[i]).addClass('active')

		$('.iscreen').removeClass('active').hide()
		$($(".iscreen")[i]).fadeIn(2000).addClass('active')
}

function load_map(markers) {
  var mapOptions = {
		mapTypeControl: false,
		streetViewControl: false,
		mapTypeId: google.maps.MapTypeId.ROADMAP,
		maxZoom: 17,
		center: new google.maps.LatLng(0,0)
  }
  map = new google.maps.Map(document.getElementById("map_canvas_popup"),mapOptions);
	setMarkers(map, markers);
}

// Add markers to the map
function setMarkers(map, locations) {
  // Add markers to the map
  // Marker sizes are expressed as a Size of X,Y
  // where the origin of the image (0,0) is located
  // in the top left of the image.

  // Origins, anchor positions and coordinates of the marker
  // increase in the X direction to the right and in
  // the Y direction down.
  var image = new google.maps.MarkerImage('http://dish.fm/images/mapPointer.png',
      // This marker is 20 pixels wide by 32 pixels tall.
      new google.maps.Size(26, 42),
      // The origin for this image is 0,0.
      new google.maps.Point(0,0),
      // The anchor for this image is the base of the flagpole at 0,32.
      new google.maps.Point(0, 42));
  // var shadow = new google.maps.MarkerImage('http://code.google.com/intl/ru-RU/apis/maps/documentation/javascript/examples/images/beachflag_shadow.png',
      // The shadow image is larger in the horizontal dimension
      // while the position and offset are the same as for the main image.
      // new google.maps.Size(37, 32),
      // new google.maps.Point(0,0),
      // new google.maps.Point(0, 32));
      // Shapes define the clickable region of the icon.
      // The type defines an HTML <area> element 'poly' which
      // traces out a polygon as a series of X,Y points. The final
      // coordinate closes the poly by connecting to the first
      // coordinate.
  var shape = {
      coord: [1, 1, 1, 26, 21, 26, 21, 1],
      type: 'poly'
  };
	var bounds = new google.maps.LatLngBounds();
  for (var i = 0; i < locations.length; i++) {
    var beach = locations[i];
    var myLatLng = new google.maps.LatLng(beach[1], beach[2]);
    var marker = new google.maps.Marker({
        position: myLatLng,
        map: map,
        icon: image,
        shape: shape,
        title: beach[0],
        zIndex: beach[3]
    });
		bounds.extend(myLatLng);
  }
	map.fitBounds(bounds);
}

	// Google analytics

  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', 'UA-27015839-1']);
  _gaq.push(['_setDomainName', 'dish.fm']);
  _gaq.push(['_trackPageview']);

  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
  })();