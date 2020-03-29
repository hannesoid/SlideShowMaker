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
    
    public typealias CompletedCombineBlock = (_ success: Bool, _ videoURL: URL?) -> Void
    public typealias Progress = (_ progress: Float) -> Void

    public var images: [UIImage?] = []
    public var contentMode = UIView.ContentMode.scaleAspectFit
    public var progress: Progress?
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
    fileprivate let fadeOffset: CGFloat = 30
    fileprivate let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    fileprivate let flags = CVPixelBufferLockFlags(rawValue: 0)
    
    fileprivate var exportTimeRate: Float = 0.0
    fileprivate var waitTranstionTimeRate: Float = 0
    fileprivate var transitionTimeRate: Float = 0
    fileprivate var writerTimeRate: Float = 0.9 {
        didSet {
            self.calculatorTimeRate()
        }
    }
    
    fileprivate var currentProgress: Float = 0.0 {
        didSet {
            self.progress?(self.currentProgress)
        }
    }

    public init(images: [UIImage]) {
        self.images = images
    }

    public func exportVideo(audio: AVURLAsset?, audioTimeRange: CMTimeRange?, completed: @escaping CompletedCombineBlock) -> SimplerVideoMaker {
        self.createDirectory()
        self.currentProgress = 0.0
        self.combineVideo { (success, url) in
            if success && url != nil {
                let video = AVURLAsset(url: url!)
                let item = VideoItem(video: video, audio: audio, audioTimeRange: audioTimeRange)
                self.videoExporter = VideoExporter(videoItem: item)
                self.videoExporter?.export()
                let timeRate = self.currentProgress
                self.videoExporter?.progressHandler = { progress in
                    DispatchQueue.main.async {
                        self.currentProgress = progress.isCompleted ? 1 : timeRate + /*(progress.progress ?? 1)*/ progress.progress * self.exportTimeRate
                        completed(progress.isCompleted, progress.resultURL)
                    }
                }
            } else {
                completed(false, nil)
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
        
        let hasSetDuration = self.videoDuration != nil
        self.timescale = hasSetDuration ? 100000 : 1
        let average = hasSetDuration ? Int(self.videoDuration! * self.timescale / self.images.count) : 2

        self.frameDuration = hasSetDuration ? average : 2
        self.transitionDuration = Int(self.frameDuration / 2)
        if hasSetDuration == false {
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
    
    fileprivate func combineVideo(completed: CompletedCombineBlock?) {
        self.makeImageFit()
        self.makeTransitionVideo(completed: completed)
    }

    fileprivate func makeTransitionVideo(completed: CompletedCombineBlock?) {
        guard self.images.isEmpty == false else {
            completed?(false, nil)
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
            completed?(false, nil)
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
            completed: { (success, url) in
                completed?(success, path)
        })
    }
    
    fileprivate func startCombine(videoWriter: AVAssetWriter,
               writerInput: AVAssetWriterInput,
               bufferAdapter: AVAssetWriterInputPixelBufferAdaptor,
               completed: CompletedCombineBlock?)
    {
        
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: CMTime.zero)
        
        var presentTime = CMTime(seconds: 0, preferredTimescale: Int32(self.timescale))
        var i = 0
        
        writerInput.requestMediaDataWhenReady(on: self.mediaInputQueue) { 
            while i < self.images.count {
                let duration = self.transitionDuration
                presentTime = CMTime(value: Int64(i * duration), timescale: Int32(self.timescale))
                
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
                    completed?(videoWriter.error == nil, nil)
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
                self.currentProgress += self.waitTranstionTimeRate
                presentTime = presentTime + CMTime(value: Int64(self.frameDuration - self.transitionDuration), timescale: Int32(self.timescale))
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

    fileprivate func calculatorTimeRate() {
        if self.images.isEmpty == false {
//            self.exportTimeRate = 1 - self.writerTimeRate
//            let frameTimeRate = self.writerTimeRate / Float(self.images.count)
//            self.waitTranstionTimeRate = frameTimeRate * 0.2
//            self.transitionTimeRate = frameTimeRate - self.waitTranstionTimeRate
        }
    }
    
    fileprivate  func createDirectory() {
        try? FileManager.default.createDirectory(at: VideoMaker.Constants.Path.movURL, withIntermediateDirectories: true, attributes: nil)
    }
}
