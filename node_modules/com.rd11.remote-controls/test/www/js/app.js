// Audio player
//
var my_media = null;
var mediaTimer = null;
var cover = "";

function updateMedia(position, error) {

    var artist = "Daft Punk";
    var title =  error ? error : "One More Time";
    var album = "Discovery";
    var duration = 100;

    var params = [artist, title, album, cover, duration, position];

    debugger;
    window.remoteControls.updateMetas(function(success){
        console.log(success);
    }, function(fail){
        console.log(fail);
    }, params);
}

function downloadImage(path, filename, callback) {
    var fileTransfer = new FileTransfer();
    var sPath = cordova.file.documentsDirectory;
    var target = sPath +"/img/"+ filename;
    target = target.replace(/[^a-zA-Z0-9:+./-]/g, '');
    fileTransfer.download( path, target, function(theFile) {
            //deferred.resolve({'type':200, 'path': "/" + subdir +"/" + filename});
            callback(null, theFile);
        },
        function(error) {
           //deferred.resolve({'type':304, 'error':error});
            callback(error);
        }
    );
}

function getNowPlaying(){
    window.remoteControls.getNowPlaying(function(success){
        console.log(success);
    }, function(fail){
        console.log(fail);
    });
}

function playAudio(src) {

    downloadImage("https://dl.dropboxusercontent.com/u/2755851/Sites/nymusictech/Orange-is-the-New-Black-Safe-Place.jpg", 'cover.jpg', function(err, fileEntry){
        cover = fileEntry.nativeURL;
    })
    // Create Media object from src
    my_media = new Media(src, onSuccess, onError);

    // Play audio
    my_media.play();

    // Update my_media position every second
    if (mediaTimer == null) {
        mediaTimer = setInterval(function() {
            // get my_media position
            my_media.getCurrentPosition(
                // success callback
                function(position) {
                    if (position > -1) {
                        updateMedia((position));
                    }
                },
                // error callback
                function(e) {
                    console.log("Error getting pos=" + e);
                    updateMedia(0, "Error: " + e);
                }
            );
        }, 1000);
    }
}

// Pause audio
//
function pauseAudio() {
    if (my_media) {
        my_media.pause();
    }
}

// Stop audio
//
function stopAudio() {
    if (my_media) {
        my_media.stop();
    }
    clearInterval(mediaTimer);
    mediaTimer = null;
}

// onSuccess Callback
//
function onSuccess() {
    console.log("playAudio():Audio Success");
}

// onError Callback
//
function onError(error) {
    alert('code: '    + error.code    + '\n' +
        'message: ' + error.message + '\n');
}