//
//  AVCaptureDevice+Extensions.swift
//  YPImagePickerExample
//
//  Created by Nik Kov on 23.04.2018.
//  Copyright © 2018 Octopepper. All rights reserved.
//

import AVFoundation

extension AVCaptureDevice {
    func tryToggleTorch() {
        guard hasFlash else { return }
        do {
            try lockForConfiguration()
            switch torchMode {
            case .on:
                torchMode = .off
            case .off:
                torchMode = .on
            default:
                break
            }
            unlockForConfiguration()
        } catch _ {}
    }

    func trySetTorchMode(_ torchMode: TorchMode) {
        guard hasFlash else { return }
        do {
            try lockForConfiguration()
            self.torchMode = torchMode
            unlockForConfiguration()
        } catch _ {}
    }
}
