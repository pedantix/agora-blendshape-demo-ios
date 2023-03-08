//
//  BlendShapeViewController.swift
//  AgoraBlendShapeDemo
//
//  Created by Deenan on 14/12/22.
//

import UIKit
import ARKit
import SceneKit
import AgoraRtcKit
import AgoraRtmKit
import VideoToolbox


class BlendShapeViewController: UIViewController {
    
    var channelName: String = ""
    var agoraKit: AgoraRtcEngineKit!
    var rtmKit: AgoraRtmKit?
    var rtmChannel: AgoraRtmChannel?
    var currentImage: CGImage?
    var rawImage: CIImage?
    var size: CGSize?
  
    let enableDetectBodyPoints = true
    let useNewCalculationMethod = true
    let messageTimeInterval: Double = 0.33
    let imageProcessTimeInterval: Double = 0.1
    let fileSaveTimeInterval: TimeInterval = 1.0
    var blendshapesLocation = ""
    var lastSentBlendshapesLocation = ""
    var messageTimer = Timer()
    var imageProcessTimer = Timer()
    private var fileSaveTimer: Timer!
    var layersDictionary = [VNHumanBodyPoseObservation.JointName: CAShapeLayer]()
    let circleSize: CGFloat = 20
    var sequenceHandler = VNSequenceRequestHandler()
    var yaw: Float = 0
    var pitch: Float = 0
    var roll: Float = 0

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var micButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        sceneView.delegate = self
        joinChannel()
        self.rtmLogin()
    }
    
    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
            
      // 1
      let configuration = ARFaceTrackingConfiguration()
      // 2
      sceneView.session.run(configuration)
    }
        
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 1
        sceneView.session.pause()
        agoraKit.leaveChannel(nil)
        self.rtmChannel?.leave()
        self.rtmKit?.logout()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.cleanAndOrCreateTrainingDataDirectory()
        self.size = self.sceneView.bounds.size
        self.startMessageTimer()
        self.startFileSaveTimer()
        if self.enableDetectBodyPoints {
            self.startImageProcessTimer()
        }
    }
    
    @IBAction func micButtonAction(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            //mute mic
            self.agoraKit.muteLocalAudioStream(true)
        }else {
            //unmute mic
            self.agoraKit.muteLocalAudioStream(false)
        }
    }
    
    func joinChannel() {
        // set up agora instance when view loaded
        let config = AgoraRtcEngineConfig()
        config.appId = appId
        config.areaCode = .global
        config.channelProfile = .liveBroadcasting
        // set audio scenario
        config.audioScenario = .default
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        
        // make myself a broadcaster
        agoraKit.setClientRole(.broadcaster)
        
        // disable video module
        agoraKit.disableVideo()
        agoraKit.enableAudio()
        
        // set audio profile
        agoraKit.setAudioProfile(.default)
        
        // Set audio route to speaker
        agoraKit.setDefaultAudioRouteToSpeakerphone(true)
        
        let result = agoraKit.joinChannel(byToken: "", channelId: channelName, userAccount: "DDD", mediaOptions: AgoraRtcChannelMediaOptions())
        if result != 0 {
            // Usually happens with invalid parameters
            // Error code description can be found at:
            // en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
            // cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
            self.showAlert(title: "Error", message: "joinChannel call failed: \(result), please check your params")
        }
    }
    
    func rtmLogin() {
        self.rtmKit = AgoraRtmKit(appId: appId, delegate: self)
        self.rtmKit?.login(byToken: nil, user: "user", completion: { loginCode in
            if loginCode == .ok {
                self.rtmChannel = self.rtmKit?.createChannel(withId: self.channelName, delegate: self)
                self.rtmChannel?.join(completion: self.channelJoined(joinCode:))
            }
        })
    }
    
    func channelJoined(joinCode: AgoraRtmJoinChannelErrorCode) {
        if joinCode == .channelErrorOk {
            print("connected to channel")
        }
    }
    
    func showAlert(title: String? = nil, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alertController.addAction(action)
        self.present(alertController, animated: true, completion: nil)
    }

}

extension BlendShapeViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        
        // 3
        guard let device = sceneView.device else {
          return nil
        }
        
        // 4
        let faceGeometry = ARSCNFaceGeometry(device: device)
        
        // 5
        let node = SCNNode(geometry: faceGeometry)
        
        // 6
        node.geometry?.firstMaterial?.fillMode = .lines
        
        // 7
        return node
      }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        // 2
        guard let faceAnchor = anchor as? ARFaceAnchor,
              let faceGeometry = node.geometry as? ARSCNFaceGeometry else {
            return
        }
        
        // 3
        faceGeometry.update(from: faceAnchor.geometry)
        
        // 4
        if self.useNewCalculationMethod {
            /*let (y, p, r) = self.getHeadValues()
            yaw = y
            pitch = p
            roll = r*/
            
            if let image = sceneView.session.currentFrame?.capturedImage {
                let detectFaceRectanglesRequest = VNDetectFaceRectanglesRequest(completionHandler: detectedFaceRectangles)
                detectFaceRectanglesRequest.revision = VNDetectFaceRectanglesRequestRevision3
                
                do {
                    try sequenceHandler.perform(
                        [detectFaceRectanglesRequest],
                        on: image,
                        orientation: .leftMirrored)
                } catch {
                    print(error.localizedDescription)
                }
            }
        }else {
            let eulerAngles = faceAnchor.transform.eulerAngles
            yaw = eulerAngles.x
            pitch = eulerAngles.y
            roll = eulerAngles.z
            
            print("Yaw: \(yaw)")
            print("Pitch: \(pitch)")
            print("Roll: \(roll)")
            print("\n")
        }
        
        let blendShapes = faceAnchor.blendShapes
            
        self.blendshapesLocation = "\(String(describing: blendShapes[.browDownLeft]!)),\(String(describing: blendShapes[.browDownRight]!)),\(String(describing: blendShapes[.browInnerUp]!)),\(String(describing: blendShapes[.browOuterUpLeft]!)),\(String(describing: blendShapes[.browOuterUpRight]!)),\(String(describing: blendShapes[.cheekPuff]!)),\(String(describing: blendShapes[.cheekSquintLeft]!)),\(String(describing: blendShapes[.cheekSquintRight]!)),\(String(describing: blendShapes[.eyeBlinkLeft]!)),\(String(describing: blendShapes[.eyeBlinkRight]!)),\(String(describing: blendShapes[.eyeLookDownLeft]!)),\(String(describing: blendShapes[.eyeLookDownRight]!)),\(String(describing: blendShapes[.eyeLookInLeft]!)),\(String(describing: blendShapes[.eyeLookInRight]!)),\(String(describing: blendShapes[.eyeLookOutLeft]!)),\(String(describing: blendShapes[.eyeLookOutRight]!)),\(String(describing: blendShapes[.eyeLookUpLeft]!)),\(String(describing: blendShapes[.eyeLookUpRight]!)),\(String(describing: blendShapes[.eyeSquintLeft]!)),\(String(describing: blendShapes[.eyeSquintRight]!)),\(String(describing: blendShapes[.eyeWideLeft]!)),\(String(describing: blendShapes[.eyeWideRight]!)),\(String(describing: blendShapes[.jawForward]!)),\(String(describing: blendShapes[.jawLeft]!)),\(String(describing: blendShapes[.jawOpen]!)),\(String(describing: blendShapes[.jawRight]!)),\(String(describing: blendShapes[.mouthClose]!)),\(String(describing: blendShapes[.mouthDimpleLeft]!)),\(String(describing: blendShapes[.mouthDimpleRight]!)),\(String(describing: blendShapes[.mouthFrownLeft]!)),\(String(describing: blendShapes[.mouthFrownRight]!)),\(String(describing: blendShapes[.mouthFunnel]!)),\(String(describing: blendShapes[.mouthLeft]!)),\(String(describing: blendShapes[.mouthLowerDownLeft]!)),\(String(describing: blendShapes[.mouthLowerDownRight]!)),\(String(describing: blendShapes[.mouthPressLeft]!)),\(String(describing: blendShapes[.mouthPressRight]!)),\(String(describing: blendShapes[.mouthPucker]!)),\(String(describing: blendShapes[.mouthRight]!)),\(String(describing: blendShapes[.mouthRollLower]!)),\(String(describing: blendShapes[.mouthRollUpper]!)),\(String(describing: blendShapes[.mouthShrugLower]!)),\(String(describing: blendShapes[.mouthShrugUpper]!)),\(String(describing: blendShapes[.mouthSmileLeft]!)),\(String(describing: blendShapes[.mouthSmileRight]!)),\(String(describing: blendShapes[.mouthStretchLeft]!)),\(String(describing: blendShapes[.mouthStretchRight]!)),\(String(describing: blendShapes[.mouthUpperUpLeft]!)),\(String(describing: blendShapes[.mouthUpperUpRight]!)),\(String(describing: blendShapes[.noseSneerLeft]!)),\(String(describing: blendShapes[.noseSneerRight]!)),\(String(describing: blendShapes[.tongueOut]!)),\(String(describing: yaw)), \(String(describing: pitch)), \(String(describing: roll))"
     

    }
    
    func detectedFaceRectangles(request: VNRequest, error: Error?) {
        guard
            let results = request.results as? [VNFaceObservation],
            let result = results.first
        else {
            return
        }
        
        self.yaw = result.yaw?.floatValue ?? 0
        self.pitch = result.pitch?.floatValue ?? 0
        self.roll = result.roll?.floatValue ?? 0
        
        print("Yaw: \(self.yaw)")
        print("Pitch: \(self.pitch)")
        print("Roll: \(self.roll)")
        print("\n")
        
    }
    
    func startFileSaveTimer() {
        self.fileSaveTimer = Timer.scheduledTimer(timeInterval: self.fileSaveTimeInterval, target: self, selector: #selector(saveFile), userInfo: .none, repeats: true)
    }
    
    func startMessageTimer() {
        self.messageTimer = Timer.scheduledTimer(withTimeInterval: self.messageTimeInterval, repeats: true, block: { [weak self] _ in
            self?.sendMessage()
        })
    }
    
    func startImageProcessTimer() {
        self.imageProcessTimer = Timer.scheduledTimer(withTimeInterval: self.imageProcessTimeInterval, repeats: true, block: { [weak self] _ in
            self?.startImageProcessing()
        })
    }
    
    func startImageProcessing() {
        
        let snapShot = self.sceneView.snapshot()
        if let newImage = snapShot.cgImage {
            
            self.currentImage = newImage
            self.getPointsFromImage(newImage)
        }
        
        if let rawSnapshot = sceneView.session.currentFrame {
            let ciImage = CIImage(cvPixelBuffer: rawSnapshot.capturedImage)
            self.rawImage = ciImage
        }
    }
    
    func sendMessage() {
        if !self.blendshapesLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           self.lastSentBlendshapesLocation != self.blendshapesLocation {
            self.lastSentBlendshapesLocation = self.blendshapesLocation
            
            print("Blend Shape json \(self.blendshapesLocation)")
            self.rtmChannel?.send(AgoraRtmMessage(text: "\(self.blendshapesLocation)"), completion: { sentCode in
                if sentCode != .errorOk {
                    print("could not send message")
                }else {
                    print("Message sent: \(Date())")
                }
            })
        }else {
            print("No data update")
            self.removeAllLayers()
        }
    }
    
    func getHeadValues() -> (Float, Float, Float) {
        
        guard let arFrame = self.sceneView.session.currentFrame,
              let faceAnchor = arFrame.anchors[0] as? ARFaceAnchor,
              let size = self.size else {
            return (0, 0, 0)
        }

        let projectionMatrix = arFrame.camera.projectionMatrix(for: .portrait, viewportSize: size, zNear: 0.001, zFar: 1000)
        let viewMatrix = arFrame.camera.viewMatrix(for: .portrait)

        let projectionViewMatrix = simd_mul(projectionMatrix, viewMatrix)
        let modelMatrix = faceAnchor.transform
        let mvpMatrix = simd_mul(projectionViewMatrix, modelMatrix)

        let newFaceMatrix = SCNMatrix4.init(mvpMatrix)
        let faceNode = SCNNode()
        faceNode.transform = newFaceMatrix
        let rotation = vector_float3(faceNode.worldOrientation.x, faceNode.worldOrientation.y, faceNode.worldOrientation.z)
        
        let yaw = -rotation.y*3
        let pitch = -rotation.x*3
        let roll = rotation.z*1.5
        
        print("Yaw: \(yaw)")
        print("Pitch: \(pitch)")
        print("Roll: \(roll)")
        print("\n")
        return (yaw, pitch, roll)
    }
    
    func getPointsFromImage(_ cgImage: CGImage) {

        // Create a new image-request handler.
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        // Create a new request to recognize a human body pose.
        let request = VNDetectHumanBodyPoseRequest(completionHandler: bodyPoseHandler)

        do {
            // Perform the body pose-detection request.
            try requestHandler.perform([request])
        } catch {
            print("Unable to perform the request: \(error).")
        }
    }
    
    func bodyPoseHandler(request: VNRequest, error: Error?) {
        guard let observations =
                request.results as? [VNHumanBodyPoseObservation] else {
            return
        }
        
        // Process each observation to find the recognized body pose points.
        observations.forEach { processObservation($0) }
    }
    
    func processObservation(_ observation: VNHumanBodyPoseObservation) {
        
        // Retrieve all torso points.
        guard let recognizedPoints =
                try? observation.recognizedPoints(.torso) else { return }
        
        var neckPoint = CGPoint.zero
        var leftShoulderPoint = CGPoint.zero
        var rightShoulderPoint = CGPoint.zero
        
        if let neck = recognizedPoints[.neck] {
            neckPoint = self.normalizePoint(neck.location)
            self.drawCircle(on: neckPoint, for: .neck)
        }
        if let leftShoulder = recognizedPoints[.leftShoulder] {
            leftShoulderPoint = self.normalizePoint(leftShoulder.location)
            self.drawCircle(on: leftShoulderPoint, for: .leftShoulder)
        }
        if let rightShoulder = recognizedPoints[.rightShoulder] {
            rightShoulderPoint = self.normalizePoint(rightShoulder.location)
            self.drawCircle(on: rightShoulderPoint, for: .rightShoulder)
        }

    }
    
    func normalizePoint(_ point: CGPoint) -> CGPoint {
        let frame = self.view.bounds
        let x = frame.width * point.x
        let y = frame.height * (1 - point.y)
        return CGPoint(x: x, y: y)
    }
}

extension BlendShapeViewController: AgoraRtcEngineDelegate {
    
    /// callback when warning occured for agora sdk, warning can usually be ignored, still it's nice to check out
    /// what is happening
    /// Warning code description can be found at:
    /// en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraWarningCode.html
    /// cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraWarningCode.html
    /// @param warningCode warning code of the problem
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        print("warning: \(warningCode)")
    }
    
    /// callback when error occured for agora sdk, you are recommended to display the error descriptions on demand
    /// to let user know something wrong is happening
    /// Error code description can be found at:
    /// en: https://docs.agora.io/en/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
    /// cn: https://docs.agora.io/cn/Voice/API%20Reference/oc/Constants/AgoraErrorCode.html
    /// @param errorCode error code of the problem
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("error: \(errorCode)")
        self.showAlert(title: "Error", message: "Error \(errorCode) occur")
    }
    
}

extension BlendShapeViewController: AgoraRtmChannelDelegate, AgoraRtmDelegate {
    
}

extension matrix_float4x4 {
    // Function to convert rad to deg
    func radiansToDegress(radians: Float32) -> Float32 {
        return radians * 180 / (Float32.pi)
    }
    var translation: SCNVector3 {
        get {
            return SCNVector3Make(columns.3.x, columns.3.y, columns.3.z)
        }
    }
    // Retrieve euler angles from a quaternion matrix
    var eulerAngles: SCNVector3 {
        get {
            // Get quaternions
            let qw = sqrt(1 + self.columns.0.x + self.columns.1.y + self.columns.2.z) / 2.0
            let qx = (self.columns.2.y - self.columns.1.z) / (qw * 4.0)
            let qy = (self.columns.0.z - self.columns.2.x) / (qw * 4.0)
            let qz = (self.columns.1.x - self.columns.0.y) / (qw * 4.0)
            
            // Deduce euler angles
            /// yaw (z-axis rotation)
            let siny = +2.0 * (qw * qz + qx * qy)
            let cosy = +1.0 - 2.0 * (qy * qy + qz * qz)
            let yaw = radiansToDegress(radians:atan2(siny, cosy))
            // pitch (y-axis rotation)
            let sinp = +2.0 * (qw * qy - qz * qx)
            var pitch: Float
            if abs(sinp) >= 1 {
                pitch = radiansToDegress(radians:copysign(Float.pi / 2, sinp))
            } else {
                pitch = radiansToDegress(radians:asin(sinp))
            }
            /// roll (x-axis rotation)
            let sinr = +2.0 * (qw * qx + qy * qz)
            let cosr = +1.0 - 2.0 * (qx * qx + qy * qy)
            let roll = radiansToDegress(radians:atan2(sinr, cosr))
            
            /// return array containing ypr values
            return SCNVector3(yaw, pitch, roll)
        }
    }
}

// MARK: - Draw circle
extension BlendShapeViewController {
    
    func drawCircle(on point: CGPoint, for jointName: VNHumanBodyPoseObservation.JointName) {
        
        if let layer = self.getLayer(for: jointName) {
            self.updateLayerPosition(point, layer: layer)
        }else {
            self.addLayer(on: point, for: jointName)
        }
    }
    
    func addLayer(on point: CGPoint, for jointName: VNHumanBodyPoseObservation.JointName) {
        let radius = circleSize/2
        let ellipsePath = UIBezierPath(ovalIn: CGRectMake(point.x - radius, point.y - radius, circleSize, circleSize))
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = ellipsePath.cgPath
        shapeLayer.fillColor = UIColor.systemGreen.cgColor
        
        self.view.layer.insertSublayer(shapeLayer, at: UInt32(self.view.layer.sublayers?.count ?? 0))
        
        self.saveReference(of: shapeLayer, for: jointName)
    }
    
    func saveReference(of layer: CAShapeLayer, for jointName: VNHumanBodyPoseObservation.JointName) {
        self.layersDictionary[jointName] = layer
    }
    
    func getLayer(for jointName: VNHumanBodyPoseObservation.JointName) -> CAShapeLayer? {
        let layer = self.layersDictionary[jointName]
        return layer
    }
    
    func updateLayerPosition(_ position: CGPoint, layer: CAShapeLayer) {

        let radius = circleSize/2
        let ellipsePath = UIBezierPath(ovalIn: CGRectMake(position.x - radius, position.y - radius, circleSize, circleSize))
        layer.path = ellipsePath.cgPath
    }
    
    func removeAllLayers() {
        self.layersDictionary.forEach { _, layer in
            layer.removeFromSuperlayer()
        }
        self.layersDictionary = [:]
    }
}

// MARK: -
// MARK: - Save files in specified format for CSV and images to Files domain
extension BlendShapeViewController {
    
    
    private func cleanAndOrCreateTrainingDataDirectory() {
        guard let directoryUrl = getURLOfTrainingDataDirectory() else { return print("\(#function) failed to get base directory URL") }
        let fm = FileManager.default
        do {
            // If directory exists remove it
            var isDir:ObjCBool = true
            if try fm.fileExists(atPath: directoryUrl.path, isDirectory: &isDir){
                try fm.removeItem(at: directoryUrl)
            }
            try fm.createDirectory(at: directoryUrl, withIntermediateDirectories: false)
        } catch {
            print("\(#function) ERROR \(error.localizedDescription)")
        }
    }
    
    @objc private func saveFile() {
        guard let rawImage = rawImage else { return print("\(#function) failed no current image") }
        guard blendshapesLocation.count > 10 else { return print("\(#function) failed blend shape lcations is too short")}
        
        let timestamp = Date().timeIntervalSince1970
        saveBlendDataToFile(timestamp)
        saveCIImageToPNGFile(timestamp, rawImage)
        print("\(#function) save current image to file")
        
    }
    
    private func saveBlendDataToFile(_ timeStamp: TimeInterval) {
        guard let url = getSaveURLfor("bs-\(timeStamp).csv") else { return print("\(#function) Error failed to save because of nil URL") }
        do {
            try self.blendshapesLocation.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("\(#function) Error Writing blend data, because \(error.localizedDescription)")
        }
    }
    
    private func saveCIImageToPNGFile(_ timeStamp: TimeInterval, _ sourceImage: CIImage) {
        let context = CIContext()
        let resizeFilter = CIFilter(name:"CILanczosScaleTransform")!

        // Desired output size
        let targetSize = CGSize(width:640, height:360)

        // Compute scale and corrective aspect ratio
        let scale = targetSize.height / (sourceImage.extent.height)
        let aspectRatio = targetSize.width/((sourceImage.extent.width) * scale)

        // Apply resizing
        resizeFilter.setValue(sourceImage, forKey: kCIInputImageKey)
        resizeFilter.setValue(scale, forKey: kCIInputScaleKey)
        resizeFilter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)
        guard let outputImage = resizeFilter.outputImage else { return print("\(#function) Error getting resampled image") }
        
        //guard let url = getSaveURLfor("pic-\(timeStamp).png") else { return print("\(#function) Error failed to save because of nil URL")
            guard let url = getSaveURLfor("pic-\(timeStamp).jpg") else { return print("\(#function) Error failed to save because of nil URL")
        }
        
        guard let colorspace = sourceImage.colorSpace else { return print("\(#function) error getting colorspae") }
        let imageProperties = [kCGImageDestinationLossyCompressionQuality as String: 0.8]
       // [CIImageRepresentationOption : Any] = [:]
        do {
            //try context.writePNGRepresentation(of: outputImage, to: url, format: .RGBA8, colorSpace: colorspace)
            try context.writeJPEGRepresentation(of: outputImage, to: url, colorSpace: colorspace, options:  [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption : 0.8] )
            
            print("\(#function) successfully wrote png to  url \(url)")
        } catch {
            
            print("\(#function) Error Writing image, because \(error.localizedDescription)")
        }
    }
    
    private func getURLOfTrainingDataDirectory() -> URL? {
        guard let baseUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("\(#function)Error getting user domain document directory, check plist")
            return nil
        }

        return baseUrl.appendingPathComponent("mopac")
    }
    
    private func getSaveURLfor(_ fileName: String) -> URL? {
        return getURLOfTrainingDataDirectory()?.appending(component: fileName)
    }
}

