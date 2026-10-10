import AppKit
import WebKit

// usage: render <input.svg> <output.png> <size>
let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: render <in.svg> <out.png> <size>\n".data(using: .utf8)!)
    exit(2)
}
let svgPath = args[1]
let outPath = args[2]
let size = Int(args[3]) ?? 1024

let svgData = try! Data(contentsOf: URL(fileURLWithPath: svgPath))
let b64 = svgData.base64EncodedString()

let html = """
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  html,body { margin:0; padding:0; width:\(size)px; height:\(size)px; background:transparent; overflow:hidden; }
  img { display:block; width:\(size)px; height:\(size)px; }
</style></head>
<body><img src="data:image/svg+xml;base64,\(b64)"></body></html>
"""

final class R: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: size, height: size)
            cfg.snapshotWidth = NSNumber(value: size)
            webView.takeSnapshot(with: cfg) { image, error in
                guard let image = image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write("snapshot failed: \(String(describing: error))\n".data(using: .utf8)!)
                    exit(3)
                }
                do {
                    try png.write(to: URL(fileURLWithPath: outPath))
                    print("ok -> \(outPath)")
                    exit(0)
                } catch {
                    FileHandle.standardError.write("write failed\n".data(using: .utf8)!)
                    exit(4)
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write("nav failed: \(error)\n".data(using: .utf8)!)
        exit(5)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = R()
let config = WKWebViewConfiguration()
let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: size, height: size), configuration: config)
webView.setValue(false, forKey: "drawsBackground")
webView.navigationDelegate = delegate

let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
win.contentView = webView
win.orderBack(nil)

webView.loadHTMLString(html, baseURL: nil)
app.run()
