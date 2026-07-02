objc_library(
    name = "UIHooks",
    enable_modules = True,
    module_name = "UIHooks",
    srcs = [
        "Sources/UIHooks.mm",
    ],
    hdrs = [
        "Sources/Headers.h",
    ],
    sdk_frameworks = [
        "UIKit",
        "Foundation",
        "Intents",
    ],
    copts = [
        "-fobjc-arc",
        "-Wno-deprecated-declarations",
    ],
    visibility = ["//visibility:public"],
)