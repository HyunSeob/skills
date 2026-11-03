// 제목으로 찾은 창 하나만 녹화한다 (ScreenCaptureKit, 커서 없음, 30fps).
// 사용: swift wincap.swift <창 제목에 포함된 문자열> <출력.mov>
// SIGINT(ctrl+c)를 받으면 파일을 마무리하고 끝난다.
// 제목만 주고 출력 경로를 빼면 찾은 창 정보만 출력하고 끝난다.
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: wincap <title-substring> [out.mov]\n", stderr)
    exit(2)
}
let needle = args[1]
// CLI에서 ScreenCaptureKit을 쓰려면 앱 컨텍스트 초기화가 필요하다
_ = NSApplication.shared
_ = CGMainDisplayID()
let outPath = args.count >= 3 ? args[2] : nil

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        // 내용이 바뀐 완전한 프레임만 쓴다
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: sb.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }
}

let sema = DispatchSemaphore(value: 0)
var stream: SCStream?
var recorder: Recorder?

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { ($0.title ?? "").contains(needle) && $0.windowLayer == 0 }) else {
            fputs("window not found: \(needle)\n", stderr)
            exit(1)
        }
        let scale = 2.0
        let w = Int(win.frame.width * scale) / 2 * 2
        let h = Int(win.frame.height * scale) / 2 * 2
        print("window \(win.windowID) \"\(win.title ?? "")\" \(Int(win.frame.width))x\(Int(win.frame.height)) -> \(w)x\(h)")
        guard let outPath else { exit(0) }

        let filter = SCContentFilter(desktopIndependentWindow: win)
        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.showsCursor = false
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6

        let rec = try Recorder(url: URL(fileURLWithPath: outPath), width: w, height: h)
        let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try s.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap"))
        try await s.startCapture()
        stream = s
        recorder = rec
        print("recording")
        fflush(stdout)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}

signal(SIGINT, SIG_IGN)
let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
src.setEventHandler {
    Task {
        try? await stream?.stopCapture()
        if let rec = recorder, rec.started {
            rec.input.markAsFinished()
            // 화면이 멈춰 있으면 새 프레임이 안 오므로, 마지막 프레임을 정지 시점까지 늘린다
            rec.writer.endSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))
            await rec.writer.finishWriting()
        }
        print("saved")
        exit(0)
    }
}
src.resume()
dispatchMain()
