//
//  XTAnimatedImageView.swift
//  GIF加载
//
//  Created by 汉子MacBook－Pro on 2019/1/9.
//  Copyright © 2019 汉子MacBook－Pro. All rights reserved.
//

import UIKit
import MobileCoreServices

open class XTAnimatedImageView: UIImageView {

    /// 是否自动播放
    var autoPlayAnimatedImage = true
    
    /// 循环次数
    var repeatCount = 0
    
    /// runLoopMode
    var runLoopMode = RunLoop.Mode.default {
        willSet {
            guard runLoopMode == newValue else {
                return
            }
            stopAnimating()
            displayLink.remove(from: .main, forMode: runLoopMode)
            displayLink.add(to: .main, forMode: newValue)
            startAnimating()
        }
    }
    
    //本地gif路径
    var gifFilePath: String? {
        didSet {
            let data = XTGIFAnimatedImage.loadLocalGIF(from: gifFilePath)
            gifData = data
        }
    }
    
    /// 设置数据
    var gifData: Data? {
        didSet {
            if let gifData = gifData {
                guard let imageSource = Animator.createImageSource(data: gifData) else {
                    return
                }
                animator = nil
                animator = Animator(imageSource: imageSource,
                                    contentMode: contentMode,
                                    size: bounds.size,
                                    framePreloadCount: 100,
                                    repeatCount: repeatCount,
                                    preloadQueue: preloadQueue)
                animator?.prepareFramesAsynchronously()
            }
            didMove()
        }
    }
    
    //Animator 对象
    private var animator: Animator?
    
    /// displayLink 为懒加载 避免还没有加载好的时候使用了 造成异常
    private var displayLinkInitialized: Bool = false
    
    open override var isAnimating: Bool {
        if displayLinkInitialized {
            return !displayLink.isPaused
        }else {
            return super.isAnimating
        }
    }
    
    open override func startAnimating() {
        guard !isAnimating else {
            return
        }
        if animator?.isReachMaxRepeatCount ?? false {
            return
        }
        
        displayLink.isPaused = false
    }
    
    open override func stopAnimating() {
        super.stopAnimating()
        if displayLinkInitialized {
            displayLink.isPaused = true
        }
    }
    
    open override func display(_ layer: CALayer) {
        if let currentFrame = animator?.currentFrameImage {
            layer.contents = currentFrame.cgImage
        }else {
            layer.contents = image?.cgImage
        }
    }
    
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        didMove()
    }
    
    open override func didMoveToSuperview() {
        super.didMoveToSuperview()
        didMove()
    }
    
    //队列
    private lazy var preloadQueue: DispatchQueue = {
        return DispatchQueue(label: "com.onevcat.Kingfisher.Animator.preloadQueue")
    }()
    
    //防止循环引用
    private class TargetProxy {
        
        private weak var target: XTAnimatedImageView?
        
        init(target: XTAnimatedImageView) {
            self.target = target
        }
        
        @objc func onScreenUpdate() {
            self.target?.updateFrameIfNeeded()
        }
    }
    
    private lazy var displayLink: CADisplayLink = {
        displayLinkInitialized = true
        let displayLink = CADisplayLink(target: TargetProxy(target: self), selector: #selector(TargetProxy.onScreenUpdate))
        displayLink.add(to: RunLoop.main, forMode: runLoopMode)
        displayLink.isPaused = true
        return displayLink
    }()
    
    private func didMove() {
        if autoPlayAnimatedImage && animator != nil {
            if let _ = superview, let _ = window {
                startAnimating()
            }
        }
    }
  
    /// 更新显示的帧数据
    private func updateFrameIfNeeded() {
        guard let animator = animator else {
            return
        }
        
        guard !animator.isFinished else {
            stopAnimating()
            return
        }
        
        let duration: CFTimeInterval
    
        if displayLink.preferredFramesPerSecond == 0 {
            duration = displayLink.duration
        } else {
            duration = 1.0 / Double(displayLink.preferredFramesPerSecond)
        }
        animator.shouldChangeFrame(with: duration) { (updateFrame) in
            if updateFrame {
                 // 此方法会触发 displayLayer
                self.layer.setNeedsDisplay()
            }
        }
    }
    
    deinit {
        if displayLinkInitialized {
            displayLink.invalidate()
        }
    }
    
}


extension XTAnimatedImageView {
    
    //每一帧的信息
    struct AnimatedFrame {
        
        var image: UIImage?
        var duration: TimeInterval
        
        func makeEmptyAnimateFrame() -> AnimatedFrame {
            return AnimatedFrame(image: nil, duration: 0.0)
        }
        
        func makeAnimatedFrame(image: UIImage?) -> AnimatedFrame {
            return AnimatedFrame(image: image, duration: duration)
        }
    }
}

extension XTAnimatedImageView {
    
    class Animator {
        private let size: CGSize
        private let maxFrameCount: Int//最大帧数
        private let imageSource: CGImageSource //
        private let maxRepeatCount: Int // 最大重复次数
        
        private let maxTimeStep: TimeInterval = 1.0 //最大间隔
        private var animatedFrames = [AnimatedFrame]() //
        private var frameCount = 0 //帧的数量
        private var timeSinceLastFrameChange: TimeInterval = 0.0 //距离上一帧改变以来的时间
        private var currentRepeatCount: UInt = 0 //当前循环次数
        
        var isFinished: Bool = false  //是否完成
        
        /// 一个动画的总时长
        var loopDuration: TimeInterval = 0
        
        /// 当前帧索引
        var currentFrameIndex = 0
        
        /// 前一帧索引
        var previousFrameIndex = 0
        
        /// 是否最后一帧
        var isLastFrame: Bool {
            return currentFrameIndex == frameCount - 1
        }
        
        // 当前帧的图片
        var currentFrameImage: UIImage? {
            return frameImage(at: currentFrameIndex)
        }
        
        /// 当前帧的执行时间
        var currentFrameDuration: TimeInterval {
            return frameDuration(at: currentFrameIndex)
        }
        
        /// 最大重复次数
        var isReachMaxRepeatCount: Bool {
            if maxRepeatCount == 0 {
                return false
            }else if currentRepeatCount >= maxRepeatCount - 1 {
                return true
            }else {
                return false
            }
        }
        
        
        /// 填充方式
        var contentMode = UIView.ContentMode.scaleToFill
        
        /// 队列
        private lazy var preloadQueue: DispatchQueue = {
            return DispatchQueue(label: "com.onevcat.Kingfisher.Animator.preloadQueue")
        }()
        
        
        /// 取帧图片
        private func frameImage(at index: Int) -> UIImage? {
            return animatedFrames[safe: index]?.image
        }
        
        /// 某一帧执行时间
        private func frameDuration(at index: Int) -> TimeInterval {
            return animatedFrames[safe: index]?.duration ?? .infinity
        }
        
        /// 准备数据
        func prepareFramesAsynchronously() {
            frameCount = CGImageSourceGetCount(imageSource)
            animatedFrames.reserveCapacity(frameCount)
            preloadQueue.async { [weak self] in
                self?.setupAnimatedFrames()
            }
        }
        
        /// 设置AnimatedFrames
        private func setupAnimatedFrames() {
            resetAnimatedFrames()
            
            var duration: TimeInterval = 0
            
            (0..<frameCount).forEach { (index) in
                let frameDuration = XTGIFAnimatedImage.getFrameDuration(from: imageSource, at: index)
                duration += frameDuration
                animatedFrames += [AnimatedFrame(image: nil, duration: frameDuration)]
                if index > maxFrameCount { return }
                animatedFrames[index] = animatedFrames[index].makeAnimatedFrame(image: loadFrame(at: index))
            }
            // 总时间
            self.loopDuration = duration
        }
        
        /// 重置 animatedFrames
        private func resetAnimatedFrames() {
            animatedFrames = []
        }
        
        /// 加载图片
        private func loadFrame(at index: Int) -> UIImage? {
            guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
                return nil
            }
            return UIImage(cgImage: image)
        }
        
        func shouldChangeFrame(with duration: CFTimeInterval, handler: (Bool) -> Void) {
            
            timeSinceLastFrameChange += min(maxTimeStep, duration)
            
            if currentFrameDuration > timeSinceLastFrameChange{
                    //不更新
                handler(false)
            }else {
                    //更新
                timeSinceLastFrameChange -= currentFrameDuration
                currentFrameIndex = increment(frameIndex: currentFrameIndex)
                if isLastFrame && isReachMaxRepeatCount {
                    isFinished = true
                }else if currentFrameIndex == 0{
                    currentRepeatCount += 1
                }
                handler(true)
            }
        }
        
        private func increment(frameIndex: Int, by value: Int = 1) -> Int {
            return (frameIndex + value) % frameCount
        }
        
        static public func createImageSource(data: Data) -> CGImageSource?{
            // kCGImageSourceShouldCache : 表示是否在存储的时候就解码
            // kCGImageSourceTypeIdentifierHint : 指明source type
            //这里的info是为了显示优化。提前解码，指定类型。
            let info: [String: Any] = [
                kCGImageSourceShouldCache as String: true,
                kCGImageSourceTypeIdentifierHint as String: kUTTypeGIF
            ]

            guard let imageSource = CGImageSourceCreateWithData(data as CFData, info as CFDictionary) else {
                print("creat imageSource error")
                return nil
            }
            return imageSource
        }
        
        
        //init
        init(imageSource source: CGImageSource,
             contentMode mode: UIView.ContentMode,
             size: CGSize,
             framePreloadCount count: Int,
             repeatCount: Int,
             preloadQueue: DispatchQueue) {
            self.imageSource = source
            self.contentMode = mode
            self.size = size
            self.maxFrameCount = count
            self.maxRepeatCount = repeatCount
            self.preloadQueue = preloadQueue
        }
        
    }
}

extension Array {
    subscript (safe index: Int) -> Element? {
        return (0 ..< count).contains(index) ? self[index] : nil
    }
}

class XTGIFAnimatedImage: NSObject {
    
    let images: [UIImage]
    let duration: TimeInterval
    
    init?(from imageSource: CGImageSource, for info: [String: Any]) {
        let frameCount = CGImageSourceGetCount(imageSource)
        var images = [UIImage]()
        var gifDuration = 0.0
        
        for i in 0 ..< frameCount {
            guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, i, info as CFDictionary) else {
                return nil
            }
            
            if frameCount == 1 {
                gifDuration = .infinity
            } else {
                // Get current animated GIF frame duration
                gifDuration += XTGIFAnimatedImage.getFrameDuration(from: imageSource, at: i)
            }
            
            images.append(UIImage(cgImage: imageRef, scale: UIScreen.main.scale, orientation: .up))
        }
        self.images = images
        self.duration = gifDuration
    }
    
    
    // Calculates frame duration for a gif frame out of the kCGImagePropertyGIFDictionary dictionary.
    static func getFrameDuration(from gifInfo: [String: Any]?) -> TimeInterval {
        let defaultFrameDuration = 0.1
        guard let gifInfo = gifInfo else { return defaultFrameDuration }
        
        let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
        let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        let duration = unclampedDelayTime ?? delayTime
        
        guard let frameDuration = duration else { return defaultFrameDuration }
        return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : defaultFrameDuration
    }
    
    // Calculates frame duration at a specific index for a gif from an `imageSource`.
    static func getFrameDuration(from imageSource: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil)
            as? [String: Any] else { return 0.0 }
        
        let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        return getFrameDuration(from: gifInfo)
    }
    
    static func loadLocalGIF(from path: String?) -> Data? {
        guard path != nil else {
            print("File does not exist")
            return nil
        }
        var gifData = Data()
        do {
            gifData = try! Data(contentsOf: URL(fileURLWithPath: path!))
        } catch {
            print(error)
        }
        return gifData
    }
}
