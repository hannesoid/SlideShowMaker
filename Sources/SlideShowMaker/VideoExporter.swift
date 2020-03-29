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

}

public final class VideoExporter: NSObject {

    public struct Configuration {

        public var exportPreset: String
        public var temporaryURL: URL
        public var durationBehaviour: DurationBehaviour
        public var shortVideoBehaviour: ShortBehaviour
        public var shortAudioBehaviour: ShortBehaviour

        public enum DurationBehaviour {
            case maximumOfAudioAndVideo
            case durationOfVideo
            case durationOfAudio
            case minimumOfAudioAndVideo
        }

        public enum ShortBehaviour {
            case repeatUntilEnd
            case playOnce
        }

        public static var constantExportURL: URL {
            VideoMaker.Constants.Path.movURL.appendingPathComponent("exported.mov")
        }

        public init(exportPreset: String = AVAssetExportPresetHighestQuality,
                    temporaryURL: URL = Configuration.constantExportURL,
                    durationBehaviour: DurationBehaviour = .maximumOfAudioAndVideo,
                    shortVideoBehaviour: ShortBehaviour = .playOnce,
                    shortAudioBehaviour: ShortBehaviour = .repeatUntilEnd) {
            self.exportPreset = exportPreset
            self.temporaryURL = temporaryURL
            self.durationBehaviour = durationBehaviour
            self.shortVideoBehaviour = shortVideoBehaviour
            self.shortAudioBehaviour = shortAudioBehaviour
        }
    }

    public struct Progress {
        public var progress: Float
        public var result: Result<URL, Swift.Error>?
        public var isCompleted: Bool { return self.result != nil }
        public var error: Swift.Error? { return self.result?.error }
        public var resultURL: URL? { return self.result?.value }
    }

    /// Callback
    public typealias ProgressHandler = (Progress) -> Void

    private var avAssetExportSession: AVAssetExportSession?
    private let videoItem: VideoItem
    private let configuration: Configuration

    public var progressHandler: ProgressHandler?

    public init(videoItem: VideoItem, configuration: Configuration = .init()) {
        self.videoItem = videoItem
        self.configuration = configuration
    }

    public func export() {
        let videoItem = self.videoItem
        let composition = AVMutableComposition()
        do {
            let videoDuration = videoItem.video.duration
            var compositionDuration: CMTime {
                guard let audioTotalTimeDuration = videoItem.audioTimeRange?.duration ?? videoItem.audio?.duration else { return videoDuration }

                switch self.configuration.durationBehaviour {
                case .maximumOfAudioAndVideo:
                    return max(videoDuration, audioTotalTimeDuration)
                case .durationOfVideo:
                    return videoDuration
                case .durationOfAudio:
                    return audioTotalTimeDuration
                case .minimumOfAudioAndVideo:
                    return min(videoDuration, audioTotalTimeDuration)
                }
            }



            guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }
            guard let videoSourceTrack = videoItem.video.tracks(withMediaType: .video).first else { throw ExportError.videoTrackNotFound }
            let videoTotalTimeRange = CMTimeRange(start: .zero, duration: min(compositionDuration, videoDuration))

            try self.insert(sourceAsset: videoItem.video, sourceTrack: videoSourceTrack, sourceTimeRange: videoTotalTimeRange, compositionTrack: videoCompositionTrack, compositionDuration: compositionDuration, shortBehaviour: self.configuration.shortVideoBehaviour)


            if let audio = videoItem.audio {
                guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ExportError.failedPreparingTracks }

                if let audioSourceTrack = audio.tracks(withMediaType: .audio).first {
                    try self.insert(sourceAsset: audio, sourceTrack: audioSourceTrack, sourceTimeRange: videoItem.audioTimeRange, compositionTrack: audioCompositionTrack, compositionDuration: compositionDuration, shortBehaviour: self.configuration.shortAudioBehaviour)
                }
            }
            self.renderIntoFile(composition: composition, duration: compositionDuration, path: self.configuration.temporaryURL)
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

    /// Add audio
    func insert(sourceAsset: AVAsset, sourceTrack: AVAssetTrack, sourceTimeRange: CMTimeRange?, compositionTrack: AVMutableCompositionTrack, compositionDuration: CMTime, shortBehaviour: Configuration.ShortBehaviour) throws {
        let sourceStart = sourceTimeRange?.start ?? CMTime.zero
        let sourceDuration = sourceTimeRange?.duration ?? sourceAsset.duration
        let sourceTimescale = sourceAsset.duration.timescale

        switch (sourceDuration < compositionDuration, shortBehaviour) {
        case (true, .playOnce), (false, _):
            let timeRange = CMTimeRange(start: sourceStart, duration: compositionDuration)
            try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
        case (true, .repeatUntilEnd):
            // appliedDuration.seconds > audioDuration.seconds
            // video is longer than audio. repeat it?

            let repeatCount = Int(compositionDuration.seconds / sourceDuration.seconds)
            let remainder = compositionDuration.seconds.truncatingRemainder(dividingBy: sourceDuration.seconds)
            let audioTotalTimeRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

            for i in 0..<repeatCount {
                let start = CMTime(seconds: Double(i) * sourceDuration.seconds, preferredTimescale: sourceTimescale)

                try compositionTrack.insertTimeRange(audioTotalTimeRange, of: sourceTrack, at: start)
            }

            if remainder > 0 {
                let startSeconds = Double(repeatCount) * sourceDuration.seconds
                let start = CMTime(seconds: startSeconds, preferredTimescale: sourceTimescale)
                let remainDuration = CMTime(seconds: remainder, preferredTimescale: sourceTimescale)
                let remainTimeRange = CMTimeRange(start: sourceStart, duration: remainDuration)

                print(startSeconds, start, remainDuration, remainTimeRange)
                try compositionTrack.insertTimeRange(remainTimeRange, of: sourceTrack, at: start)
            }
        }
    }

    func renderIntoFile(composition: AVMutableComposition, duration: CMTime, path: URL) {
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
        case videoTrackNotFound
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
