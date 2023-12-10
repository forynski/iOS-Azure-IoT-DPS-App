import UIKit
import AzureIoTHubClient
import Foundation
import CoreMotion

class ViewController: UIViewController {
    
    private let connectionString = "HostName=IoTHubUoD.azure-devices.net;DeviceId=iPhone;SharedAccessKey=ud4o53zYfWIcEg4d8q0PaCcynGVr53YoUAIoTGdqH0o="
    private let iotProtocol: IOTHUB_CLIENT_TRANSPORT_PROVIDER = MQTT_Protocol
    private var iotHubClientHandle: IOTHUB_CLIENT_LL_HANDLE!
    
    private let motionManager = CMMotionManager()
    
    @IBOutlet weak var btnStart: UIButton!
    @IBOutlet weak var btnStop: UIButton!
    @IBOutlet weak var lblSent: UILabel!
    @IBOutlet weak var lblGood: UILabel!
    @IBOutlet weak var lblBad: UILabel!
    @IBOutlet weak var lblRcvd: UILabel!
    @IBOutlet weak var lblLastTemp: UILabel!
    @IBOutlet weak var lblLastHum: UILabel!
    @IBOutlet weak var lblLastRcvd: UILabel!
    @IBOutlet weak var lblLastSent: UILabel!
    
    var cntSent = 0
    var cntGood: Int = 0
    var cntBad = 0
    var cntRcvd = 0
    var randomTelem: String!
    
    var timerMsgRate: Timer!
    var timerDoWork: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        motionManager.accelerometerUpdateInterval = 0.1
    }

    
    @IBAction func startSend(sender: UIButton!) {
        btnStart.isEnabled = false
        btnStop.isEnabled = true
        cntSent = 0
        lblSent.text = String(cntSent)
        cntGood = 0
        lblGood.text = String(cntGood)
        cntBad = 0
        lblBad.text = String(cntBad)
        
        iotHubClientHandle = IoTHubClient_LL_CreateFromConnectionString(connectionString, iotProtocol)
        
        if (iotHubClientHandle == nil) {
            showError(message: "Failed to create IoT handle", startState: true, stopState: false)
            return
        }
        
        let that = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        if (IOTHUB_CLIENT_OK != (IoTHubClient_LL_SetMessageCallback(iotHubClientHandle, myReceiveMessageCallback, that))) {
            showError(message: "Failed to establish received message callback", startState: true, stopState: false)
            return
        }
        
        updateTelemWithAccelerometerData()
        
        timerMsgRate = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(sendMessage), userInfo: nil, repeats: true)
        timerDoWork = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(dowork), userInfo: nil, repeats: true)
    }
    
    @IBAction public func stopSend(sender: UIButton!) {
        timerMsgRate?.invalidate()
        timerDoWork?.invalidate()
        motionManager.stopAccelerometerUpdates()
        IoTHubClient_LL_Destroy(iotHubClientHandle)
        btnStart.isEnabled = true
        btnStop.isEnabled = false
    }
    
    func updateTelemWithAccelerometerData() {
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer not available")
            return
        }
        
        motionManager.startAccelerometerUpdates(to: .main) { (data, error) in
            guard let acceleration = data?.acceleration else {
                print("Error getting accelerometer data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            let accelerometerData = [
                "accelerationX": acceleration.x,
                "accelerationY": acceleration.y,
                "accelerationZ": acceleration.z
            ]
            
            self.randomTelem = accelerometerData.description
//            self.lblLastTemp.text = "X: \(acceleration.x)"
//            self.lblLastHum.text = "Y: \(acceleration.y)"
        }
    }
    
    @objc func sendMessage() {
        var messageString: String!
        updateTelemWithAccelerometerData()
        messageString = randomTelem
        lblLastSent.text = messageString
        
        let messageHandle: IOTHUB_MESSAGE_HANDLE = IoTHubMessage_CreateFromByteArray(messageString, messageString.utf8.count)
        
        if (messageHandle != OpaquePointer.init(bitPattern: 0)) {
            let that = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            
            if (IOTHUB_CLIENT_OK == IoTHubClient_LL_SendEventAsync(iotHubClientHandle, messageHandle, mySendConfirmationCallback, that)) {
                incrementSent()
            }
        }
    }
    
    // This is the function that will be called when a message confirmation is received
    let mySendConfirmationCallback: IOTHUB_CLIENT_EVENT_CONFIRMATION_CALLBACK = { result, userContext in
        
        var mySelf: ViewController = Unmanaged<ViewController>.fromOpaque(userContext!).takeUnretainedValue()
        
        if (result == IOTHUB_CLIENT_CONFIRMATION_OK) {
            mySelf.incrementGood()
        }
        else {
            mySelf.incrementBad()
        }
    }
    
    // This function is called when a message is received from the IoT hub
    let myReceiveMessageCallback: IOTHUB_CLIENT_MESSAGE_CALLBACK_ASYNC = { message, userContext in
        
        var mySelf: ViewController = Unmanaged<ViewController>.fromOpaque(userContext!).takeUnretainedValue()
        
        var messageId: String!
        var correlationId: String!
        var size: Int = 0
        var buff: UnsafePointer<UInt8>?
        var messageString: String = ""
        
        messageId = String(describing: IoTHubMessage_GetMessageId(message))
        correlationId = String(describing: IoTHubMessage_GetCorrelationId(message))
        
        if (messageId == nil) {
            messageId = "<nil>"
        }
        
        if correlationId == nil {
            correlationId = "<nil>"
        }
        
        mySelf.incrementRcvd()
        
        // Get the data from the message
        var rc: IOTHUB_MESSAGE_RESULT = IoTHubMessage_GetByteArray(message, &buff, &size)
        
        if rc == IOTHUB_MESSAGE_OK {
            for i in 0 ..< size {
                let out = String(buff![i], radix: 16)
                print("0x" + out, terminator: " ")
            }
            
            print()
            
            let data = Data(bytes: buff!, count: size)
            messageString = String.init(data: data, encoding: String.Encoding.utf8)!
            
            print("Message Id:", messageId, " Correlation Id:", correlationId)
            print("Message:", messageString)
            mySelf.lblLastRcvd.text = messageString
        }
        else {
            print("Failed to acquire message data")
            mySelf.lblLastRcvd.text = "Failed to acquire message data"
        }
        return IOTHUBMESSAGE_ACCEPTED
    }
    
    func incrementSent() {
        cntSent += 1
        lblSent.text = String(cntSent)
    }
    
    func incrementGood() {
        cntGood += 1
        lblGood.text = String(cntGood)
    }
    
    func incrementBad() {
        cntBad += 1
        lblBad.text = String(cntBad)
    }
    
    func incrementRcvd() {
        cntRcvd += 1
        lblRcvd.text = String(cntRcvd)
    }
    
//    func dowork() {
//        IoTHubClient_LL_DoWork(iotHubClientHandle)
//    }
    
    @objc func dowork() {
        IoTHubClient_LL_DoWork(iotHubClientHandle)
    }
    
    func showError(message: String, startState: Bool, stopState: Bool) {
        btnStart.isEnabled = startState
        btnStop.isEnabled = stopState
        print(message)
    }
}
