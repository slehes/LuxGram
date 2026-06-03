// Created by Cal Stephens on 1/6/22.
// Copyright © 2022 Airbnb Inc. All rights reserved.

import QuartzCore

/// The CALayer type responsible for rendering the `Mask` of a `BaseCompositionLayer`
final class MaskCompositionLayer: CALayer {

  init(masks: [Mask]) {
    maskLayers = masks.map(MaskLayer.init(mask:))
    super.init()

    for maskLayer in maskLayers {
      addSublayer(maskLayer)
    }
  }

  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Called by CoreAnimation to create a shadow copy of this layer
  /// More details: https://developer.apple.com/documentation/quartzcore/calayer/1410842-init
  override init(layer: Any) {
    guard let typedLayer = layer as? Self else {
      fatalError("\(Self.self).init(layer:) incorrectly called with \(type(of: layer))")
    }

    maskLayers = typedLayer.maskLayers
    super.init(layer: typedLayer)
  }

  override func layoutSublayers() {
    super.layoutSublayers()

    for sublayer in sublayers ?? [] {
      sublayer.fillBoundsOfSuperlayer()
    }
  }

  private let maskLayers: [MaskLayer]

}

extension MaskCompositionLayer: AnimationLayer {
  func setupAnimations(context: LayerAnimationContext) throws {
    for maskLayer in maskLayers {
      try maskLayer.setupAnimations(context: context)
    }
  }
}

extension MaskCompositionLayer {
  final class MaskLayer: CAShapeLayer {

    init(mask: Mask) {
      maskModel = mask
      super.init()
      fillColor = .rgb(0, 0, 0)
    }

    required init?(coder _: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    /// Called by CoreAnimation to create a shadow copy of this layer
    /// More details: https://developer.apple.com/documentation/quartzcore/calayer/1410842-init
    override init(layer: Any) {
      guard let typedLayer = layer as? Self else {
        fatalError("\(Self.self).init(layer:) incorrectly called with \(type(of: layer))")
      }

      maskModel = typedLayer.maskModel
      super.init(layer: typedLayer)
    }

    private let maskModel: Mask

  }
}

extension MaskCompositionLayer.MaskLayer: AnimationLayer {
  func setupAnimations(context: LayerAnimationContext) throws {
    try addAnimations(for: maskModel.shape, context: context)
  }
}
