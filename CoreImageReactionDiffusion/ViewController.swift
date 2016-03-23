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

    let grayScottFilter = GrayScottFilter()
    
    let rect640x640 = CGRect(x: 0, y: 0, width: 640, height: 640)
    
    let accumulator = CIImageAccumulator(extent: CGRect(x: 0, y: 0, width: 640, height: 640), format: kCIFormatARGB8)
    
    let edgesFilter = CIFilter(name: "CIEdges",
        withInputParameters: [kCIInputIntensityKey: 50])!
    
    let imageView = MetalImageView()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        view.addSubview(imageView)
        
        setInitialImage()
        
        let displayLink = CADisplayLink(target: self, selector: #selector(ViewController.step))
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
        for _ in 0 ..< 5
        {
            grayScottFilter.setValue(accumulator.image(),
                forKey: kCIInputImageKey)
            accumulator.setImage(grayScottFilter.outputImage)
        }
        
        edgesFilter.setValue(accumulator.image(),
                             forKey: kCIInputImageKey)
        
        imageView.image = edgesFilter.outputImage!
    }
    
    override func viewDidLayoutSubviews()
    {
        imageView.frame = CGRect(
            origin: CGPoint(
                x: view.frame.width / 2 - rect640x640.width / 2,
                y: view.frame.height / 2 - rect640x640.height / 2),
            size: CGSize(
                width: rect640x640.width,
                height: rect640x640.height))
    }

}


// MARK: GrayScottFilter_v2 - Uses Core Image convolution filter with Laplacian kernel
class GrayScottFilter_v2: CIFilter
{
    var inputImage : CIImage?
 
    var D_a: CGFloat = 0.189
    var D_b: CGFloat = 0.080
    var k: CGFloat = 0.062
    var f: CGFloat = 0.0425
    
    let grayScottKernel = CIColorKernel(string:
        "kernel vec4 coreImageKernel(__sample pixel, __sample laplacian, float D_a, float D_b, float k, float f) " +
        "{" +
        "float reactionRate = pixel.x * pixel.z * pixel.z;" +
  
        "float u = pixel.x + (D_a * laplacian.x) - reactionRate + f * (1.0 - pixel.x);" +
        "float v = pixel.z + (D_b * laplacian.z) + reactionRate - (f + k) * pixel.z;" +
        
        "return vec4(u, u, v, 1.0);" +
        "}"
    )

    let laplacianFilter: CIFilter =
    {
        let laplacianWeights = CIVector(values: [
            CGFloat(0.0), CGFloat(1.0), CGFloat(0.0),
            CGFloat(1.0), CGFloat(-4.0), CGFloat(1.0),
            CGFloat(0.0), CGFloat(1.0), CGFloat(0.0) ], count: 9)
        
        return CIFilter(name: "CIConvolution3X3",
            withInputParameters: [
                kCIInputWeightsKey: laplacianWeights])!
    }()
    
    override var outputImage : CIImage!
    {
        if let inputImage = inputImage,
            grayScottKernel = grayScottKernel
        {
            laplacianFilter.setValue(inputImage,
                forKey: kCIInputImageKey)
  
            let arguments = [inputImage,
                laplacianFilter.outputImage!,
                D_a, D_b, k, f]
            let extent = inputImage.extent
        
            return grayScottKernel.applyWithExtent(extent,
                arguments: arguments)
        }
        return nil
    }
}

// MARK: GrayScottFilter_v3 - Hand coded convolution filter
class GrayScottFilter_v3: CIFilter
{
    var inputImage : CIImage?
    
    var D_a: CGFloat = 0.189
    var D_b: CGFloat = 0.080
    var k: CGFloat = 0.062
    var f: CGFloat = 0.0425
    
    let grayScottKernel = CIColorKernel(string:
        "kernel vec4 coreImageKernel(__sample pixel, __sample laplacian, float D_a, float D_b, float k, float f) " +
        "{" +
        "float reactionRate = pixel.x * pixel.z * pixel.z;" +
        
        "float u = pixel.x + (D_a * laplacian.x) - reactionRate + f * (1.0 - pixel.x);" +
        "float v = pixel.z + (D_b * laplacian.z) + reactionRate - (f + k) * pixel.z;" +
        
        "return vec4(u, u, v, 1.0);" +
        "}"
    )
    
    let laplacianKernel = CIKernel(string:
        "kernel vec4 laplacianConvolution(sampler image) " +
        "{" +
        "vec2 d = destCoord();" +
        
        "vec2 northSample = sample(image, samplerTransform(image, d + vec2(0.0,-1.0))).rb;" +
        "vec2 southSample = sample(image, samplerTransform(image, d + vec2(0.0,1.0))).rb;" +
        "vec2 eastSample = sample(image, samplerTransform(image, d + vec2(1.0,0.0))).rb;" +
        "vec2 westSample = sample(image, samplerTransform(image, d + vec2(-1.0,0.0))).rb;" +
        
        "vec2 thisSample = sample(image, samplerCoord(image)).xz;" +
        
        "vec2 laplacian = (northSample + southSample + eastSample + westSample) - (4.0 * thisSample);" +
            
        "return vec4(laplacian.x, laplacian.x, laplacian.y, 1.0);" +
        "}"
    )

    override var outputImage : CIImage!
    {
        if let inputImage = inputImage,
            laplacianKernel = laplacianKernel,
            grayScottKernel = grayScottKernel
        {
            let laplacian = laplacianKernel.applyWithExtent(inputImage.extent,
                roiCallback:
                {
                    (index, rect) in
                    return rect
                },
                arguments: [inputImage])
            
            let arguments = [inputImage,
                laplacian!,
                D_a, D_b, k, f]
            let extent = inputImage.extent
        
            return grayScottKernel.applyWithExtent(extent,
                arguments: arguments)
        }
        return nil
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

// MARK Metal Image View

import MetalKit

/// `MetalImageView` extends an `MTKView` and exposes an `image` property of type `CIImage` to
/// simplify Metal based rendering of Core Image filters.

class MetalImageView: MTKView
{
    let colorSpace = CGColorSpaceCreateDeviceRGB()!
    
    lazy var commandQueue: MTLCommandQueue =
    {
        [unowned self] in
        
        return self.device!.newCommandQueue()
    }()
    
    lazy var ciContext: CIContext =
    {
        [unowned self] in
        
        return CIContext(MTLDevice: self.device!)
    }()

    override init(frame frameRect: CGRect, device: MTLDevice?)
    {
        super.init(frame: frameRect,
                   device: device ?? MTLCreateSystemDefaultDevice())
        
        if super.device == nil
        {
            fatalError("Device doesn't support Metal")
        }
        
        framebufferOnly = false
    }
    
    required init(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// The image to display
    var image: CIImage?
        {
        didSet
        {
            renderImage()
        }
    }
    
    func renderImage()
    {
        guard let
            image = image,
            targetTexture = currentDrawable?.texture else
        {
            return
        }
        
        let commandBuffer = commandQueue.commandBuffer()
        
        let bounds = CGRect(origin: CGPointZero, size: drawableSize)
        
        let originX = image.extent.origin.x
        let originY = image.extent.origin.y
        
        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scale = min(scaleX, scaleY)
        
        let scaledImage = image
            .imageByApplyingTransform(CGAffineTransformMakeTranslation(-originX, -originY))
            .imageByApplyingTransform(CGAffineTransformMakeScale(scale, scale))
        
        ciContext.render(scaledImage,
                         toMTLTexture: targetTexture,
                         commandBuffer: commandBuffer,
                         bounds: bounds,
                         colorSpace: colorSpace)
        
        commandBuffer.presentDrawable(currentDrawable!)
        
        commandBuffer.commit()
    }
}