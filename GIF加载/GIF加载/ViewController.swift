//
//  ViewController.swift
//  GIF加载
//
//  Created by 汉子MacBook－Pro on 2019/1/9.
//  Copyright © 2019 汉子MacBook－Pro. All rights reserved.
//

import UIKit
import ImageIO
import MobileCoreServices

class ViewController: UIViewController {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var animatedImageView: XTAnimatedImageView!
    
    var gifDuration: Double?
    var gifImages: [UIImage]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let path = Bundle.main.path(forResource: "timg", ofType: "gif")
        let data = loadLocalGIF(from: path)
        guard data != nil else {
            print("data 为空")
            return
        }
        animatedImageView.gifData = data
//        animatedImage(data: data!)
        imageView.animationImages = self.gifImages
        imageView.animationDuration = self.gifDuration ?? 0.1
        imageView.animationRepeatCount = 0
        imageView.startAnimating()
    }

    @IBAction func start(_ sender: UIButton) {
        if !animatedImageView.isAnimating {
            animatedImageView.startAnimating()
        }
    }
    
    @IBAction func stop(_ sender: UIButton) {
        if animatedImageView.isAnimating {
            animatedImageView.stopAnimating()
        }
    }
    /*
     1.本地读取GIF图片,转化为Data
     2.根据Data获取CGImageSource对象
     3.获取帧数
     4.根据帧数获取每一帧对应的UIImage和时间间隔
     5.循环播放
     */
 
    /// 1.本地读取GIF图片,转化为NSData
    func loadLocalGIF(from path: String?) -> Data? {
        guard path != nil else {
            print("文件不存在")
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
    
    func animatedImage(data: Data) {
        // kCGImageSourceShouldCache : 表示是否在存储的时候就解码
        // kCGImageSourceTypeIdentifierHint : 指明source type
        //这里的info是为了显示优化。提前解码，指定类型。
        let info: [String: Any] = [
            kCGImageSourceShouldCache as String: true,
            kCGImageSourceTypeIdentifierHint as String: kUTTypeGIF
        ]
        
        //然后通过CGImageSourceCreateWithData 方法创建一个CGImageSource 对象 。
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, info as CFDictionary) else {
            print("创建 CGImageSource 失败")
            return
        }
        
        //获取gif的帧数
        let frameCount = CGImageSourceGetCount(imageSource)
        var gifDuration = 0.0
        var images = [UIImage]()
        
        for i in 0..<frameCount {
            //取出索引对应的图片
            guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, i, info as CFDictionary) else {
                print("取出对应的图片失败")
                return
            }
            
            if frameCount == 1 {
                // 单帧
                //infinity 解释: https://swifter.tips/math-number/
               gifDuration = .infinity
            }else {
                //1.获取gif没帧的时间间隔
                
                //获取到该帧图片的属性字典
                guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [String: Any] else {
                    print("获取帧图片属性字典失败")
                    return
                }
                
                //获取该帧图片中的GIF相关的属性字典
                guard let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else {
                    print("获取GIF相关属性失败")
                    return
                }
                
                let defaultFrameDuration = 0.1
                //获取该帧图片的播放时间
                let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
                //如果通过kCGImagePropertyGIFUnclampedDelayTime没有获取到播放时长，就通过kCGImagePropertyGIFDelayTime来获取，两者的含义是相同的；
                let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
                let duration = unclampedDelayTime ?? delayTime
                guard let frameDuration = duration else {
                    print("获取帧时间间隔失败")
                    return
                }
                //对于播放时间低于0.011s的,重新指定时长为0.100s；
                let gifFrameDuration = frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : defaultFrameDuration
                
                //计算总时间
                gifDuration += gifFrameDuration
                
                
                //2.图片
                let frameImage = UIImage(cgImage: imageRef, scale: 1.0, orientation: .up)
                images.append(frameImage)
            }
        }
        
        self.gifDuration = gifDuration
        self.gifImages = images
        print("解码成功 gifDuration = \(gifDuration)")
        
    }
    
}

