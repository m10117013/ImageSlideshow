//
//  ZoomablePhotoView.swift
//  ImageSlideshow
//
//  Created by Petr Zvoníček on 30.07.15.
//

import UIKit

/// Used to wrap a single slideshow item and allow zooming on it
@objcMembers
open class ImageSlideshowItem: UIScrollView, UIScrollViewDelegate {

    /// Image view to hold the image
    open let imageView = UIImageView()

    /// Activity indicator shown during image loading, when nil there won't be shown any
    open let activityIndicator: ActivityIndicatorView?

    /// Input Source for the item
    open let image: InputSource

    /// Guesture recognizer to detect double tap to zoom
    open var gestureRecognizer: UITapGestureRecognizer?

    /// Holds if the zoom feature is enabled
    open let zoomEnabled: Bool

    /// If set to true image is initially zoomed in
    open var zoomInInitially = false
    
    /// Maximum zoom scale
    open var maximumScale: CGFloat = 2.0

    
    /// Is Image need blur processing
    open var needProcessBlur : Bool = false
    
    fileprivate var lastFrame = CGRect.zero
    fileprivate var imageReleased = false
    fileprivate var isLoading = false
    fileprivate var singleTapGestureRecognizer: UITapGestureRecognizer?
    fileprivate var loadFailed = false {
        didSet {
            singleTapGestureRecognizer?.isEnabled = loadFailed
            gestureRecognizer?.isEnabled = !loadFailed
        }
    }

    // MARK: - Life cycle

    /**
        Initializes a new ImageSlideshowItem
        - parameter image: Input Source to load the image
        - parameter zoomEnabled: holds if it should be possible to zoom-in the image
    */
    init(image: InputSource, zoomEnabled: Bool, activityIndicator: ActivityIndicatorView? = nil, maximumScale: CGFloat = 2.0) {
        self.zoomEnabled = zoomEnabled
        self.image = image
        self.activityIndicator = activityIndicator
        self.maximumScale = maximumScale

        super.init(frame: CGRect.null)

        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true

        setPictoCenter()

        // scroll view configuration
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        addSubview(imageView)
        minimumZoomScale = 1.0
        maximumZoomScale = calculateMaximumScale()

        if let activityIndicator = activityIndicator {
            addSubview(activityIndicator.view)
        }

        // tap gesture recognizer
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(ImageSlideshowItem.tapZoom))
        tapRecognizer.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(tapRecognizer)
        gestureRecognizer = tapRecognizer

        singleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(retryLoadImage))
        singleTapGestureRecognizer!.numberOfTapsRequired = 1
        singleTapGestureRecognizer!.isEnabled = false
        imageView.addGestureRecognizer(singleTapGestureRecognizer!)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        if !zoomEnabled {
            imageView.frame.size = frame.size
        } else if !isZoomed() {
            imageView.frame.size = calculatePictureSize()
        }

        if isFullScreen() {
            clearContentInsets()
        } else {
            setPictoCenter()
        }

        self.activityIndicator?.view.center = imageView.center

        // if self.frame was changed and zoomInInitially enabled, zoom in
        if lastFrame != frame && zoomInInitially {
            setZoomScale(maximumZoomScale, animated: false)
        }

        lastFrame = self.frame

        contentSize = imageView.frame.size
        maximumZoomScale = calculateMaximumScale()
    }

    /// Request to load Image Source to Image View
    public func loadImage() {
        if self.imageView.image == nil && !isLoading {
            isLoading = true
            imageReleased = false
            activityIndicator?.show()
            image.load(to: self.imageView) {[weak self] image in
                // set image to nil if there was a release request during the image load
                if let imageRelease = self?.imageReleased, imageRelease {
                    self?.imageView.image = nil
                } else {
                    if let needProcessBlur = self?.needProcessBlur {
                        if (needProcessBlur) {
                            
                            DispatchQueue.global().async {
                                let new_image = self?.blurImage(image: image!)
                                DispatchQueue.main.async {
                                    
                                    let label = UILabel(frame: CGRect(x: (self?.imageView.bounds.width)! / 2 - 100, y: (self?.imageView.bounds.height)! / 2 - 25, width: 200, height: 50))
                                    label.layer.cornerRadius = 10
                                    label.layer.borderColor = UIColor.gray.cgColor
                                    label.layer.borderWidth = 3
                                    label.textAlignment = .center
                                    label.textColor = UIColor.white
                                    label.sizeToFit()
                                    label.text = "點我看更多圖片"
                                    self?.imageView.addSubview(label)
                                    label.frame = CGRect(x: (self?.imageView.bounds.width)! / 2 - 100, y: (self?.imageView.bounds.height)! / 2 - 25, width: 200, height: 50)
                                    self?.imageView.image = new_image
                                }
                                
                            }
                            
                        } else {   
                            self?.imageView.image = image
                        }
                    }
                }
                self?.activityIndicator?.hide()
                self?.loadFailed = image == nil
                self?.isLoading = false
            }
        }
    }
    
    
    
    func releaseImage() {
        imageReleased = true
        cancelPendingLoad()
        self.imageView.image = nil
    }
    
    public func cancelPendingLoad() {
        image.cancelLoad?(on: imageView)
    }

    @objc func retryLoadImage() {
        self.loadImage()
    }

    // MARK: - Image zoom & size

    func isZoomed() -> Bool {
        return self.zoomScale != self.minimumZoomScale
    }

    func zoomOut() {
        self.setZoomScale(minimumZoomScale, animated: false)
    }

    @objc func tapZoom() {
        if isZoomed() {
            self.setZoomScale(minimumZoomScale, animated: true)
        } else {
            self.setZoomScale(maximumZoomScale, animated: true)
        }
    }

    fileprivate func screenSize() -> CGSize {
        return CGSize(width: frame.width, height: frame.height)
    }

    fileprivate func calculatePictureFrame() {
        let boundsSize: CGSize = bounds.size
        var frameToCenter: CGRect = imageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    fileprivate func calculatePictureSize() -> CGSize {
        if let image = imageView.image, imageView.contentMode == .scaleAspectFit {
            let picSize = image.size
            let picRatio = picSize.width / picSize.height
            let screenRatio = screenSize().width / screenSize().height

            if picRatio > screenRatio {
                return CGSize(width: screenSize().width, height: screenSize().width / picSize.width * picSize.height)
            } else {
                return CGSize(width: screenSize().height / picSize.height * picSize.width, height: screenSize().height)
            }
        } else {
            return CGSize(width: screenSize().width, height: screenSize().height)
        }
    }

    fileprivate func calculateMaximumScale() -> CGFloat {
        return maximumScale
    }

    fileprivate func setPictoCenter() {
        var intendHorizon = (screenSize().width - imageView.frame.width ) / 2
        var intendVertical = (screenSize().height - imageView.frame.height ) / 2
        intendHorizon = intendHorizon > 0 ? intendHorizon : 0
        intendVertical = intendVertical > 0 ? intendVertical : 0
        contentInset = UIEdgeInsets(top: intendVertical, left: intendHorizon, bottom: intendVertical, right: intendHorizon)
    }

    private func isFullScreen() -> Bool {
        return imageView.frame.width >= screenSize().width && imageView.frame.height >= screenSize().height
    }

    func clearContentInsets() {
        contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    // MARK: UIScrollViewDelegate

    open func scrollViewDidZoom(_ scrollView: UIScrollView) {
        setPictoCenter()
    }

    open func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return zoomEnabled ? imageView : nil
    }

}

extension ImageSlideshowItem {
    
    
    func blurImage(image:UIImage) -> UIImage? {
        

        var image = self.resizeImage(image : image, targetSize: CGSize(width:   200, height: 100))
        
        let context = CIContext(options: nil)
        let inputImage = CIImage(image: image)
        let originalOrientation = image.imageOrientation
        let originalScale = image.scale
        
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(inputImage, forKey: kCIInputImageKey)
        filter?.setValue(10.0, forKey: kCIInputRadiusKey)
        let outputImage = filter?.outputImage
        
        var cgImage:CGImage?
        
        if let asd = outputImage
        {
            cgImage = context.createCGImage(asd, from: (inputImage?.extent)!)
        }
        
        if let cgImageA = cgImage
        {
//            return self.waterMark(image: image, text: "12")
            return UIImage(cgImage: cgImageA, scale: CGFloat(originalScale), orientation: originalOrientation)
        }
        
        return nil
    }
    
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage!
    }
    
    func waterMark(image:UIImage , text:String) -> UIImage! {
        
        UIGraphicsBeginImageContext(image.size)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.width))
        
        UIColor.gray.set()
        let watermark = UIImage(named: "MasterCard")
        watermark?.draw(in: CGRect(x: image.size.width / 2 - 50 , y: image.size.height / 2, width: 50, height: 50))
        
        let re_image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return re_image
    }

}
