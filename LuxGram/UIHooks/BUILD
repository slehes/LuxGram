objc_library(
    name = "UIHooks",
    enable_modules = True,
    module_name = "UIHooks",
    srcs = glob([
        "Sources/*.m",
        "Sources/*.mm",
        "Sources/*.h",
    ]),
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