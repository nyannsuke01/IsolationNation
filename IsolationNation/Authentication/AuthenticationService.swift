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
      // 1
      _ = Amplify.Auth.signIn(username: username, password: password) { [self] result in
        switch result {
        // 2
        case .failure(let error):
          logger.logError(error.localizedDescription)
          promise(.failure(error))
        // 3
        case .success:
          guard let authUser = Amplify.Auth.getCurrentUser() else {
            let authError = IsolationNationError.unexpctedAuthResponse
            logger.logError(authError)
            signOut()
            promise(.failure(authError))
            return
          }
          // 4
          cancellable = fetchUserModel(id: authUser.userId)
            .sink(receiveCompletion: { completion in
              switch completion {
              case .failure(let error):
                signOut()
                promise(.failure(error))
              case .finished:
                break
              }
            }, receiveValue: { user in
              setUserSessionData(user)
              promise(.success(.signedIn))
            })
        }
      }
    }
  }

  func signUp(as username: String, identifiedBy password: String, with email: String) -> Future<AuthenticationState, Error> {
    return Future { promise in
      // 1
      let userAttributes = [AuthUserAttribute(.email, value: email)]
      let options = AuthSignUpRequest.Options(userAttributes: userAttributes)
      // 2
      _ = Amplify.Auth.signUp(username: username, password: password, options: options) { [self] result in
        DispatchQueue.main.async {
          switch result {
          case .failure(let error):
            logger.logError(error.localizedDescription)
            promise(.failure(error))
          case .success(let amplifyResult):
            // 3
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
      // 1
      _ = Amplify.Auth.confirmSignUp(for: username, confirmationCode: confirmationCode) { [self] result in
        switch result {
        case .failure(let error):
          logger.logError(error.localizedDescription)
          promise(.failure(error))
        case .success:
          // 2
          _ = Amplify.Auth.signIn(username: username, password: password) { result in
            switch result {
            case .failure(let error):
              logger.logError(error.localizedDescription)
              promise(.failure(error))
            case .success:
              // 3
              // 1
              guard let authUser = Amplify.Auth.getCurrentUser() else {
                let authError = IsolationNationError.unexpctedAuthResponse
                logger.logError(authError)
                promise(.failure(IsolationNationError.unexpctedAuthResponse))
                signOut()
                return
              }
              // 2
              let sub = authUser.userId
              let user = User(
                id: sub,
                username: username,
                sub: sub,
                postcode: nil,
                createdAt: Temporal.DateTime.now()
              )
              // 3
              _ = Amplify.API.mutate(request: .create(user)) { event in
                switch event {
                // 4
                case .failure(let error):
                  signOut()
                  promise(.failure(error))
                case .success(let result):
                  switch result {
                  case .failure(let error):
                    signOut()
                    promise(.failure(error))
                  case .success(let user):
                    // 5
                    setUserSessionData(user)
                    promise(.success(.signedIn))
                  }
                }
              }                }
          }
        }
      }
    }
  }

  func signOut() {
    setUserSessionData(nil)
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
    // 1
    _ = Amplify.Auth.fetchAuthSession { [self] result in
      switch result {
      // 2
      case .failure(let error):
        logger.logError(error)
        signOut()

      // 3
      case .success(let session):
        if !session.isSignedIn {
          setUserSessionData(nil)
          return
        }

        // 4
        guard let authUser = Amplify.Auth.getCurrentUser() else {
          let authError = IsolationNationError.unexpctedAuthResponse
          logger.logError(authError)
          signOut()
          return
        }
        let sub = authUser.userId
        cancellable = fetchUserModel(id: sub)
          .sink(receiveCompletion: { completion in
            switch completion {
            case .failure(let error):
              logger.logError(error)
              signOut()
            case .finished: ()
            }
          }, receiveValue: { user in
            setUserSessionData(user)
          })
      }
    }
  }

  // MARK: Private

  private func setUserSessionData(_ user: User?) {
    DispatchQueue.main.async {
      if let user = user {
        self.userSession.loggedInUser = user
      } else {
        self.userSession.loggedInUser = nil
      }
    }
  }

  private func fetchUserModel(id: String) -> Future<User, Error> {
    // 1
    return Future { promise in
      // 2
      _ = Amplify.API.query(request: .get(User.self, byId: id)) { [self] event in
        // 3
        switch event {
        case .failure(let error):
          logger.logError(error.localizedDescription)
          promise(.failure(error))
          return
        case .success(let result):
          // 4
          switch result {
          case .failure(let resultError):
            logger.logError(resultError.localizedDescription)
            promise(.failure(resultError))
            return
          case .success(let user):
            // 5
            guard let user = user else {
              let error = IsolationNationError.unexpectedGraphQLData
              logger.logError(error.localizedDescription)
              promise(.failure(error))
              return
            }
            promise(.success(user))
          }
        }
      }
    }
  }
}
