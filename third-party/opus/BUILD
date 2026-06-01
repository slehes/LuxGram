
headers = [
    "opus.h",
    "opus_defines.h",
    "opus_multistream.h",
    "opus_projection.h",
    "opus_types.h",
]

libs = [
    "opus",
]

# MARK: LuxGram — use prebuilt libopus instead of genrule (saves ~10 min)
config_setting(
    name = "ios_arm64",
    values = {"cpu": "ios_arm64"},
)

config_setting(
    name = "ios_sim_arm64",
    values = {"cpu": "ios_sim_arm64"},
)

[genrule(
    name = "copy_header_" + h,
    srcs = ["prebuilt/include/" + h],
    outs = ["Public/opus/" + h],
    cmd = "cp $< $@",
    visibility = ["//visibility:public"],
) for h in headers]

genrule(
    name = "opus_build",
    srcs = select({
        ":ios_arm64": ["prebuilt/arm64/libopus.a"],
        ":ios_sim_arm64": ["prebuilt/sim_arm64/libopus.a"],
        "//conditions:default": ["prebuilt/arm64/libopus.a"],
    }),
    outs = ["Public/opus/lib/libopus.a"],
    cmd = "cp $< $@",
    visibility = [
        "//visibility:public",
    ],
)
# MARK: End LuxGram

cc_library(
    name = "opus_lib",
    srcs = [":Public/opus/lib/lib" + x + ".a" for x in libs],
)

cc_library(
    name = "opus_cc",
    hdrs = [":Public/opus/" + x for x in headers],
    includes = [
        "Public",
    ],
    deps = [
        ":opus_lib",
    ],
    visibility = [
        "//visibility:public",
    ],
)

objc_library(
    name = "opus",
    module_name = "opus",
    enable_modules = True,
    hdrs = [":Public/opus/" + x for x in headers],
    includes = [
        "Public",
    ],
    deps = [
        ":opus_lib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
