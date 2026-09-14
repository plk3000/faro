@preconcurrency import AVFoundation
import Foundation

final class CameraImageSource:
    NSObject,
    ImageSource,
    @unchecked Sendable,
    AVCapturePhotoCaptureDelegate
{
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(
        label: "com.jdsolissmith.faro.camera-session"
    )
    private let continuationLock = NSLock()

    private var isConfigured = false
    private var captureContinuation:
        CheckedContinuation<CapturedImage, Error>?

    func prepare() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw ImageSourceError.permissionDenied
            }
        case .denied, .restricted:
            throw ImageSourceError.permissionDenied
        @unknown default:
            throw ImageSourceError.permissionDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func capture() async throws -> CapturedImage {
        try await prepare()

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                let accepted = continuationLock.withLock {
                    guard captureContinuation == nil else {
                        return false
                    }
                    captureContinuation = continuation
                    return true
                }

                guard accepted else {
                    continuation.resume(
                        throwing: ImageSourceError.captureInProgress
                    )
                    return
                }

                let settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
                )
                settings.photoQualityPrioritization = .balanced
                photoOutput.capturePhoto(
                    with: settings,
                    delegate: self
                )
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw ImageSourceError.cameraUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw ImageSourceError.configurationFailed
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            throw ImageSourceError.configurationFailed
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let result: Result<CapturedImage, Error>
        if error != nil {
            result = .failure(ImageSourceError.captureFailed)
        } else if let data = photo.fileDataRepresentation(), !data.isEmpty {
            result = .success(
                CapturedImage(data: data, format: .jpeg)
            )
        } else {
            result = .failure(ImageSourceError.invalidImageData)
        }

        let continuation = continuationLock.withLock {
            defer { captureContinuation = nil }
            return captureContinuation
        }
        continuation?.resume(with: result)
    }
}
