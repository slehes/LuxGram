// Created by Jianjun Wu on 2022/5/12.
// Copyright © 2022 Airbnb Inc. All rights reserved.

import CoreGraphics
import Foundation

private final class CachedImageProvider: AnimationImageProvider {

  /// Initializes an image provider with an image provider
  ///
  /// - Parameter imageProvider: The provider to load image from asset
  ///
  public init(imageProvider: AnimationImageProvider) {
    self.imageProvider = imageProvider
  }

  public func imageForAsset(asset: ImageAsset) -> CGImage? {
    if let image = imageCache.object(forKey: asset.id as NSString) {
      return image
    }
    if let image = imageProvider.imageForAsset(asset: asset) {
      imageCache.setObject(image, forKey: asset.id as NSString)
      return image
    }
    return nil
  }

  let imageCache: NSCache<NSString, CGImage> = .init()
  let imageProvider: AnimationImageProvider
}

extension AnimationImageProvider {
  /// Create a cache enabled image provider which will reuse the asset image with the same asset id
  /// It wraps the current provider as image loader, and uses `NSCache` to cache the images for resue.
  /// The cache will be reset when the `animation` is reset.
  var cachedImageProvider: AnimationImageProvider {
    CachedImageProvider(imageProvider: self)
  }
}
