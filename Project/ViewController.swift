//
//  ViewController.swift
//  DotMatrix
//
//  Created by usagimaru on 2025/11/23.
//

import UIKit

class ViewController: UIViewController, UIScrollViewDelegate {
	
	@IBOutlet var scrollView: UIScrollView!
	private var scrollContentView = UIView()
	
	/// 横向单元总数
	private let numberOfCells_x: Int = 30
	/// 纵向单元总数
	private let numberOfCells_y: Int = 30
	/// 边缘判定阈值（屏幕边缘内的单元会逐渐缩小）
	private var edgeThreshold = 150.0
	
	private var cellSize = 72.0
	private var cellSpacing = 28.0
	private var cellCornerRadius = 20.0
	
	/// 各单元的 frame 缓存
	private var cellFrames = [CGRect]()
	/// 各单元的颜色缓存（索引→CGColor）
	private var cellColors = [CGColor]()
	
	/// 可复用单元池
	private var reusablePool = [Cell]()
	/// 当前显示中的单元（网格索引→Cell）
	private var visibleCells = [Int: Cell]()
	
	private var isSetUp = false
	
	/// 后台时忽略滚动处理
	private var isInBackground = false
	/// 进入后台前保留 contentOffset
	private var savedContentOffset: CGPoint?
	
	override var prefersStatusBarHidden: Bool {
		true
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		view.backgroundColor = UIColor.black
		
		scrollView.addSubview(scrollContentView)
		scrollView.contentInsetAdjustmentBehavior = .never
		
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sceneDidEnterBackground),
			name: UIScene.didEnterBackgroundNotification,
			object: nil)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sceneDidBecomeActive),
			name: UIScene.didActivateNotification,
			object: nil)
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		if !isSetUp {
			isSetUp = true
			setupGrid()
			updateContentInset()
			scrollToCenter()
			updateVisibleCells()
		}
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		
		let savedOffset = scrollView.contentOffset
		coordinator.animate(alongsideTransition: nil) { [weak self] _ in
			guard let self else { return }
			self.rebuildFrameCache()
			self.updateContentInset()
			self.scrollView.contentOffset = savedOffset
			self.updateVisibleCells()
		}
	}
	
	@objc private func sceneDidEnterBackground(_ notification: Notification) {
		guard let scene = notification.object as? UIWindowScene,
			  scene == view.window?.windowScene
		else { return }
		
		savedContentOffset = scrollView.contentOffset
		isInBackground = true
		
		// 回收全部单元到池中
		CALayer.disableAnimations {
			for (_, cell) in visibleCells {
				cell.isHidden = true
				cell.transform = CATransform3DIdentity
				cell.removeFromSuperlayer()
				reusablePool.append(cell)
			}
			visibleCells.removeAll()
		}
	}
	
	@objc private func sceneDidBecomeActive(_ notification: Notification) {
		guard let scene = notification.object as? UIWindowScene,
			  scene == view.window?.windowScene
		else { return }
		
		guard isInBackground else { return }
		isInBackground = false
		
		CALayer.disableAnimations {
			rebuildFrameCache()
			updateContentInset()
			
			if let offset = savedContentOffset {
				scrollView.contentOffset = offset
				savedContentOffset = nil
			}
		}
		updateVisibleCells()
	}
	
	// MARK: - Grid Setup
	/// 初始化网格数据（不生成 CALayer）
	private func setupGrid() {
		let totalCount = numberOfCells_x * numberOfCells_y
		
		updateCanvasSize()
		buildFrameCache()
		
		// 预先生成颜色并缓存
		cellColors.reserveCapacity(totalCount)
		for _ in 0..<totalCount {
			cellColors.append(UIColor(hue: .random(in: 0.0...1.0), saturation: 0.5, brightness: 1.0, alpha: 1.0).cgColor)
		}
	}
	
	/// 重建 frame 缓存（旋转/恢复时）
	private func rebuildFrameCache() {
		updateCanvasSize()
		buildFrameCache()
		
		// 更新可见单元的 frame
		let contentsScale = view.window?.screen.scale ?? UITraitCollection.current.displayScale
		CALayer.disableAnimations {
			for (index, cell) in visibleCells {
				cell.frame = cellFrames[index]
				cell.contentsScale = contentsScale
			}
		}
	}
	
	// MARK: - Cell Pool
	
	/// 从池中获取单元，没有则新建
	private func dequeueCell() -> Cell {
		if let cell = reusablePool.popLast() {
			return cell
		}
		let cell = Cell()
		cell.cornerRadius = cellCornerRadius
		cell.cornerCurve = .continuous
		cell.setBorderColor(UIColor(white: 0.9, alpha: 0.35).cgColor, width: 1)
		return cell
	}
	
	/// 将单元归还到池中
	private func recycleCell(_ cell: Cell, index: Int) {
		cell.isHidden = true
		cell.transform = CATransform3DIdentity
		cell.removeFromSuperlayer()
		visibleCells.removeValue(forKey: index)
		reusablePool.append(cell)
	}
	
	// MARK: - Frame Cache
	
	private func buildFrameCache() {
		let totalCount = numberOfCells_x * numberOfCells_y
		if cellFrames.count != totalCount {
			cellFrames = [CGRect](repeating: .zero, count: totalCount)
		}
		
		let step = cellSize + cellSpacing
		let halfStep = step / 2
		let size = CGSize(width: cellSize, height: cellSize)
		
		for iy in 0..<numberOfCells_y {
			let shiftX = iy % 2 == 0 ? -halfStep : 0.0
			let y = step * CGFloat(iy)
			
			for ix in 0..<numberOfCells_x {
				let index = ix + iy * numberOfCells_x
				cellFrames[index] = CGRect(
					origin: CGPoint(x: step * CGFloat(ix) + shiftX, y: y),
					size: size)
			}
		}
	}
	
	private func updateCanvasSize() {
		let w = cellSize * CGFloat(numberOfCells_x) + cellSpacing * CGFloat(max(numberOfCells_x - 1, 0))
		let h = cellSize * CGFloat(numberOfCells_y) + cellSpacing * CGFloat(max(numberOfCells_y - 1, 0))
		let size = CGSize(width: w, height: h)
		scrollContentView.frame = CGRect(origin: .zero, size: size)
		scrollView.contentSize = size
	}
	
	private func updateContentInset() {
		let boundsSize = scrollView.bounds.size
		let contentSize = scrollView.contentSize
		let insetH = max((boundsSize.width - contentSize.width) / 2, 0)
		let insetV = max((boundsSize.height - contentSize.height) / 2, 0)
		scrollView.contentInset = UIEdgeInsets(top: insetV, left: insetH, bottom: insetV, right: insetH)
	}
	
	// MARK: - Scroll Handling
	
	func scrollViewDidScroll(_ scrollView: UIScrollView) {
		guard scrollView == self.scrollView, !isInBackground else { return }
		updateVisibleCells()
	}
	
	/// 根据当前滚动位置更新可见单元的显示状态
	private func updateVisibleCells() {
		guard isSetUp else { return }
		
		let visibleRect = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
		let contentsScale = view.window?.screen.scale ?? UITraitCollection.current.displayScale
		
		// 由网格坐标计算可见范围的索引区间
		let step = cellSize + cellSpacing
		let shiftMargin = step / 2
		let expandedRect = visibleRect.insetBy(dx: -(step + shiftMargin), dy: -step)
		let minIndex_x = max(Int(floor(expandedRect.minX / step)) - 1, 0)
		let maxIndex_x = min(Int(ceil(expandedRect.maxX / step)) + 1, numberOfCells_x - 1)
		let minIndex_y = max(Int(floor(expandedRect.minY / step)) - 1, 0)
		let maxIndex_y = min(Int(ceil(expandedRect.maxY / step)) + 1, numberOfCells_y - 1)
		
		guard minIndex_x <= maxIndex_x, minIndex_y <= maxIndex_y else { return }
		
		// 收集本次可见索引
		var newVisibleIndices = Set<Int>()
		
		for iy in minIndex_y...maxIndex_y {
			for ix in minIndex_x...maxIndex_x {
				let index = ix + iy * numberOfCells_x
				if visibleRect.intersects(cellFrames[index]) {
					newVisibleIndices.insert(index)
				}
			}
		}
		
		CALayer.disableAnimations {
			// 回收移出屏幕的单元
			for index in visibleCells.keys {
				if !newVisibleIndices.contains(index) {
					if let cell = visibleCells[index] {
						recycleCell(cell, index: index)
					}
				}
			}
			
			// 分配并更新可见单元
			for index in newVisibleIndices {
				let cell: Cell
				if let existing = visibleCells[index] {
					cell = existing
				} else {
					// 从池中取出并放置
					cell = dequeueCell()
					cell.backgroundColor = cellColors[index]
					cell.frame = cellFrames[index]
					cell.contentsScale = contentsScale
					cell.isHidden = false
					scrollContentView.layer.addSublayer(cell)
					visibleCells[index] = cell
				}
				cell.update(scrollView: scrollView, threshold: edgeThreshold)
			}
		}
	}
	
	private func scrollToCenter() {
		let inset = scrollView.contentInset
		let offsetX = (scrollView.contentSize.width + inset.left + inset.right - scrollView.bounds.width) / 2 - inset.left
		let offsetY = (scrollView.contentSize.height + inset.top + inset.bottom - scrollView.bounds.height) / 2 - inset.top
		scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
	}

}

