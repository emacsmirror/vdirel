;;; vdirel.el --- Manipulate vdir (i.e., vCard) repositories

;; Copyright (C) 2015 Damien Cassou

;; Author: Damien Cassou <damien@cassou.me>
;; Version: 0.1.0
;; GIT: https://github.com/DamienCassou/vdirel
;; Package-Requires: ((emacs "24.4") (org-vcard "0.1.0") (helm "1.7.0") (seq "1.11"))
;; Created: 09 Dec 2015
;; Keywords: vdirsyncer vdir vCard carddav contact addressbook helm

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Manipulate vdir (i.e., vCard) repositories from Emacs

;;; Code:
(require 'org-vcard)
(require 'seq)
(require 'helm)

(defgroup vdirel nil
  "Manipulate vdir (i.e., vCard) repositories from Emacs"
  :group 'applications)

(defcustom vdirel-repository "~/contacts"
  "Path to the vdir folder.")

(defvar vdirel--cache-contacts '()
  "Cache where contacts are stored to avoid repeated parsing.
This is an alist mapping a vdir folder to a contact list.")

;; (
;;  ("VDIREL-FILENAME" . "/home/cassou/Documents/configuration/contacts/5007154e-e4e4-491e-ab4e-2bfc6970444c.vcf")
;;  ("VERSION" . "3.0")
;;  ("PRODID" . "-//ASynK v2.1.0-rc2+//EN")
;;  ("UID" . "5007154e-e4e4-491e-ab4e-2bfc6970444c")
;;  ("EMAIL;TYPE=home" . "email1@foo.com")
;;  ("EMAIL;TYPE=home" . "email2@foo.com")
;;  ("EMAIL" . "email3@foo.com")
;;  ("EMAIL" . "email4@foo.com")
;;  ("EMAIL" . "email5@foo.com")
;;  ("FN" . "First Last")
;;  ("N" . "First;Last;;;")
;;  ("REV" . "20150612T164658Z")
;;  ("TEL;TYPE=voice" . "+33242934873")
;;  ("TEL;TYPE=voice" . "+33399898111"))

(defun vdirel--contact-property (property contact)
  "Return value of first property named PROPERTY in CONTACT.
Return nil if PROPERTY is not in CONTACT."
  (assoc-default property contact #'string= nil))

(defun vdirel--contact-properties (property contact)
  "Return values of all properties named PROPERTY in CONTACT."
  (vdirel--contact-matching-properties (lambda (name) (string= name property)) contact))

(defun vdirel--contact-matching-properties (pred contact)
  "Return values of all properties whose name match PRED in CONTACT."
  (seq-map #'cdr (seq-filter (lambda (pair)
                               (funcall pred (car pair)))
                             contact)))

(defun vdirel-contact-fullname (contact)
  "Return the fullname of CONTACT."
  (or
   (vdirel--contact-property "FN" contact)
   (replace-regexp-in-string
    ";" " "
    (vdirel--contact-property "N" contact))))

(defun vdirel-contact-emails (contact)
  "Return a list of CONTACT's email addresses."
  (vdirel--contact-matching-properties
   (lambda (property) (string-match "^EMAIL" property))
   contact))


(defun vdirel--repository ()
  "Return the path to the vdir folder.
This is an expantion of the variable `vdirel-repository'."
  (expand-file-name vdirel-repository))

(defun vdirel--cache-contacts (&optional repository)
  "Return the contacts in cache for REPOSITORY."
  (let ((repository (or repository (vdirel--repository))))
    (assoc-default repository vdirel--cache-contacts #'string=)))

(defun vdirel--contact-files (&optional repository)
  "Return a list of vCard files in REPOSITORY.
If REPOSITORY is absent or nil, use the function `vdirel--repository'."
  (let ((repository (or repository (vdirel--repository))))
    (directory-files repository t "\.vcf$" t)))

(defun vdirel--parse-file-to-contact (filename)
  "Return a list representing the vCard in inside FILENAME.
Each element in the list is a cons cell containing the vCard property name
in the `car', and the value of that property in the `cdr'.  Parsing is done
through `org-vcard-import-parse'."
  (with-temp-buffer
    (insert-file-contents filename)
    (cons
     (cons "VDIREL-FILENAME" filename)
     (car (org-vcard-import-parse "buffer")))))

(defun vdirel--build-contacts (&optional repository)
  "Return a list of contacts in REPOSITORY.
If REPOSITORY is absent or nil, use the function `vdirel--repository'."
  (mapcar #'vdirel--parse-file-to-contact (vdirel--contact-files)))

(defun vdirel-refresh-cache (&optional repository)
  "Parse all contacts in REPOSITORY and store the result."
  (let ((repository (or repository (vdirel--repository))))
    (add-to-list 'vdirel--cache-contacts (cons repository (vdirel--build-contacts)))))

(defun vdirel--helm-email-candidates (contacts)
  "Return a list of contact emails for every contact in CONTACTS."
  (seq-mapcat (lambda (contact)
                (mapcar (lambda (email)
                          (cons (format "%s <%s>"
                                        (vdirel-contact-fullname contact)
                                        email)
                                (list (vdirel-contact-fullname contact)
                                      email)))
                        (vdirel-contact-emails contact)))
              contacts))

(defun vdirel--helm-insert-contact-email (candidate)
  "Print selected contacts as comma-separated text.
CANDIDATE is ignored."
  (ignore candidate)
  (insert (mapconcat (lambda (pair)
                       (format "\"%s\" <%s>"
                               (car pair)
                               (cadr pair)))
                     (helm-marked-candidates)
                     ", ")))

;;;###autoload
(defun vdirel-helm-select-email (&optional refresh repository)
  "Let user choose an email address from (REFRESH'ed) REPOSITORY."
  (interactive
   (list (cond ((equal '(16) current-prefix-arg) 'server)
               ((consp current-prefix-arg) 'cache))
         (vdirel--repository)))
  (when (eq refresh 'server)
    (vdirel-vdirsyncer-sync-server repository))
  (when (or refresh (null (vdirel--cache-contacts repository)))
    (vdirel-refresh-cache repository))
  (helm
   :prompt "Contacts: "
   :sources
   (helm-build-sync-source "Contacts"
     :candidates (vdirel--helm-email-candidates (vdirel--cache-contacts repository))
     :action (helm-make-actions
              "Insert" #'vdirel--helm-insert-contact-email))))

(provide 'vdirel)

;;; vdirel.el ends here

;;  LocalWords:  vCard
