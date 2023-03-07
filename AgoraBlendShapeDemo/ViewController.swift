//
//  ViewController.swift
//  AgoraBlendShapeDemo
//
//  Created by Deenan on 14/12/22.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var channelNameTextField: UITextField!
    @IBOutlet weak var joinButton: UIButton!
    

    override func viewDidLoad() {
        super.viewDidLoad()
        channelNameTextField.text = "mocap"
    }

    @IBAction func onJoinButtonTapped(_ sender: UIButton) {
        if let channelName = channelNameTextField.text, channelName.count > 0 {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let vc = storyboard.instantiateViewController(withIdentifier: "blendShape") as? BlendShapeViewController
            vc?.channelName = channelName //.uppercased() -> uncomment if you want to send it as uppercased
            vc?.modalPresentationStyle = .fullScreen
            self.present(vc!, animated: true)
        }
    }
}

extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        channelNameTextField.endEditing(true)
        return true
    }
}


