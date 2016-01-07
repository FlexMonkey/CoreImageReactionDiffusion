//
//  ViewController.swift
//  CoreImageReactionDiffusion
//
//  Created by Simon Gladman on 04/01/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit
import GLKit

class ViewController: UIViewController {

    let rect640x640 = CGRect(x: 0, y: 0, width: 640, height: 640)
    
    let accumulator = CIImageAccumulator(extent: CGRect(x: 0, y: 0, width: 640, height: 640), format: kCIFormatARGB8)
    let grayScottFilter = GrayScottFilter()
    
    let edgesFilter = CIFilter(name: "CIEdges",
        withInputParameters: [kCIInputIntensityKey: 50])!
    
    lazy var imageView: GLKView =
    {
        [unowned self] in
        
        let imageView = GLKView()
        
        imageView.layer.borderColor = UIColor.grayColor().CGColor
        imageView.layer.borderWidth = 1
        imageView.layer.shadowOffset = CGSize(width: 0, height: 0)
        imageView.layer.shadowOpacity = 0.75
        imageView.layer.shadowRadius = 5
    
        imageView.context = self.eaglContext
        imageView.delegate = self
        
        return imageView
    }()
    
    let eaglContext = EAGLContext(API: .OpenGLES2)
    
    lazy var ciContext: CIContext =
    {
        [unowned self] in
        
        return CIContext(EAGLContext: self.eaglContext,
            options: [kCIContextWorkingColorSpace: NSNull()])
    }()
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.addSubview(imageView)
        
        setInitialImage()
        
        let displayLink = CADisplayLink(target: self, selector: Selector("step"))
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
    }

    func setInitialImage()
    {
        let yellow = CIImage(color: CIColor(color: UIColor.yellowColor()))
        let noise = CIFilter(name: "CIRandomGenerator")!

        let crop = CIFilter(name: "CICrop",
            withInputParameters: [kCIInputImageKey: noise.outputImage!,
                "inputRectangle": CIVector(CGRect: rect640x640.insetBy(dx: 250, dy: 250))])!

        let composite = CIFilter(name: "CISourceAtopCompositing",
            withInputParameters: [kCIInputBackgroundImageKey: yellow,
                kCIInputImageKey:crop.outputImage!])!
        
        accumulator.setImage(composite.outputImage!)
    }
    
    func step()
    {
        imageView.setNeedsDisplay()
    }
    
    override func viewDidLayoutSubviews()
    {
        imageView.frame = CGRect(origin: CGPoint(x: view.frame.width / 2 - rect640x640.width / 2, y: view.frame.height / 2 - rect640x640.height / 2),
            size: CGSize(width: rect640x640.width, height: rect640x640.height))
    }

}

// MARK: GLKViewDelegate extension

extension ViewController: GLKViewDelegate
{
func glkView(view: GLKView, drawInRect rect: CGRect)
{
    for _ in 0 ..< 5
    {
        grayScottFilter.setValue(accumulator.image(),
            forKey: kCIInputImageKey)
        accumulator.setImage(grayScottFilter.outputImage)
    }
    
    edgesFilter.setValue(accumulator.image(),
        forKey: kCIInputImageKey)

    ciContext.drawImage(edgesFilter.outputImage!,
        inRect: CGRect(x: 0, y: 0,
            width: imageView.drawableWidth,
            height: imageView.drawableHeight),
        fromRect: rect640x640)
}
}

// MARK: GrayScottFilter

class GrayScottFilter: CIFilter
{
    var inputImage : CIImage?
    
    
    var D_a: CGFloat = 0.189
    var D_b: CGFloat = 0.080
    var k: CGFloat = 0.062
    var f: CGFloat = 0.0425
    
    let grayScottKernel = CIKernel(string:
        "kernel vec4 coreImageKernel(sampler image, float D_a, float D_b, float k, float f) " +
        "{" +
        
        "vec2 d = destCoord();" +
        
        "vec2 northSample = sample(image, samplerTransform(image, d + vec2(0.0,-1.0))).rb;" +
        "vec2 southSample = sample(image, samplerTransform(image, d + vec2(0.0,1.0))).rb;" +
        "vec2 eastSample = sample(image, samplerTransform(image, d + vec2(1.0,0.0))).rb;" +
        "vec2 westSample = sample(image, samplerTransform(image, d + vec2(-1.0,0.0))).rb;" +
        
        "vec2 thisSample = sample(image, samplerCoord(image)).xz;" +
        
        "vec2 laplacian = (northSample + southSample + eastSample + westSample) - (4.0 * thisSample);" +
        
        "float reactionRate = thisSample.x * thisSample.y * thisSample.y;" +
  
        "float u = thisSample.x + (D_a * laplacian.x) - reactionRate + f * (1.0 - thisSample.x);" +
        "float v = thisSample.y + (D_b * laplacian.y) + reactionRate - (f + k) * thisSample.y;" +
        
        "return vec4(u, u, v, 1.0);" +
        "}"
    )
    
override var outputImage : CIImage!
{
    if let inputImage = inputImage,
        grayScottKernel = grayScottKernel
    {
        let arguments = [inputImage, D_a, D_b, k, f]
        let extent = inputImage.extent
    
        return grayScottKernel.applyWithExtent(extent,
            roiCallback:
            {
                (index, rect) in
                return rect
            },
            arguments: arguments)
    }
    return nil
}
}