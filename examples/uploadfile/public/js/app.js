function playvideo( filename ) {
  let ws = new WebSocket( "ws://localhost:3000/filename" );
  var v = document.querySelector( "#player" );
}

function submit_file() {
  let ws = new WebSocket( "ws://localhost:3000/ws-upload" );
  let filedom = document.querySelector( "#input-field" );
  ws.onmessage = function ( evnt ) {
    console.log( evnt.data );
  }
  ws.onopen = function ( evnt ) {
    ws.send( filedom.files[ 0 ].name );
    ws.send( filedom.files[ 0 ].slice() );
    ws.close();
  }
  return true;
}