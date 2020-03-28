# SlideShowMaker

This was forked from https://github.com/cf-L/SlideShowMaker to adapt to a new code style and swift package manager.

## Requirements

## Installation

SlideShowMaker is available through Swift package manager

# Usage

```swift
let images = [#imageLiteral(resourceName: "img0"), #imageLiteral(resourceName: "img1"), #imageLiteral(resourceName: "img2"), #imageLiteral(resourceName: "img3")]
        
var audio: AVURLAsset?
var timeRange: CMTimeRange?
if let audioURL = Bundle.main.url(forResource: "Sound", withExtension: "mp3") {
	audio = AVURLAsset(url: audioURL)
	let audioDuration = CMTime(seconds: 30, preferredTimescale: audio!.duration.timescale)
    timeRange = CMTimeRange(start: kCMTimeZero, duration: audioDuration)
}
        
// OR: VideoMaker(images: images, movement: ImageMovement.fade)
let maker = VideoMaker(images: images, transition: ImageTransition.wipeMixed)
    
maker.contentMode = .scaleAspectFit
        
maker.exportVideo(audio: audio, audioTimeRange: timeRange, completed: { success, videoURL in
	if let url = videoURL {
		print(url)  // /Library/Mov/merge.mov
	}
}).progress = { progress in
	print(progress)
}
```





## Author

cf-L, linchangfeng@live.com

## License

SlideShowMaker is available under the MIT license. See the LICENSE file for more info.
