// Created by Cal Stephens on 5/17/22.
// Copyright © 2022 Airbnb Inc. All rights reserved.

import QuartzCore

protocol OpacityAnimationModel {
  /// The opacity animation to apply to a `CALayer`
  var opacity: KeyframeGroup<Vector1D> { get }
}

extension Transform: OpacityAnimationModel { }

extension ShapeTransform: OpacityAnimationModel { }

extension Fill: OpacityAnimationModel { }

extension GradientFill: OpacityAnimationModel { }

extension Stroke: OpacityAnimationModel { }

extension GradientStroke: OpacityAnimationModel { }

extension CALayer {
  /// Adds the opacity animation from the given `OpacityAnimationModel` to this layer
  @nonobjc
  func addOpacityAnimation(for opacity: OpacityAnimationModel, context: LayerAnimationContext) throws {
    try addAnimation(
      for: .opacity,
      keyframes: opacity.opacity.keyframes,
      value: {
        // Lottie animation files express opacity as a numerical percentage value
        // (e.g. 0%, 50%, 100%) so we divide by 100 to get the decimal values
        // expected by Core Animation (e.g. 0.0, 0.5, 1.0).
        $0.cgFloatValue / 100
      },
      context: context)
  }
}
