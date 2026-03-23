//
//  Cell.swift
//  DotMatrix
//
//  Created by usagimaru on 2025/11/23.
//

import UIKit

class Cell: CALayer {
	
	private let smallestScale = 0.01
	
	override init() {
		super.init()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	func update(scrollView: UIScrollView, threshold: CGFloat) {
		let visibleRect = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
		let cellFrame = frame
		let cellCenter = CGPoint(x: cellFrame.midX, y: cellFrame.midY)
		
		let topDistance = max(cellCenter.y - visibleRect.minY, 0)
		let bottomDistance = max(visibleRect.maxY - cellCenter.y, 0)
		let leftDistance = max(cellCenter.x - visibleRect.minX, 0)
		let rightDistance = max(visibleRect.maxX - cellCenter.x, 0)
		
		var rate = 1.0
		if topDistance <= threshold {
			rate = min(topDistance / threshold, rate)
		}
		if bottomDistance <= threshold {
			rate = min(bottomDistance / threshold, rate)
		}
		if leftDistance <= threshold {
			rate = min(leftDistance / threshold, rate)
		}
		if rightDistance <= threshold {
			rate = min(rightDistance / threshold, rate)
		}
		rate = max(min(rate, 1.0), smallestScale)
		
		CALayer.disableAnimations {
			if rate < 1.0 {
				transform = CATransform3DMakeScale(rate, rate, 1.0)
			}
			else {
				transform = CATransform3DIdentity
			}
		}
	}
	
}
