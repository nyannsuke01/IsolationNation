/// Copyright (c) 2020 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import SwiftUI
import Combine

struct RepliesScreen: View {
  @ObservedObject private(set) var model: RepliesScreenViewModel

  var body: some View {
    Loadable(loadingState: model.replyListState) { replyList in
      ZStack {
        Color.backgroundColor
          .edgesIgnoringSafeArea(.all)
        VStack(alignment: .leading) {
          MessageDetailsHeader(message: $model.message.wrappedValue)
          Text("Replies")
            .font(.caption)
            .padding(.leading)
          Divider()
          RepliesView(
            repliesList: replyList
          )
          ReplyInputBar(model: model)
        }
        .background(Color.backgroundColor)
        .navigationBarTitle(Text("Replies"))
        .keyboardAdaptive()
      }
    }.onAppear {
      model.perform(action: .fetchReplies)
      model.perform(action: .subscribe)
    }
  }
}

struct RepliesScreen_Previews: PreviewProvider {
  static var previews: some View {
    let sampleMessage = MessageModel(
      id: "0",
      body: "Help Needed. Can somebody buy me some groceries please",
      authorName: "Lizzie",
      messageThreadId: "0",
      createdAt: Date()
    )
    let sampleData = [
      ReplyModel(id: "0", body: "Sure, what do you need?", authorName: "Charlie", messageId: "0", createdAt: Date()),
      ReplyModel(id: "1", body: "Yup! Give me a call?", authorName: "Andy", messageId: "0", createdAt: Date())
    ]

    return RepliesScreen(
      model: RepliesScreenViewModel(
        userSession: UserSession(),
        messageID: "0",
        message: sampleMessage,
        replies: sampleData
      )
    )
      .environmentObject(UserSession())
  }
}
