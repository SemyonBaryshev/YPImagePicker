//
//  PostiOS10PhotoCapture.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 08/03/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import AVFoundation
import UIKit

@available(iOS 10.0, *)
class PostiOS10PhotoCapture: NSObject, YPPhotoCapture, AVCapturePhotoCaptureDelegate {
    var sessionQueue: DispatchQueue?
    let session = AVCaptureSession()
    var deviceInput: AVCaptureDeviceInput?
    var device: AVCaptureDevice? { return deviceInput?.device }
    private let photoOutput = AVCapturePhotoOutput()
    var output: AVCaptureOutput { return photoOutput }
    var isCaptureSessionSetup: Bool = false
    var isPreviewSetup: Bool = false
    var previewView: UIView!
    var videoLayer: AVCaptureVideoPreviewLayer!
    var currentFlashMode: YPFlashMode = .off
    var hasFlash: Bool {
        guard let device = device else { return false }
        return device.hasFlash
    }
    var block: ((Data?) -> Void)?

    // MARK: - Configuration

    private func newSettings() -> AVCapturePhotoSettings {
        var settings = AVCapturePhotoSettings()

        // Catpure Heif when available.
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        // Catpure Highest Quality possible.
        settings.isHighResolutionPhotoEnabled = true

        // Set flash mode.
        if let deviceInput = deviceInput {
            if deviceInput.device.isFlashAvailable {
                switch currentFlashMode {
                case .off:
                    if deviceInput.device.isFlashModeSupported(.off) {
                        settings.flashMode = .off
                    }
                case .on:
                    if deviceInput.device.isFlashModeSupported(.on) {
                        settings.flashMode = .on
                    }
                }
            }
        }
        return settings
    }

    func configure() {
        photoOutput.isHighResolutionCaptureEnabled = true

        // Improve capture time by preparing output with the desired settings.
        photoOutput.setPreparedPhotoSettingsArray([newSettings()], completionHandler: nil)
    }

    // MARK: - Flash

    func tryToggleFlash() {
        // if device.hasFlash device.isFlashAvailable //TODO test these
        switch currentFlashMode {
        case .on:
            currentFlashMode = .off
        case .off:
            currentFlashMode = .on
        }
    }

    // MARK: - Shoot

    func shoot(completion: @escaping (Data?) -> Void) {
        block = completion

        // Set current device orientation
        setCurrentOrienation()

        let settings = newSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error _: Error?) {
        guard let data = photo.fileDataRepresentation() else {
            block?(nil)
            return
        }
        block?(data)
    }
}
