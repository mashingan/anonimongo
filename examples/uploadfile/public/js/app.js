function playvideo( filename ) {
  let ws = new WebSocket( "ws://localhost:3000/filename" );
  var v = document.querySelector( "#player" );
}

function submit_file() {
  let ws = new WebSocket( "ws://localhost:3000/ws-upload" );
  let filedom = document.querySelector( "#input-field" );
  ws.onmessage = function ( evnt ) {
    let data = evnt.data;
    console.log( data );
    let infonode = document.querySelector( "#upload-info" )
    let needToDisableInfonode = false
    if ( data === "ok" ) {
      needToDisableInfonode = true;
      infonode.style.display = "block"
      infonode.style.borderColor = "green"
      infonode.style.backgroundColor = "green"
      infonode.innerHTML = "Upload OK" 
    } else if ( data === "error" ) {
      needToDisableInfonode = true;
      infonode.style.display = "block"
      infonode.innerHTML = "Upload Failed"
    }

    if ( needToDisableInfonode ) {
      setTimeout( () => {
        let infonode = document.querySelector( "#upload-info" )
        if (!infonode) { return; }
        infonode.style.display = "none"
        infonode.style.borderColor = "green"
        infonode.style.backgroundColor = "green"
      }, 5000 )
    }
  }

  ws.onopen = function ( evnt ) {
    ws.send( filedom.files[ 0 ].name );
    ws.send( filedom.files[ 0 ].slice() );
    // ws.close();
    ws.send( "done" )
  }
  return true;
}