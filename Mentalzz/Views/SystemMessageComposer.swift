//
//  SystemMessageComposer.swift
//  Mentalzz
//
//  Wraps MFMessageComposeViewController. This is the only route iOS gives an
//  app for sending an SMS/iMessage, and it always shows the sheet — the owner
//  taps send themselves. In exchange, iOS tells us the real result, which the
//  wa.me deep link can't.
//

import SwiftUI
import MessageUI

struct SystemMessageComposer: UIViewControllerRepresentable {

    let recipient: String
    let body: String
    /// .sent, .cancelled or .failed, straight from MessageUI.
    let onFinish: (MessageComposeResult) -> Void

    /// False on iPad without an iPhone paired for Text Message Forwarding, and
    /// in the simulator. Check before presenting.
    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}
