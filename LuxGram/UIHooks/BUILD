load("@build_bazel_rules_apple//apple:ios.bzl", "ios_library")

objc_library(
    name = "UIHooks",
    module_name = "UIHooks",
    srcs = glob(["Sources/**/*.{m,mm}"]),
    hdrs = glob(["Sources/**/*.h"]),
    copts = [
        "-fobjc-arc",
        "-Wno-deprecated-declarations",
    ],
    sdk_frameworks = [
        "UIKit",
        "Foundation",
        "Intents",
    ],
    visibility = ["//visibility:public"],
)