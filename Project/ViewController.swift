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
	
	/// 横方向のセル総数
	private let numberOfCells_x: Int = 30
	/// 縦方向のセル総数
	private let numberOfCells_y: Int = 30
	/// エッジ判定閾値（スクリーン端からこの値の範囲にあるセルを徐々に縮小させる）
	private var edgeThreshold = 150.0
	
	private var cellSize = 72.0
	private var cellSpacing = 28.0
	private var cellCornerRadius = 22.0
	
	/// 各セルのframeキャッシュ
	private var cellFrames = [CGRect]()
	/// 各セルの色キャッシュ（インデックス→CGColor）
	private var cellColors = [CGColor]()
	
	/// 再利用可能なセルのプール
	private var reusablePool = [Cell]()
	/// 現在表示中のセル（グリッドインデックス→Cell）
	private var visibleCells = [Int: Cell]()
	
	private var isSetUp = false
	
	/// バックグラウンド中はスクロール処理を無視する
	private var isInBackground = false
	/// バックグラウンド移行前のcontentOffsetを保持
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
		
		// 全セルをプールに回収
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
	
	/// グリッドデータの初期化（CALayerは生成しない）
	private func setupGrid() {
		let totalCount = numberOfCells_x * numberOfCells_y
		
		updateCanvasSize()
		buildFrameCache()
		
		// 色を事前生成してキャッシュ
		cellColors.reserveCapacity(totalCount)
		for _ in 0..<totalCount {
			cellColors.append(UIColor(hue: .random(in: 0.0...1.0), saturation: 0.5, brightness: 1.0, alpha: 1.0).cgColor)
		}
	}
	
	/// frameキャッシュを再構築（回転・復帰時）
	private func rebuildFrameCache() {
		updateCanvasSize()
		buildFrameCache()
		
		// 表示中のセルのframeを更新
		let contentsScale = view.window?.screen.scale ?? UITraitCollection.current.displayScale
		CALayer.disableAnimations {
			for (index, cell) in visibleCells {
				cell.frame = cellFrames[index]
				cell.contentsScale = contentsScale
			}
		}
	}
	
	// MARK: - Cell Pool
	
	/// プールからセルを取得、なければ新規生成
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
	
	/// セルをプールに返却
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
	
	/// 現在のスクロール位置に基づいて可視セルの表示状態を更新
	private func updateVisibleCells() {
		guard isSetUp else { return }
		
		let visibleRect = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
		let contentsScale = view.window?.screen.scale ?? UITraitCollection.current.displayScale
		
		// グリッド座標から可視範囲のインデックス範囲を算出
		let step = cellSize + cellSpacing
		let shiftMargin = step / 2
		let expandedRect = visibleRect.insetBy(dx: -(step + shiftMargin), dy: -step)
		let minIndex_x = max(Int(floor(expandedRect.minX / step)) - 1, 0)
		let maxIndex_x = min(Int(ceil(expandedRect.maxX / step)) + 1, numberOfCells_x - 1)
		let minIndex_y = max(Int(floor(expandedRect.minY / step)) - 1, 0)
		let maxIndex_y = min(Int(ceil(expandedRect.maxY / step)) + 1, numberOfCells_y - 1)
		
		guard minIndex_x <= maxIndex_x, minIndex_y <= maxIndex_y else { return }
		
		// 今回の可視インデックスを収集
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
			// 画面外に出たセルを回収
			for index in visibleCells.keys {
				if !newVisibleIndices.contains(index) {
					if let cell = visibleCells[index] {
						recycleCell(cell, index: index)
					}
				}
			}
			
			// 可視セルの割り当てと更新
			for index in newVisibleIndices {
				let cell: Cell
				if let existing = visibleCells[index] {
					cell = existing
				} else {
					// プールから取得して配置
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

