import Foundation

let sgChatExportCSS: String = """
body {
    margin: 0;
    font: 12px/18px 'Open Sans',"Lucida Grande","Lucida Sans Unicode",Arial,Helvetica,Verdana,sans-serif;
}
strong {
    font-weight: 700;
}
code, kbd, pre, samp {
    font-family: Menlo,Monaco,Consolas,"Courier New",monospace;
}
code {
    padding: 2px 4px;
    font-size: 90%;
    color: #c7254e;
    background-color: #f9f2f4;
    border-radius: 4px;
}
pre {
    display: block;
    margin: 0;
    line-height: 1.42857143;
    word-break: break-all;
    word-wrap: break-word;
    color: #333;
    background-color: #f5f5f5;
    border-radius: 4px;
    overflow: auto;
    padding: 3px;
    border: 1px solid #eee;
    max-height: none;
    font-size: inherit;
}
.clearfix:after {
    content: " ";
    visibility: hidden;
    display: block;
    height: 0;
    clear: both;
}
.pull_left {
    float: left;
}
.pull_right {
    float: right;
}
.page_wrap {
    background-color: #ffffff;
    color: #000000;
}
.page_wrap a {
    color: #168acd;
    text-decoration: none;
}
.page_wrap a:hover {
    text-decoration: underline;
}
.page_header {
    position: fixed;
    z-index: 10;
    background-color: #ffffff;
    width: 100%;
    border-bottom: 1px solid #e3e6e8;
}
.page_header .content {
    width: 480px;
    margin: 0 auto;
    border-radius: 0 !important;
}
.bold {
    color: #212121;
    font-weight: 700;
}
.details {
    color: #70777b;
}
.page_header .content .text {
    padding: 24px 24px 22px 24px;
    font-size: 22px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
.page_body {
    padding-top: 64px;
    width: 480px;
    margin: 0 auto;
}
.userpic {
    display: block;
    border-radius: 50%;
    overflow: hidden;
}
.userpic .initials {
    display: block;
    color: #fff;
    text-align: center;
    text-transform: uppercase;
    user-select: none;
}
.userpic1 { background-color: #ff5555; }
.userpic2 { background-color: #64bf47; }
.userpic3 { background-color: #ffab00; }
.userpic4 { background-color: #4f9cd9; }
.userpic5 { background-color: #9884e8; }
.userpic6 { background-color: #e671a5; }
.userpic7 { background-color: #47bcd1; }
.userpic8 { background-color: #ff8c44; }
.history {
    padding: 16px 0;
}
.message {
    margin: 0 -10px;
    transition: background-color 2.0s ease;
}
div.selected {
    background-color: rgba(242,246,250,255);
    transition: background-color 0.5s ease;
}
.service {
    padding: 10px 24px;
}
.service .body {
    text-align: center;
}
.message .userpic .initials {
    font-size: 16px;
}
.default {
    padding: 10px;
}
.default.joined {
    margin-top: -10px;
}
.default .from_name {
    color: #3892db;
    font-weight: 700;
    padding-bottom: 5px;
}
.default .from_name .details {
    font-weight: normal;
}
.default .body {
    margin-left: 60px;
}
.default .text {
    word-wrap: break-word;
    line-height: 150%;
    unicode-bidi: plaintext;
    text-align: start;
}
.default .reply_to,
.default .media_wrap {
    padding-bottom: 5px;
}
.default .media {
    margin: 0 -10px;
    padding: 5px 10px;
}
.default .media .fill,
.default .media .thumb {
    width: 48px;
    height: 48px;
    border-radius: 50%;
}
.default .media .fill {
    background-repeat: no-repeat;
    background-position: 12px 12px;
    background-size: 24px 24px;
}
.default .media .title {
    padding-top: 4px;
    font-size: 14px;
}
.default .media .description {
    color: #000000;
    padding-top: 4px;
    font-size: 13px;
}
.default .media .status {
    padding-top: 4px;
    font-size: 13px;
}
.default .video_file_wrap {
    position: relative;
}
.default .video_file,
.default .photo,
.default .sticker {
    display: block;
}
.video_duration {
    background: rgba(0, 0, 0, .4);
    padding: 0px 5px;
    position: absolute;
    z-index: 2;
    border-radius: 2px;
    right: 3px;
    bottom: 3px;
    color: #ffffff;
    font-size: 11px;
}
.video_play_bg {
    background: rgba(0, 0, 0, .4);
    width: 40px;
    height: 40px;
    line-height: 0;
    position: absolute;
    z-index: 2;
    border-radius: 50%;
    overflow: hidden;
    margin: -20px auto 0 -20px;
    top: 50%;
    left: 50%;
    pointer-events: none;
}
.video_play {
    position: absolute;
    display: inline-block;
    top: 50%;
    left: 50%;
    margin-left: -5px;
    margin-top: -9px;
    z-index: 1;
    width: 0;
    height: 0;
    border-style: solid;
    border-width: 9px 0 9px 14px;
    border-color: transparent transparent transparent #fff;
}
.pagination {
    text-align: center;
    padding: 20px;
    font-size: 16px;
}
.toast_container {
    position: fixed;
    left: 50%;
    top: 50%;
    opacity: 0;
    transition: opacity 3.0s ease;
}
.toast_body {
    margin: 0 -50%;
    float: left;
    border-radius: 15px;
    padding: 10px 20px;
    background: rgba(0, 0, 0, 0.7);
    color: #ffffff;
}
div.toast_shown {
    opacity: 1;
    transition: opacity 0.4s ease;
}
.media_voice_message .fill { background-color: #4f9cd9; }
.media_file .fill { background-color: #ff5555; }
.media_photo .fill { background-color: #64bf47; }
.media_video .fill { background-color: #47bcd1; }
.media_contact .fill { background-color: #ff8c44; }
.media_location .fill { background-color: #47bcd1; }
.spoiler {
    background: #e8e8e8;
}
.spoiler.hidden {
    background: #a9a9a9;
    cursor: pointer;
    border-radius: 3px;
}
.spoiler.hidden span {
    opacity: 0;
    user-select: none;
}
.reactions {
    margin: 5px 0;
}
.reactions .reaction {
    display: inline-flex;
    height: 20px;
    border-radius: 15px;
    background-color: #e8f5fc;
    color: #168acd;
    font-weight: bold;
    margin-bottom: 5px;
}
.reactions .reaction.active {
    background-color: #40a6e2;
    color: #fff;
}
.reactions .reaction .emoji {
    line-height: 20px;
    margin: 0 5px;
    font-size: 15px;
}
.reactions .reaction .userpic:not(:first-child) {
    margin-left: -8px;
}
.reactions .reaction .userpic {
    display: inline-block;
}
.reactions .reaction .userpic .initials {
    font-size: 8px;
}
.reactions .reaction .count {
    margin-right: 8px;
    line-height: 20px;
}
@media (prefers-color-scheme: dark) {
html, body {
    background-color: #1a2026;
    margin: 0;
    padding: 0;
}
.page_wrap {
    background-color: #1a2026;
    color: #ffffff;
    min-height: 100vh;
}
.page_wrap a {
    color: #4db8ff;
}
.page_header {
    background-color: #1a2026;
    border-bottom: 1px solid #2c333d;
}
.bold {
    color: #ffffff;
}
.details {
    color: #91979e;
}
.page_body {
    background-color: #1a2026;
}
code {
    color: #ff8aac;
    background-color: #2c333d;
}
pre {
    color: #ffffff;
    background-color: #2c333d;
    border: 1px solid #323a45;
}
.message {
    color: #ffffff;
}
div.selected {
    background-color: #323a45;
}
.default .from_name {
    color: #4db8ff;
}
.default .media .description {
    color: #ffffff;
}
.spoiler {
    background: #323a45;
}
.spoiler.hidden {
    background: #61c0ff;
}
.reactions .reaction {
    background-color: #2c333d;
    color: #4db8ff;
}
.reactions .reaction.active {
    background-color: #4db8ff;
    color: #1a2026;
}
}
"""
