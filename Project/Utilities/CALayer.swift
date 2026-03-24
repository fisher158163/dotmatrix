//
//  CALayer.swift
//
//  Copyright © 2018 usagimaru.
//

import QuartzCore

extension CALayer {
	
	func setBorderColor(_ color: CGColor?, width: CGFloat = 1.0) {
		borderColor = color
		borderWidth = width
	}
	
	/// 禁用动画的代码块
	class func disableAnimations(_ animations: () -> Void) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		CATransaction.setAnimationDuration(0)
		animations()
		CATransaction.commit()
	}
	
}
