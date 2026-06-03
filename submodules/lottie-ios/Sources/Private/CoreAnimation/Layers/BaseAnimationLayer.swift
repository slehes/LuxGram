// Created by Cal Stephens on 1/27/22.
// Copyright © 2022 Airbnb Inc. All rights reserved.

import QuartzCore

/// A base `CALayer` that manages the frame and animations
/// of its `sublayers` and `mask`
class BaseAnimationLayer: CALayer, AnimationLayer {

  override func layoutSublayers() {
    super.layoutSublayers()

    for sublayer in managedSublayers {
      sublayer.fillBoundsOfSuperlayer()
    }
  }

  func setupAnimations(context: LayerAnimationContext) throws {
    for childAnimationLayer in managedSublayers {
      try (childAnimationLayer as? AnimationLayer)?.setupAnimations(context: context)
    }
  }

  /// All of the sublayers managed by this container
  private var managedSublayers: [CALayer] {
    (sublayers ?? []) + [mask].compactMap { $0 }
  }

}
