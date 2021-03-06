//
//  YYPPickerVC.swift
//  YPPickerVC
//
//  Created by Sacha Durand Saint Omer on 25/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import Foundation
import Photos
import Stevia

protocol ImagePickerDelegate: AnyObject {
    func noPhotos()
}

protocol YPVideoCaptureDelegate: AnyObject {
    func willStartVideoCapture(completion: (() -> Void)?)
}

protocol YPPhotoCaptureDelegate: AnyObject {
    func willStartPhotoCapture()
    func didCancelPhotoCapture()
}

open class YPPickerVC: YPBottomPager, YPBottomPagerDelegate {
    let albumsManager = YPAlbumsManager()
    var shouldHideStatusBar = false
    var initialStatusBarHidden = false
    weak var imagePickerDelegate: ImagePickerDelegate?
    private let sessionQueue = DispatchQueue(label: "YPVideoVCSerialQueue", qos: .background)
    private var isLoading = false
    private var isProcessing = false
    private var isLoadingDoneTimer: Timer?
    var isIgnoringInteraction = false
    private let blockingView = UIView()

    open override var prefersStatusBarHidden: Bool {
        return (shouldHideStatusBar || initialStatusBarHidden) && YPConfig.hidesStatusBar
    }

    /// Private callbacks to YPImagePicker
    public var didClose: (() -> Void)?
    public var didSelectItems: (([YPMediaItem]) -> Void)?

    enum Mode {
        case library
        case camera
        case video
    }

    private var albumVC: YPAlbumVC?
    private var libraryVC: YPLibraryVC?
    private var cameraVC: YPCameraVC?
    private var videoVC: YPVideoCaptureVC?

    var mode = Mode.camera

    var capturedImage: UIImage?

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = YPImagePickerConfiguration.shared.colors.pickerBackground

        delegate = self

        // Force Library only when using `minNumberOfItems`.
        if YPConfig.library.minNumberOfItems > 1 {
            YPImagePickerConfiguration.shared.screens = [.library]
        }

        // Library
        if YPConfig.screens.contains(.library) {
            libraryVC = YPLibraryVC()
            libraryVC?.delegate = self
        }

        // Camera
        if YPConfig.screens.contains(.photo) {
            cameraVC = YPCameraVC()
            cameraVC?.photoCapture.sessionQueue = sessionQueue
            cameraVC?.photoCaptureDelegate = self
            cameraVC?.videoCaptureDelegate = self
            cameraVC?.didCapturePhoto = { [weak self] img in
                self?.didSelectItems?([YPMediaItem.photo(p: YPMediaPhoto(image: img,
                                                                         fromCamera: true))])
            }
        }

        // Video
        if YPConfig.screens.contains(.video) {
            videoVC = YPVideoCaptureVC()
            videoVC?.videoHelper.sessionQueue = sessionQueue
            videoVC?.videoCaptureDelegate = self
            videoVC?.didCaptureVideo = { [weak self] videoURL in
                self?.didSelectItems?([YPMediaItem
                        .video(v: YPMediaVideo(thumbnail: thumbnailFromVideoPath(videoURL),
                                               videoURL: videoURL,
                                               fromCamera: true))])
            }
        }

        // Show screens
        var vcs = [UIViewController]()
        for screen in YPConfig.screens {
            switch screen {
            case .library:
                if let libraryVC = libraryVC {
                    vcs.append(libraryVC)
                }
            case .photo:
                if let cameraVC = cameraVC {
                    vcs.append(cameraVC)
                }
            case .video:
                if let videoVC = videoVC {
                    vcs.append(videoVC)
                }
            }
        }
        controllers = vcs

        // Select good mode
        if YPConfig.screens.contains(YPConfig.startOnScreen) {
            switch YPConfig.startOnScreen {
            case .library:
                mode = .library
            case .photo:
                mode = .camera
            case .video:
                mode = .video
            }
        }

        // Select good screen
        if let index = YPConfig.screens.firstIndex(of: YPConfig.startOnScreen) {
            startOnPage(index)
        }

        YPHelper.changeBackButtonIcon(self)
        YPHelper.changeBackButtonTitle(self)

        // Add blocking view
        view.sv(blockingView)
        blockingView.fillContainer()
        blockingView.isHidden = true
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraVC?.v.shotButton.isEnabled = true

        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        updateMode(with: currentController)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shouldHideStatusBar = true
        initialStatusBarHidden = true
        UIView.animate(withDuration: 0.3) {
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    internal func pagerScrollViewDidScroll(_: UIScrollView) {}

    func modeFor(vc: UIViewController) -> Mode {
        switch vc {
        case is YPLibraryVC:
            return .library
        case is YPCameraVC:
            return .camera
        case is YPVideoCaptureVC:
            return .video
        default:
            return .camera
        }
    }

    func pagerDidSelectController(_ vc: UIViewController) {
        updateMode(with: vc)
    }

    func updateMode(with vc: UIViewController) {
        stopCurrentCamera()

        // Set new mode
        mode = modeFor(vc: vc)

        // Re-trigger permission check
        if let vc = vc as? YPLibraryVC {
            vc.checkPermission()
        } else if let cameraVC = vc as? YPCameraVC {
            cameraVC.start()
        } else if let videoVC = vc as? YPVideoCaptureVC {
            videoVC.start()
        }

        updateUI()
    }

    func stopCurrentCamera() {
        switch mode {
        case .library:
            libraryVC?.pausePlayer()
        case .camera:
            cameraVC?.stopCamera()
        case .video:
            videoVC?.stopCamera()
        }
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shouldHideStatusBar = false
        stopAll()
    }

    @objc
    func navBarTapped() {
        guard !isProcessing else {
            return
        }
        let vc = YPAlbumVC(albumsManager: albumsManager)
        albumVC = vc
        let navVC = YPAlbumsNavigationController(rootViewController: vc)

        vc.didSelectAlbum = { [weak self] album in
            self?.libraryVC?.setAlbum(album)
            self?.setTitleViewWithTitle(aTitle: album.title)
            self?.dismiss(animated: true, completion: nil)
        }
        present(navVC, animated: true, completion: nil)
    }

    func setTitleViewWithTitle(aTitle: String) {
        let titleView = UIView()
        titleView.frame = CGRect(x: 0, y: 0, width: 200, height: 40)

        let label = UILabel()
        label.setContentCompressionResistancePriority(UILayoutPriority(rawValue: 749), for: .horizontal)
        label.text = aTitle
        // Use standard font by default.
        label.font = UIFont.boldSystemFont(ofSize: 17)

        // Use custom font if set by user.
        if let navBarTitleFont = YPConfig.library.titleNavigationBarFont {
            label.font = navBarTitleFont
        }
        // Use custom textColor if set by user.
        if let navBarTitleColor = YPConfig.colors.libraryTitleNavigationBarColor {
            label.textColor = navBarTitleColor
        }

        if YPConfig.library.options != nil {
            titleView.sv(
                label
            )
            |-(>=8) - label.centerHorizontally() - (>=8)-|
            align(horizontally: label)
        } else {
            let arrow = UIImageView()
            arrow.image = YPConfig.icons.arrowDownIcon

            if let foregroundColor = YPConfig.colors.libraryTitleNavigationBarColor {
                arrow.image = arrow.image?.withRenderingMode(.alwaysTemplate)
                arrow.tintColor = foregroundColor
            }

            let button = UIButton()
            button.addTarget(self, action: #selector(navBarTapped), for: .touchUpInside)

            titleView.sv(
                label,
                arrow,
                button
            )
            button.fillContainer()
            |-(>=8) - label.centerHorizontally() - arrow - (>=8)-|
            align(horizontally: label - arrow)
        }

        label.firstBaselineAnchor.constraint(equalTo: titleView.bottomAnchor, constant: -14).isActive = true

        titleView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        navigationItem.titleView = titleView
    }

    func updateUI() {
        // Update Nav Bar state.
        let backButton = YPBackButton(frame: CGRect(x: 0, y: 0, width: 24, height: navigationController?.navigationBar.frame.height ?? 0))
        backButton.didTap = { [weak self] in
            self?.close()
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)

        switch mode {
        case .library:
            setTitleViewWithTitle(aTitle: libraryVC?.title ?? "")
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: YPConfig.wordings.next,
                                                                style: .done,
                                                                target: self,
                                                                action: #selector(done))
            navigationItem.rightBarButtonItem?.tintColor = YPConfig.colors.tintColor

            // Disable Next Button until minNumberOfItems is reached.
            navigationItem.rightBarButtonItem?.isEnabled = libraryVC!.selection.count >= YPConfig.library.minNumberOfItems

        case .camera:
            navigationItem.titleView = nil
            title = cameraVC?.title
            navigationItem.rightBarButtonItem = nil
        case .video:
            navigationItem.titleView = nil
            title = videoVC?.title
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func close() {
        func handleClose() {
            // Cancelling exporting of all videos
            if let libraryVC = libraryVC {
                libraryVC.mediaManager.forseCancelExporting()
            }
            didClose?()
        }

        if isProcessing {
            YPConfig.triesToCloseWhileProcessing?(handleClose)
        } else {
            handleClose()
        }
    }

    // When pressing "Next"
    @objc
    func done() {
        guard let libraryVC = libraryVC else { print("⚠️ YPPickerVC >>> YPLibraryVC deallocated"); return }

        guard !isLoading else {
            return
        }

        if mode == .library {
            libraryVC.doAfterPermissionCheck { [weak self] in
                libraryVC.selectedMedia(photoCallback: { photo in
                    self?.didSelectItems?([YPMediaItem.photo(p: photo)])
                }, videoCallback: { video in
                    self?.didSelectItems?([YPMediaItem
                            .video(v: video)])
                }, multipleItemsCallback: { items in
                    self?.didSelectItems?(items)
                })
            }
        }
    }

    func stopAll() {
        libraryVC?.v.assetZoomableView.videoView.deallocate()
        videoVC?.stopCamera()
        cameraVC?.stopCamera()
    }
}

extension YPPickerVC: YPLibraryViewDelegate {
    public func libraryViewStartedLoading(withSpinner: Bool) {
        libraryVC?.isProcessing = true
        DispatchQueue.main.async {
            self.v.scrollView.isScrollEnabled = false
            self.libraryVC?.v.fadeInLoader()
            self.libraryVC?.v.assetViewContainer.spinnerView.isHidden = !withSpinner
            self.isLoading = true
            self.isLoadingDoneTimer?.invalidate()
            self.isLoadingDoneTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                self.navigationItem.rightBarButtonItem?.isEnabled = false
            }
        }
    }

    public func libraryViewFinishedLoading() {
        libraryVC?.isProcessing = false
        DispatchQueue.main.async {
            self.isLoading = false
            self.isLoadingDoneTimer?.invalidate()
            self.v.scrollView.isScrollEnabled = YPConfig.isScrollToChangeModesEnabled
            self.libraryVC?.v.hideLoader()
            self.updateUI()
        }
    }

    public func libraryViewDidToggleMultipleSelection(enabled: Bool) {
        updateUI()
    }

    public func noPhotosForOptions() {
        updateUI()
        self.imagePickerDelegate?.noPhotos()
    }

    public func didDeselectItem() {
        updateUI()
    }

    public func didStartProcessing() {
        isProcessing = true
        DispatchQueue.main.async {
            self.blockingView.isHidden = false
        }
    }

    public func didEndProcessing() {
        isProcessing = false
        DispatchQueue.main.async {
            self.blockingView.isHidden = true
        }
    }

    public func libraryDidChange() {
        albumsManager.resetCache()
        albumVC?.fetchAlbumsInBackground()
    }
}

extension YPPickerVC: YPPhotoCaptureDelegate {
    func willStartPhotoCapture() {
        DispatchQueue.main.async {
            self.isIgnoringInteraction = true
            UIApplication.shared.beginIgnoringInteractionEvents()
        }
    }

    func didCancelPhotoCapture() {
        DispatchQueue.main.async {
            if self.isIgnoringInteraction {
                self.isIgnoringInteraction = false
                UIApplication.shared.endIgnoringInteractionEvents()
            }
        }
    }
}

extension YPPickerVC: YPVideoCaptureDelegate {
    func willStartVideoCapture(completion: (() -> Void)?) {
        completion?()
    }
}
