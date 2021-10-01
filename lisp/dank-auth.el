;;; dank-auth.el --- Major mode for browsing Reddit

;; Copyright (C) 2021 John Louis Del Rosario

;; Author: John Louis Del Rosario <john2x@gmail.com>
;; Version: 0.1.3
;; Keywords: reddit, social

;;; Commentary:

;; This file defines functions for authenticating with Reddit.

;;; Code:

(require 'dank-url)
(require 'json)
(require 'dank-utils)


(defcustom dank-auth-file (expand-file-name "~/.emacs.d/dank-mode/auth.json")
  "Path to a JSON file containing your Reddit auth info.
Refer to auth.example.json included in this package for example format."
  :type 'string
  :group 'dank-mode)

(defcustom dank-auth-username nil
  "Your Reddit username.  This _should_ be set via `dank-auth-file'."
  :type 'string
  :group 'dank-mode)

(defcustom dank-auth-password nil
  "Your Reddit password.  This _should_ be set via `dank-auth-file'."
  :type 'string
  :group 'dank-mode)

(defcustom dank-auth-oauth-client-id nil
  "Your Reddit OAuth client id.  This _should_ be set via `dank-auth-file'.
For instructions on how to retrieve the client id, refer to this package's
README file."
  :type 'string
  :group 'dank-mode)

(defcustom dank-auth-oauth-client-secret nil
  "Your Reddit OAuth client secret.
This _should_ be set via `dank-auth-file'.
For instructions on how to retrieve the client secret, refer to this package's
README file."
  :type 'string
  :group 'dank-mode)

(defcustom dank-auth-user-agent nil
  "User agent value to use when requesting the Reddit API.
This can be set via `dank-auth-file'.  This variable is optional, and
by default will be a concatenation of the string \"Emacs dank-mode/\" plus your
username."
  :type 'string
  :group 'dank-mode)

(defvar dank-auth--token-expiry-threshold-seconds 300
  "The threshold in seconds to consider an access token as invalid.")

(defvar dank-auth--token-storage nil)

(define-error 'dank-auth-error "dank-auth error" 'error)
(define-error 'dank-auth-token-refresh-error "Failed to refresh access token" 'dank-auth-error)

(defun dank-auth-load-auth-vars-from-file (path)
  "Read and set auth values from PATH."
  (when (file-exists-p path)
    (let* ((json-object-type 'plist)
           (data (json-read-file path)))
      (when data
        (setq dank-auth-username (plist-get data :username))
        (setq dank-auth-password (plist-get data :password))
        (setq dank-auth-oauth-client-id (plist-get data :oauthClientId))
        (setq dank-auth-oauth-client-secret (plist-get data :oauthClientSecret))
        (setq dank-auth-user-agent (or (plist-get data :userAgent)
                                       (concat "Emacs dank-mode/" dank-auth-username)))
        data))))

(defun dank-auth-configured-p ()
  "Return t if the following auth vars are set.
- dank-auth-username
- dank-auth-password
- dank-auth-oauth-client-id
- dank-auth-oauth-client-secret"
  (and dank-auth-username dank-auth-password
       dank-auth-oauth-client-id dank-auth-oauth-client-secret))

(defun dank-auth-token-refresh (&optional force-refresh)
  "Retrieve new token data and store it in dank-auth--token-storage.
When FORCE-REFRESH is non-nil, then force the refresh."
  (when (and (dank-auth-configured-p) (or force-refresh (not (dank-auth--token-valid-p))))
    (let* ((authorization (base64-encode-string (concat dank-auth-oauth-client-id ":"
                                                        dank-auth-oauth-client-secret)))
           (full-url "https://www.reddit.com/api/v1/access_token")
           (url-user-agent dank-auth-user-agent)
           (url-request-method "POST")
           (url-request-extra-headers `(("Authorization" . ,(concat "Basic " authorization))
                                        ("Content-Type" . "application/x-www-form-urlencoded")))
           (url-request-data (dank-url-encode-alist `(("grant_type" . "password")
                                                      ("username" . ,dank-auth-username)
                                                      ("password" . ,dank-auth-password))))
           (response-buf (url-retrieve-synchronously full-url)))
      ;; cleanup
      (setq url-request-method nil
            url-request-extra-headers nil
            url-request-data nil)
      (with-current-buffer response-buf
        (let* ((response-status-code (dank-url-response-status-code))
               (response-content-type (dank-url-response-header "content-type"))
               (response-content (dank-url-response-uncompress))
               (response-json (if (string-match-p "^application/json" response-content-type)
                                  (json-parse-string response-content :object-type 'plist :null-object nil))))
          (if (and (= response-status-code 200) (plist-get response-json :expires_in))
              (let ((expiry (+ (float-time) (plist-get response-json :expires_in))))
                (setq dank-auth--token-storage (plist-put response-json :expiry expiry))
                response-json)
            (signal 'dank-auth-token-refresh-error
                    `(,full-url ,url-request-method ,response-status-code ,response-content))))))))

(defun dank-auth-token ()
  "Return the access token stored in dank-auth--token-storage.
If the token is no longer valid, then attempt to retrieve a new token."
  (if (dank-auth--token-valid-p)
      (plist-get dank-auth--token-storage :access_token)
    (progn (dank-auth-token-refresh)
           (plist-get dank-auth--token-storage :access_token))))

(defun dank-auth--token-valid-p (&optional attempt-request)
  "Return t if the access token in `dank-auth--token-storage' is still valid.
It checks if the token expiry falls below
`dank-auth--token-expiry-threshold-seconds'.

If `ATTEMPT-REQUEST' is non-nil, then in addition this function will attempt
to do an actual request to Reddit's API using the current access token."
  (when dank-auth--token-storage
    (> (- (plist-get dank-auth--token-storage :expiry) (float-time))
       dank-auth--token-expiry-threshold-seconds)))

(provide 'dank-auth)

;;; dank-auth.el ends here
