//
//  VideoMaker.swift
//  SlideShowMaker
//
//  Created by lcf on 27/07/2017.
//  Copyright © 2017 flow. All rights reserved.
//

import UIKit
import AVFoundation

public final class SimplerVideoMaker {
    
    public typealias ProgressHandler = (Result<URL, VideoError>?) -> Void

    public var images: [UIImage?] = []
    public var contentMode = UIView.ContentMode.scaleAspectFit
    public var quarity = CGInterpolationQuality.low
    
    // Video resolution
    public var size = CGSize(width: 640, height: 640)
    
    public var definition: CGFloat = 1
    
    /// Video duration
    public var videoDuration: Int?
    
    /// Every image duration, defualt 2
    public var frameDuration: Int = 2
    
    // Every image animation duration, default 1
    public var transitionDuration: Int = 1
    
    fileprivate var videoWriter: AVAssetWriter?
    fileprivate var videoExporter: VideoExporter?
    fileprivate var timescale = 10000000
    fileprivate let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    fileprivate let flags = CVPixelBufferLockFlags(rawValue: 0)


    public init(images: [UIImage]) {
        self.images = images
    }

    public func exportVideo(audio: AVURLAsset?, audioTimeRange: CMTimeRange?, updateHandler: @escaping ProgressHandler) -> SimplerVideoMaker {
        self.createDirectory()
        self.combineVideo { currentResult in
            switch currentResult {
            case .none:
                updateHandler(currentResult)
            case .some(.failure):
                updateHandler(currentResult)
            case .some(.success(let url)):
                let video = AVURLAsset(url: url)
                let item = VideoItem(video: video, audio: audio, audioTimeRange: audioTimeRange)
                self.videoExporter = VideoExporter(videoItem: item)
                self.videoExporter?.export()
                self.videoExporter?.progressHandler = { progress in
                    DispatchQueue.main.async {
                        switch progress.result {
                        case .none:
                            updateHandler(nil)
                        case .failure(let error):
                            updateHandler(.failure(.combiningVideoAudioFailed(error)))
                        case .success(let url):
                            updateHandler(.success(url))
                        }
                    }
                }
            }
        }
        return self
    }
    
    public func cancelExport() {
        self.videoWriter?.cancelWriting()
        self.videoExporter?.cancelExport()
    }
    
    fileprivate func calculateTime() {
        guard self.images.isEmpty == false else { return }

        if let videoDuration = self.videoDuration {
            self.timescale = 100000
            let average = Int(self.videoDuration! * self.timescale / self.images.count)
            self.frameDuration = average
            self.transitionDuration = Int(self.frameDuration / 2)
        } else {
            let hasSetDuration = self.videoDuration != nil
            self.timescale = 1
            self.frameDuration = 2
            self.transitionDuration = Int(self.frameDuration / 2)
            self.videoDuration = self.frameDuration * self.timescale * self.images.count

        }

    }
    
    fileprivate func makeImageFit() {
        var newImages = [UIImage?]()
        for image in self.images {
            if let image = image {
                
                let size = CGSize(width: self.size.width * definition, height: self.size.height * definition)
                let viewSize = size
                let view = UIView(frame: CGRect(origin: .zero, size: viewSize))
                view.backgroundColor = UIColor.black
                let imageView = UIImageView(image: image)
                imageView.contentMode = self.contentMode
                imageView.backgroundColor = UIColor.black
                imageView.frame = view.bounds
                view.addSubview(imageView)
                let newImage = UIImage(view: view)
                newImages.append(newImage)
            }
        }
        self.images = newImages
    }
    
    fileprivate func combineVideo(update: @escaping ProgressHandler) {
        self.makeImageFit()
        self.makeTransitionVideo(update: update)
    }

    fileprivate func makeTransitionVideo(update: @escaping ProgressHandler) {
        guard self.images.isEmpty == false else {
            update(.failure(.noImages))
            return
        }
        
        self.calculateTime()

        
        // video path
        let path = VideoMaker.Constants.Path.movURL.appendingPathComponent("transitionvideo.mov")
        print(path)
        self.deletePreviousTmpVideo(url: path)
        
        // writer
        self.videoWriter = try? AVAssetWriter(outputURL: path, fileType: .mov)
        
        guard let videoWriter = self.videoWriter else {
            print("Create video writer failed")
            update(.failure(.unknown))
            return
        }
        
        // input
        let videoSettings = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: self.size.width,
            AVVideoHeightKey: self.size.height
        ] as [String : Any]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriter.add(writerInput)
        
        // adapter
        let bufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)
        ]
        let bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: bufferAttributes)
        
        
        self.startCombine(
            videoWriter: videoWriter,
            writerInput: writerInput,
            bufferAdapter: bufferAdapter,
            path: path,
            completed: update)
    }
    
    fileprivate func startCombine(videoWriter: AVAssetWriter,
               writerInput: AVAssetWriterInput,
               bufferAdapter: AVAssetWriterInputPixelBufferAdaptor,
               path: URL,
               completed: @escaping ProgressHandler)
    {
        
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: CMTime.zero)
        
        var presentTime = CMTime(seconds: 0, preferredTimescale: Int32(self.timescale))
        var i = 0
        
        writerInput.requestMediaDataWhenReady(on: self.mediaInputQueue) { 
            while i < self.images.count {
//                let duration = self.transitionDuration
//                presentTime = CMTime(value: Int64(i * self.frameDuration), timescale: Int32(self.timescale))
                
                let presentImage = self.images[i]

                presentTime = self.appendImageBuffer(
                        presentImage: presentImage,
                        time: presentTime,
                        writerInput: writerInput,
                        bufferAdapter: bufferAdapter
                    )
                
                self.images[i] = nil
                i += 1
            }
            
            writerInput.markAsFinished()
            videoWriter.finishWriting {
                DispatchQueue.main.async {
                    print("finished")

                    print(videoWriter.error ?? "no error")
                    if let error = videoWriter.error {
                        completed(.failure(.systemError(error)))
                        return
                    } else {
                        completed(.success(path))
                    }

                }
            }
        }
    }
    
    fileprivate func appendImageBuffer(
                                  presentImage: UIImage?,
                                  time: CMTime,
                                  writerInput: AVAssetWriterInput,
                                  bufferAdapter: AVAssetWriterInputPixelBufferAdaptor) -> CMTime
    {
       
        var presentTime = time
        if let cgImage = presentImage?.cgImage {
            if let buffer = self.transitionPixelBuffer(fromImage: cgImage) {
                
                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                bufferAdapter.append(buffer, withPresentationTime: presentTime)
                presentTime = presentTime + CMTime(value: Int64(self.frameDuration), timescale: Int32(self.timescale))
            }
        }
        return presentTime
    }

    fileprivate func transitionPixelBuffer( fromImage: CGImage) -> CVPixelBuffer? {
        let transitionBuffer = autoreleasepool { () -> CVPixelBuffer? in
            guard let buffer = self.createBuffer() else { return nil }
            
            CVPixelBufferLockBaseAddress(buffer, self.flags)
            
            let pxdata = CVPixelBufferGetBaseAddress(buffer)
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            
            let context = CGContext(
                data: pxdata,
                width: Int(self.size.width),
                height: Int(self.size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: rgbColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
            context?.interpolationQuality = self.quarity
            
            self.performTransitionDrawing(cxt: context, from: fromImage)
            
            CVPixelBufferUnlockBaseAddress(buffer, self.flags)
            
            return buffer
        }
        return transitionBuffer
    }
    
    // Transition
    fileprivate func performTransitionDrawing(cxt: CGContext?, from: CGImage) {
        let fromFitSize = self.size

        let rect = CGRect(x: 0, y: 0, width: fromFitSize.width, height: fromFitSize.height)
        cxt?.concatenate(.identity)
        cxt?.draw(from, in: rect)
        return
    }

    
    fileprivate func createBuffer() -> CVPixelBuffer? {
        
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: NSNumber(value: true),
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: NSNumber(value: true)
        ]
        
        var pxBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary?,
            &pxBuffer
        )
        
        let success = status == kCVReturnSuccess && pxBuffer != nil
        return success ? pxBuffer : nil
    }
    
    fileprivate func deletePreviousTmpVideo(url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    fileprivate  func createDirectory() {
        try? FileManager.default.createDirectory(at: VideoMaker.Constants.Path.movURL, withIntermediateDirectories: true, attributes: nil)
    }

    public enum VideoError: Swift.Error {
        case noImages
        case unknown
        case systemError(Swift.Error)
        case combiningVideoAudioFailed(Swift.Error)
    }
}
