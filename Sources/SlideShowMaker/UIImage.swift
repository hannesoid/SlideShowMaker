//
//  UIImage.swift
//  SlideShowMaker
//
//  Created by lcf on 27/07/2017.
//  Copyright © 2017 flow. All rights reserved.
//

import UIKit

extension UIImage {
    
    convenience init(view: UIView) {
        if #available(iOS 10.0, *) {
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size)

            let image = renderer.image { imageRendererContext in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
                view.layer.render(in: UIGraphicsGetCurrentContext()!)
            }
            self.init(cgImage: image.cgImage!)
        } else {
            fatalError()
            // Fallback on earlier versions
        }
    }
}
