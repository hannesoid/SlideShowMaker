//
//  Enum.swift
//  SlideShowMaker
//
//  Created by lcf on 28/07/2017.
//  Copyright © 2017 flow. All rights reserved.
//

public enum ImageTransition: CaseIterable {
    case none
    case crossFade
    case crossFadeLong
    case crossFadeUp
    case crossFadeDown
    case wipeRight
    case wipeLeft
    case wipeUp
    case wipeDown
    case wipeMixed
    case slideLeft
    case slideRight
    case slideUp
    case slideDown
    case slideMixed
    case pushRight
    case pushLeft
    case pushUp
    case pushDown
    case pushMixed
    
    static var count: Int {
        return ImageTransition.allCases.count
    }

    var next: ImageTransition {
        switch self {
        case .wipeMixed, .wipeLeft, .wipeRight, .wipeUp, .wipeDown:
            return self.wipeNext
        case .slideMixed, .slideLeft, .slideRight, .slideUp, .slideDown:
            return self.slideNext
        case .pushMixed, .pushLeft, .pushRight, .pushUp, .pushDown:
            return self.pushNext
        case .none, .crossFade, .crossFadeLong, .crossFadeUp, .crossFadeDown:
            return self
        }
    }

    var wipeNext: ImageTransition {
        switch self {
        case .wipeMixed:
            return .wipeRight
        case .wipeRight:
            return .wipeLeft
        case .wipeLeft:
            return .wipeUp
        case .wipeUp:
            return .wipeDown
        case .wipeDown:
            return .wipeRight
        default:
            return self
        }
    }
    
    var slideNext: ImageTransition {
        switch self {
        case .slideMixed:
            return .slideRight
        case .slideRight:
            return .slideLeft
        case .slideLeft:
            return .slideUp
        case .slideUp:
            return .slideDown
        case .slideDown:
            return .slideRight
        default:
            return self
        }
    }
    
    var pushNext: ImageTransition {
        switch self {
        case .pushMixed:
            return .pushRight
        case .pushRight:
            return .pushLeft
        case .pushLeft:
            return .pushUp
        case .pushUp:
            return .pushDown
        case .pushDown:
            return .pushRight
        default:
            return self
        }
    }
}

public enum ImageMovement {

    case none
    case fade
    case scale
}

public enum MovementFade {

    case upLeft
    case upRight
    case bottomLeft
    case bottomRight
    
    var next: MovementFade {
        switch self {
        case .upLeft:
            return .upRight
        case .upRight:
            return .bottomLeft
        case .bottomLeft:
            return .bottomRight
        case .bottomRight:
            return .upLeft
        }
    }
}
