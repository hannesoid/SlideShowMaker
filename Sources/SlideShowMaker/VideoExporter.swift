//
//  VideoMaker.swift
//  SlideShowMaker
//
//  Created by lcf on 26/07/2017.
//  Copyright © 2017 flow. All rights reserved.
//

import UIKit
import AVFoundation

public struct VideoItem {
    
    var video: AVURLAsset
    var audio: AVURLAsset?

    // Optionally specified audio time range
    var audioTimeRange: CMTimeRange?
    var durationBehaviour: DurationBehaviour = .maximumOfAudioAndVideo

    enum DurationBehaviour {
        case maximumOfAudioAndVideo
        case limitByVideo
        case limitByAudio
    }
}

public final class VideoExporter: NSObject {

    struct Configuration {
        var exportPreset: String = AVAssetExportPresetHighestQuality
        var temporaryURL: URL = VideoMaker.Constants.Path.movURL.appendingPathComponent("exported.mov") // use temp dir instead
    }

    struct Progress {
        var progress: Float
        var result: Result<URL, Swift.Error>?
        var isCompleted: Bool { return self.result != nil }
        var error: Swift.Error? { return self.result?.error }
        var resultURL: URL? { return self.result?.value }
    }

    /// Callback
    typealias ProgressHandler = (Progress) -> Void
    
    var progressHandler: ProgressHandler?
    let videoItem: VideoItem
    let configuration: Configuration
    var avAssetExportSession: AVAssetExportSession?

    init(videoItem: VideoItem, configuration: Configuration = .init()) {
        self.videoItem = videoItem
        self.configuration = configuration
    }
    
    public func export() {
        let videoItem = self.videoItem
        let composition = AVMutableComposition()
        do {
            guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }

            let videoTotalTimeRange = CMTimeRange(start: .zero, duration: videoItem.video.duration)
            try self.insertVideoTrack(ofVideoItem: videoItem, intoCompositionTrack: videoCompositionTrack, timeRange: videoTotalTimeRange)

            if videoItem.audio != nil {
                guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }

                try self.addAudio(ofVideoItem: videoItem, audioCompositionTrack: audioCompositionTrack)
            }
            self.merge(composition: composition, duration: videoTotalTimeRange.duration)
        } catch {
            self.progressHandler?(.init(progress: 0, result: .failure(error)))
        }
    }
    
    public func cancelExport() {
        if let session = self.avAssetExportSession, session.status == .exporting {
            session.cancelExport()
        }
    }
}

// MARK: - Edit

private extension VideoExporter {
    
    /// Add video and audio mutable composition tracks
    func prepareTracks(forAddingVideoItem videoItem: VideoItem, to composition: AVMutableComposition) throws -> (video: AVMutableCompositionTrack, audio: AVMutableCompositionTrack?) {
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }
        if videoItem.audio != nil {
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }

            return (video, audio)
        }
        return (video, nil)
    }
    
    /// Add the item's video track to the video composition
    func insertVideoTrack(ofVideoItem item: VideoItem, intoCompositionTrack videoCompositionTrack: AVMutableCompositionTrack, timeRange: CMTimeRange) throws {
        guard let videoTrack = item.video.tracks(withMediaType: .video).first else { return }

        do {
            try videoCompositionTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            throw ExportError.insertingVideoTrackFailed(error)
        }
    }
    
    /// Add audio
    func addAudio(ofVideoItem videoItem: VideoItem, audioCompositionTrack: AVMutableCompositionTrack) throws {
        guard let audio = videoItem.audio else { return }
        guard let audioSourceTrack = audio.tracks(withMediaType: .audio).first else { return }
        
        let audioStart = videoItem.audioTimeRange?.start ?? CMTime.zero
        let audioDuration = videoItem.audioTimeRange?.duration ?? audio.duration
        let audioTimescale = audio.duration.timescale
        let videoDuration = videoItem.video.duration


        if videoDuration.seconds <= audioDuration.seconds {
            let timeRange = CMTimeRange(start: audioStart, duration: videoDuration)
            try audioCompositionTrack.insertTimeRange(timeRange, of: audioSourceTrack, at: .zero)
            return
        }

        // video is longer than audio
        if videoDuration.seconds > audioDuration.seconds {
            let repeatCount = Int(videoDuration.seconds / audioDuration.seconds)
            let remainder = videoDuration.seconds.truncatingRemainder(dividingBy: audioDuration.seconds)
            let audioTotalTimeRange = CMTimeRange(start: audioStart, duration: audioDuration)
            
            for i in 0..<repeatCount {
                let start = CMTime(seconds: Double(i) * audioDuration.seconds, preferredTimescale: audioTimescale)

                try audioCompositionTrack.insertTimeRange(audioTotalTimeRange, of: audioSourceTrack, at: start)
            }
            
            if remainder > 0 {
                let startSeconds = Double(repeatCount) * audioDuration.seconds
                let start = CMTime(seconds: startSeconds, preferredTimescale: audioTimescale)
                let remainDuration = CMTime(seconds: remainder, preferredTimescale: audioTimescale)
                let remainTimeRange = CMTimeRange(start: audioStart, duration: remainDuration)
                
                print(startSeconds, start, remainDuration, remainTimeRange)
                try audioCompositionTrack.insertTimeRange(remainTimeRange, of: audioSourceTrack, at: start)
            }
        }
    }

    func merge(composition: AVMutableComposition, duration: CMTime) {
        let filename = "merge.mov"

        let path = VideoMaker.Constants.Path.movURL.appendingPathComponent(filename)
        print(path)
        self.deletePreviousTmpVideo(url: path)
        
        self.avAssetExportSession = AVAssetExportSession(asset: composition, presetName: self.configuration.exportPreset)
        if let exporter = self.avAssetExportSession {
            exporter.outputURL = path
            exporter.outputFileType = .mov
            exporter.shouldOptimizeForNetworkUse = true
            exporter.timeRange = CMTimeRange(start: CMTime.zero, duration: duration)
            
            let timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.readProgress), userInfo: nil, repeats: true)
            
            exporter.exportAsynchronously {
                timer.invalidate()
                
                if exporter.status == AVAssetExportSession.Status.failed {
                    self.avAssetExportSession = nil
                    print(#function, exporter.error ?? "unknow error")
                    self.progressHandler?(.init(progress: 0, result: .failure(ExportError.exporterFailed(exporter.error))))
                } else {
                    self.avAssetExportSession = nil
                    self.progressHandler?(.init(progress: 1.0, result: .success(path)))
                }
                print("export completed")
            }
        }
    }
}

// MARK: - Private

private extension VideoExporter {
    
    func deletePreviousTmpVideo(url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    @objc func readProgress() {
        if let exporter = self.avAssetExportSession {
            print(#function, exporter.progress)
            progressHandler?(.init(progress: exporter.progress, result: nil))
        }
    }
}

extension VideoExporter {

    enum ExportError: Swift.Error {

        case exporterFailed(Swift.Error?)
        case insertingVideoTrackFailed(Swift.Error)
        case failedPreparingTracks
        case incompleteAudioData
    }
}

private extension Result {

    var error: Failure? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }

    var value: Success? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }
}
