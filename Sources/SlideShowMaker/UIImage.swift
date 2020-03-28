//
//  UIImage.swift
//  SlideShowMaker
//
//  Created by lcf on 27/07/2017.
//  Copyright © 2017 flow. All rights reserved.
//

import UIKit

extension UIImage{
    
    convenience init(view: UIView) {
        // TODO: there may be better API for this: UIGraphicsImageRenderer or snapshotting
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.isOpaque, 0)
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        view.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        self.init(cgImage: image!.cgImage!)
    }
}
