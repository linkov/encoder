//
//  ViewController.swift
//  Encoder
//
//  Created by Alex Linkov on 6/24/20.
//  Copyright © 2020 SDWR. All rights reserved.
//

import UIKit
import JGProgressHUD
import Accelerate
import AudioToolbox

class ViewController: UIViewController, ImagePickerDelegate {
    func didSelect(image: UIImage?) {
        
        if (image == nil) {
            return
        }
        

        self.resultImageView.isHidden = true
        self.drawingView.clear()
        self.drawingView.preRenderImage = image
        //self.resultImageView.image = image!.resize(targetSize: activeSize)
    }
    

    var hud:JGProgressHUD?
     var imagePicker: ImagePicker!
    var activeSize = CGSize(width: 64, height: 64)
    
    @IBOutlet weak var resultImageView: UIImageView!
    @IBOutlet weak var drawingView: DrawingView!
    override func viewDidLoad() {
        super.viewDidLoad()
        hud = JGProgressHUD(style: .dark)
         self.imagePicker = ImagePicker(presentationController: self, delegate: self)
        resultImageView.layer.cornerRadius = 12
    }

    @IBAction func loadIMG(_ sender: Any) {
        self.imagePicker.present(from: sender as! UIView)
    }
    @IBAction func encode(_ sender: Any) {
        
        self.hud?.textLabel.text = "Encoding"
        self.hud!.indicatorView = JGProgressHUDIndeterminateIndicatorView()
        self.hud!.show(in: self.view)
  
   //     self.resultImageView.isHidden = false
       

        
        let origin = self.drawingView.preRenderImage.resize(targetSize: activeSize)
  
        
//        FFT2(origin: origin)

        
        
        DispatchQueue.global(qos: .background).async {
                   print("In background")

            let data = PixelData(image: origin)

            let result = fft(data, channel: .grayscale)
            let img = result.generateImage()



            DispatchQueue.main.async {
                                     print("dispatched to main")

                self.resultImageView.image = img
//                self.drawingView.clear()
//                self.drawingView.preRenderImage = nil
                self.resultImageView.isHidden = false
                self.hud?.dismiss()
            }
        }
        
    }
    
    
    @IBAction func clearDrawing(_ sender: Any) {
        
        self.resultImageView.isHidden = true
        self.drawingView.clear()
    }
    @IBAction func didChangeRES(_ sender: UISegmentedControl) {
    
        if (sender.selectedSegmentIndex == 0) {
            activeSize = CGSize(width: 64, height: 64)
        }
        if (sender.selectedSegmentIndex == 1) {
            activeSize = CGSize(width: 128, height: 128)
        }
        
        if (sender.selectedSegmentIndex == 2) {
            activeSize = CGSize(width: 256, height: 256)
        }
        if (sender.selectedSegmentIndex == 3) {
            activeSize = CGSize(width: 512, height: 512)
        }
    }
    
    @IBAction func save(_ sender: Any) {
        
        self.hud?.textLabel.text = "Image saved"
        self.hud!.indicatorView = JGProgressHUDSuccessIndicatorView()
        self.hud!.show(in: self.view)
        
        UIImageWriteToSavedPhotosAlbum(resultImageView.image!, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {

            

            self.hud!.dismiss(afterDelay: 2.0)
        }
    }
    
    
    
    
    func imageFromPixelSource(_ pixelSource: inout DSPSplitComplex,
                                     width: Int, height: Int,
                                     denominator: Float = pow(2, 29),
                                     bitmapInfo: CGBitmapInfo) -> UIImage? {
        
        let pixelCount = width * height
        let n = vDSP_Length(pixelCount / 2)
        let stride = vDSP_Stride(1)
        
        // multiply all float values (1 / denominator) * 255
        let multiplier = [Float](repeating: Float((1 / denominator) * 255),
                                 count: pixelCount / 2)

        vDSP.multiply(pixelSource,
                      by: multiplier,
                      result: &pixelSource)
        
        // Clip values to 0...255
        var low: Float = 0
        var high: Float = 255

        vDSP_vclip(pixelSource.realp,
                   stride,
                   &low,
                   &high,
                   pixelSource.realp,
                   stride,
                   n)
        
        vDSP_vclip(pixelSource.imagp,
                   stride,
                   &low,
                   &high,
                   pixelSource.imagp,
                   stride, n)
        
        var uIntPixels = [UInt8](repeating: 0,
                                 count: pixelCount)

        let floatPixels = [Float](fromSplitComplex: pixelSource,
                                  scale: 1,
                                  count: pixelCount)
        
        vDSP.convertElements(of: floatPixels,
                             to: &uIntPixels,
                             rounding: .towardZero)
        
        
        let result: UIImage? = uIntPixels.withUnsafeMutableBufferPointer { uIntPixelsPtr in
            
            let buffer = vImage_Buffer(data: uIntPixelsPtr.baseAddress!,
                                       height: vImagePixelCount(height),
                                       width: vImagePixelCount(width),
                                       rowBytes: width)
            
            if let format = vImage_CGImageFormat(bitsPerComponent: 8,
                                                  bitsPerPixel: 8,
                                                  colorSpace: CGColorSpaceCreateDeviceGray(),
                                                  bitmapInfo: bitmapInfo),
                let cgImage = try? buffer.createCGImage(format: format) {
                
                return UIImage(cgImage: cgImage)
            } else {
                print("Unable to create `CGImage`.")
                return nil
            }
        }

        
        return result
    }
    
    
    func imageToComplex(_ image: UIImage, splitComplex splitComplexOut: inout DSPSplitComplex) {
        guard let cgImage = image.cgImage else {
            fatalError("unable to generate cgimage")
        }
        
        let pixelCount = Int(image.size.width * image.size.height)
        
        let pixelData = cgImage.dataProvider?.data
        
        let pixelsArray = Array(UnsafeBufferPointer(start: CFDataGetBytePtr(pixelData),
                                                    count: pixelCount))
        
        let floatPixels = vDSP.integerToFloatingPoint(pixelsArray,
                                                      floatingPointType: Float.self)
        
        let interleavedPixels = stride(from: 1, to: floatPixels.count, by: 2).map {
            return DSPComplex(real: floatPixels[$0.advanced(by: -1)],
                              imag: floatPixels[$0])
        }
        
        vDSP.convert(interleavedComplexVector: interleavedPixels,
                     toSplitComplexVector: &splitComplexOut)
    }
    
    
    func FFT2(origin: UIImage) {
        
        
        
        
        let log2n = 10; // 2^10 = 1024
        
        let width = Int(origin.size.width)
        let height = Int(origin.size.height)
        let pixelCount = width * height
        let n = pixelCount / 2
        
        var setup:FFTSetup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2))!;
        
        
        var sourceImageReal = [Float](repeating: 0, count: n)
        var sourceImageImaginary = [Float](repeating: 0, count: n)
        
        let result: UIImage? = sourceImageReal.withUnsafeMutableBufferPointer { sourceImageRealPtr in
            sourceImageImaginary.withUnsafeMutableBufferPointer { sourceImageImaginaryPtr in

                        
                        var sourceImageSplitComplex = DSPSplitComplex(realp: sourceImageRealPtr.baseAddress!,
                                                                      imagp: sourceImageImaginaryPtr.baseAddress!)
                        
                        imageToComplex(origin,
                                       splitComplex: &sourceImageSplitComplex)
                     
             //   vDSP_fft_zrip(setup, &sourceImageSplitComplex, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                        
                return imageFromPixelSource(&sourceImageSplitComplex, width: 1024, height: 1024, bitmapInfo: CGBitmapInfo())
                    }

        }
        
        
        self.resultImageView.image = result
        
        
//        vDSP_fft_zrip(<#T##__Setup: FFTSetup##FFTSetup#>, <#T##__C: UnsafePointer<DSPSplitComplex>##UnsafePointer<DSPSplitComplex>#>, <#T##__IC: vDSP_Stride##vDSP_Stride#>, <#T##__Log2N: vDSP_Length##vDSP_Length#>, <#T##__Direction: FFTDirection##FFTDirection#>)
        //vImageConvert
        
        
        
//        let n = 1024;
//        let log2n = 10; // 2^10 = 1024
//
//        let a:DSPSplitComplex
//        a.realp = new float[n/2];
//        a.imagp = new float[n/2];
//
//        // prepare the fft algo (you want to reuse the setup across fft calculations)
//        FFTSetup setup = vDSP_create_fftsetup(log2n, kFFTRadix2);
//
//        // copy the input to the packed complex array that the fft algo uses
//        vDSP_ctoz((DSPComplex *) input, 2, &a, 1, n/2);
//
//        // calculate the fft
//        vDSP_fft_zrip(setup, &a, 1, log2n, FFT_FORWARD);
//
//        // do something with the complex spectrum
//        for (size_t i = 0; i < n/2; ++i) {
//            a.realp[i];
//            a.imagp[i];
//        }
//
        
        
        
        
        
//        // Your signal, array of length 1024
//        let signal: [Float] = (0 ... 1024)
//
//        // --- INITIALIZATION
//        // The length of the input
//        length = vDSP_Length(signal.count)
//        // The power of two of two times the length of the input.
//        // Do not forget this factor 2.
//        log2n = vDSP_Length(ceil(log2(Float(length * 2))))
//        // Create the instance of the FFT class which allow computing FFT of complex vector with length
//        // up to `length`.
//        fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
//
//
//        // --- Input / Output arrays
//        var forwardInputReal = [Float](signal) // Copy the signal here
//        var forwardInputImag = [Float](repeating: 0, count: Int(length))
//        var forwardOutputReal = [Float](repeating: 0, count: Int(length))
//        var forwardOutputImag = [Float](repeating: 0, count: Int(length))
//        var magnitudes = [Float](repeating: 0, count: Int(length))
//
//        /// --- Compute FFT
//        forwardInputReal.withUnsafeMutableBufferPointer { forwardInputRealPtr in
//          forwardInputImag.withUnsafeMutableBufferPointer { forwardInputImagPtr in
//            forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
//              fforwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
//                // Input
//                let forwardInput = DSPSplitComplex(realp: forwardInputRealPtr.baseAddress!, imagp: forwardInputImagPtr.baseAddress!)
//                // Output
//                var forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!, imagp: forwardOutputImagPtr.baseAddress!)
//
//                fftSetup.forward(input: forwardInput, output: &forwardOutput)
//                vDSP.absolute(forwardOutput, result: &magnitudes)
//              }
//            }
//          }
//        }
    }
    
    
    
}

extension UIImage {

func resize(targetSize: CGSize) -> UIImage {
    return UIGraphicsImageRenderer(size:targetSize).image { _ in
        self.draw(in: CGRect(origin: .zero, size: targetSize))
    }
}

}
extension UIImage {
    class func resize2(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / image.size.width
        let heightRatio = targetSize.height / image.size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
    
    class func scale(image: UIImage, by scale: CGFloat) -> UIImage? {
        let size = image.size
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIImage.resize2(image: image, targetSize: scaledSize)
    }
}
