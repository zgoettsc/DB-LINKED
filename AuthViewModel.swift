import Foundation
import FirebaseAuth
import Combine

class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: AuthUser?
    @Published var errorMessage: String?
    @Published var isProcessing = false
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    
    init() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            if let user = user {
                self.currentUser = AuthUser(user: user)
                self.authState = .signedIn
            } else {
                self.currentUser = nil
                self.authState = .signedOut
            }
        }
        
        // Note: Firebase Auth uses .localLevel by default anyway
        // so we don't need to explicitly set it
    }
    
    deinit {
        if let authStateHandler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(authStateHandler)
        }
    }
    
    // Sign in with email and password
    func signIn(email: String, password: String) {
        isProcessing = true
        errorMessage = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            self.isProcessing = false
            
            if let error = error {
                self.handleAuthError(error)
                return
            }
            
            // Successfully signed in
            if let user = result?.user {
                self.currentUser = AuthUser(user: user)
                self.authState = .signedIn
            }
        }
    }
    
    // Sign up with email and password
    func signUp(name: String, email: String, password: String) {
        isProcessing = true
        errorMessage = nil
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isProcessing = false
                self.handleAuthError(error)
                return
            }
            
            // Set the user's display name
            let changeRequest = result?.user.createProfileChangeRequest()
            changeRequest?.displayName = name
            changeRequest?.commitChanges { [weak self] error in
                guard let self = self else { return }
                self.isProcessing = false
                
                if let error = error {
                    self.errorMessage = "Error updating profile: \(error.localizedDescription)"
                    return
                }
                
                // Successfully created account and set display name
                if let user = result?.user {
                    self.currentUser = AuthUser(user: user)
                    self.authState = .signedIn
                }
            }
        }
    }
    
    // Reset password for email
    func resetPassword(email: String, completion: @escaping (Bool) -> Void) {
        isProcessing = true
        errorMessage = nil
        
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            guard let self = self else { return }
            self.isProcessing = false
            
            if let error = error {
                self.handleAuthError(error)
                completion(false)
                return
            }
            
            completion(true)
        }
    }
    
    // Sign out
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.authState = .signedOut
            self.currentUser = nil
        } catch {
            self.errorMessage = "Error signing out: \(error.localizedDescription)"
        }
    }
    
    // Handle Firebase Auth errors
    private func handleAuthError(_ error: Error) {
        let authError: AuthError
        
        if let errorCode = AuthErrorCode(rawValue: (error as NSError).code) {
            switch errorCode {
            case .invalidEmail:
                authError = .invalidEmail
            case .wrongPassword:
                authError = .invalidCredentials
            case .emailAlreadyInUse:
                authError = .emailInUse
            case .weakPassword:
                authError = .weakPassword
            default:
                authError = .unknown(message: error.localizedDescription)
            }
        } else {
            authError = .unknown(message: error.localizedDescription)
        }
        
        self.errorMessage = authError.message
    }
}
