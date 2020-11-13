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

import UIKit
import Combine
import Amplify


enum AuthenticationState {
  case startingSignUp
  case startingSignIn
  case awaitingConfirmation(String, String)
  case signedIn
  case errored(Error)
}

public final class AuthenticationService {
  let userSession: UserSession
  var logger = Logger()
  var cancellable: AnyCancellable?

  init(userSession: UserSession) {
    self.userSession = userSession
  }

  // MARK: Public API

    func signIn(as username: String, identifiedBy password: String) -> Future<AuthenticationState, Error> {
        return Future { promise in
            // 1ユーザー名とパスワードを渡して、AmplifyサインインAPIを呼び出します。
            _ = Amplify.Auth
                .signIn(username: username, password: password) { [self] result in
                    switch result {
                    // 2 障害をチェックして処理します。
                    case .failure(let error):
                        logger.logError(error.localizedDescription)
                        promise(.failure(error))
                    // 3 成功したら、現在ログインしているユーザーを取得します。
                    case .success:
                        guard let authUser = Amplify.Auth.getCurrentUser() else {
                            let authError = IsolationNationError.unexpctedAuthResponse
                            logger.logError(authError)
                            signOut()
                            promise(.failure(authError))
                            return
                        }
                        // 4 以前と同様に、ユーザーセッションでユーザーの詳細を設定します。
                        setUserSessionData(authUser.username)
                    }
                }
        }
    }

  func signUp(as username: String, identifiedBy password: String, with email: String) -> Future<AuthenticationState, Error> {
    return Future { promise in
      // 1 電子メールによるサインアップを期待するようにサインアップ要求を構成します。
      let userAttributes = [AuthUserAttribute(.email, value: email)]
      let options = AuthSignUpRequest.Options(userAttributes: userAttributes)
      // 2 Amplifyを使用してサインアップを実行します。前の例で行ったように結果を処理します。
      _ = Amplify.Auth.signUp(
        username: username,
        password: password,
        options: options
      ) { [self] result in
        DispatchQueue.main.async {
          switch result {
          case .failure(let error):
            logger.logError(error.localizedDescription)
            promise(.failure(error))
          case .success(let amplifyResult):
            //3サインアップが成功した場合は、awaitingConfirmation状態を返します。Amplifyは、提供されたアドレスの所有権を確認するために、ユーザーに電子メールでコードを送信します。
            if case .confirmUser = amplifyResult.nextStep {
              promise(.success(.awaitingConfirmation(username, password)))
            } else {
              let error = IsolationNationError.unexpctedAuthResponse
              logger.logError(error.localizedDescription)
              promise(.failure(error))
            }
          }
        }
      }
    }
  }

  func confirmSignUp(for username: String, with password: String, confirmedBy confirmationCode: String) -> Future<AuthenticationState, Error> {
    return Future { promise in
      // 1 Amplifyでサインアップを確認し、通常の方法で応答を処理します。
      _ = Amplify.Auth.confirmSignUp(
        for: username,
        confirmationCode: confirmationCode
      ) { [self] result in
        switch result {
        case .failure(let error):
          logger.logError(error.localizedDescription)
          promise(.failure(error))
        case .success:
          // 2 成功したら、ユーザーをサインインします。
          _ = Amplify.Auth.signIn(
            username: username,
            password: password
          ) { result in
            switch result {
            case .failure(let error):
              logger.logError(error.localizedDescription)
              promise(.failure(error))
            case .success:
              // 3 checkAuthSession()を呼び出します。これにより、ユーザーセッションが設定されます。
              checkAuthSession()
            }
          }
        }
      }
    }
  }

  func signOut() {
    _ = Amplify.Auth.signOut { [self] result in
      switch result {
      case .failure(let error):
        logger.logError(error)
      default:
        break
      }
    }
  }

  func checkAuthSession() {
    // To implement
    // 1Amplifyに現在の認証セッションを要求します。
    _ = Amplify.Auth.fetchAuthSession { [self] result in
      switch result {
      // 2エラーがある場合は、ユーザーをサインアウトします。
      case .failure(let error):
        logger.logError(error)
        signOut()

      // 3成功したら、ユーザーがサインインしていることを確認します。
      case .success(let session):
        if !session.isSignedIn {
          setUserSessionData(nil)
          return
        }

        // 4ユーザーがサインインしている場合は、現在のユーザーを取得し、ユーザーセッションの詳細を設定します。
        guard let authUser = Amplify.Auth.getCurrentUser() else {
          let authError = IsolationNationError.unexpctedAuthResponse
          logger.logError(authError)
          signOut()
          return
        }
        setUserSessionData(authUser.username)
      }
    }
  }

  // MARK: Private

  private func setUserSessionData(_ user: String?) {
    DispatchQueue.main.async {
      if let user = user {
        self.userSession.loggedInUser = user
      } else {
        self.userSession.loggedInUser = nil
      }
    }
  }
}
