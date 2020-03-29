//
//  ViewController.swift
//  SlideShowMakerExample
//
//  Created by Hannes Oud on 28.03.20.
//  Copyright © 2020 Hannes Oud EPU. All rights reserved.
//

import UIKit
import AVFoundation
import SlideShowMaker

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.makeVideo()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }


    func makeVideo() {

        let images = [#imageLiteral(resourceName: "img0"), #imageLiteral(resourceName: "img1"), #imageLiteral(resourceName: "img2"), #imageLiteral(resourceName: "img3")]

        var audio: AVURLAsset?
        var timeRange: CMTimeRange?
        if let audioURL = Bundle.main.url(forResource: "Sound", withExtension: "mp3") {
            audio = AVURLAsset(url: audioURL)
            let audioDuration = CMTime(seconds: 30, preferredTimescale: audio!.duration.timescale)
            timeRange = CMTimeRange(start: CMTime.zero, duration: audioDuration)
        }

        // OR: VideoMaker(images: images, movement: ImageMovement.fade)
        let maker = SimplerVideoMaker(images: images)

        maker.contentMode = .scaleAspectFit

        maker.exportVideo(audio: audio, audioTimeRange: timeRange, completed: { success, videoURL in

            if let url = videoURL {
                print(url)  // /Library/Mov/merge.mov
            }

        }).progress = { progress in
            print(progress)
        }
    }


}

