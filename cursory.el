;;; cursory.el --- Manage cursor styles using presets -*- lexical-binding: t -*-

;; Copyright (C) 2022-2025  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>
;; Maintainer: Protesilaos Stavrou <info@protesilaos.com>
;; URL: https://github.com/protesilaos/cursory
;; Version: 1.2.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: convenience, cursor

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Cursory lets users define preset configurations for the cursor.
;; Those cover the style of the cursor (e.g. box or bar), whether it
;; is blinking or not, and how fast, as well as the colour it uses.
;; Having distinct presets makes it easy to switch between, say, a
;; "reading mode" with an ambient cursor and a "presentation mode"
;; with a cursor that is more noticeable and thus easier to spot.
;;
;; The user option `cursory-presets' holds the presets.  The command
;; `cursory-set-preset' is applies one among them.  The command supports
;; minibuffer completion when there are multiple presets, else sets the
;; single preset outright.
;;
;; Presets consist of an arbitrary symbol broadly described the style set
;; followed by a list of properties that govern the cursor type in the
;; active and inactive windows, as well as cursor blinking variables.
;; They look like this:
;;
;;     (bar
;;      :cursor-type (bar . 2)
;;      :cursor-in-non-selected-windows hollow
;;      :blink-cursor-mode 1
;;      :blink-cursor-blinks 10
;;      :blink-cursor-interval 0.5
;;      :blink-cursor-delay 0.2)
;;
;; The car of the list is an arbitrary, user-defined symbol that identifies
;; (and can describe) the set.  Each of the properties corresponds to
;; built-in variables: `cursor-type', `cursor-in-non-selected-windows',
;; `blink-cursor-blinks', `blink-cursor-interval', `blink-cursor-delay'.
;; The value each property accepts is the same as the variable it
;; references.
;;
;; A property of `:blink-cursor-mode' is also available.  It is a numeric
;; value of either `1' or `-1' and is given to the function
;; `blink-cursor-mode': `1' is to enable, `-1' is to disable the mode.
;;
;; Presets can inherit from each other.  Using the special `:inherit'
;; property, like this:
;;
;;     (bar
;;      :cursor-type (bar . 2)
;;      :cursor-in-non-selected-windows hollow
;;      :blink-cursor-mode 1
;;      :blink-cursor-blinks 10
;;      :blink-cursor-interval 0.5
;;      :blink-cursor-delay 0.2)
;;
;;     (bar-no-other-window
;;      :inherit bar
;;      :cursor-in-non-selected-windows nil)
;;
;; In the above example, the `bar-no-other-window' is the same as `bar'
;; except for the value of `:cursor-in-non-selected-windows'.
;;
;; The value given to the `:inherit' property corresponds to the name of
;; another named preset (unquoted).  This tells the relevant Cursory
;; functions to get the properties of that given preset and blend them
;; with those of the current one.  The properties of the current preset
;; take precedence over those of the inherited one, thus overriding them.
;;
;; A preset whose car is `t' is treated as the default option.  This
;; makes it possible to specify multiple presets without duplicating
;; their properties.  Presets beside `t' act as overrides of the
;; defaults and, as such, need only consist of the properties that
;; change from the default.  In the case of an `:inherit', properties
;; are first taken from the inherited preset and then the default one.
;; See the original value of this variable for how that is done:
;;
;;     (defcustom cursory-presets
;;       '((box
;;          :blink-cursor-interval 0.8)
;;         (box-no-blink
;;          :blink-cursor-mode -1)
;;         (bar
;;          :cursor-type (bar . 2)
;;          :blink-cursor-interval 0.5)
;;         (bar-no-other-window
;;          :inherit bar
;;          :cursor-in-non-selected-windows nil)
;;         (underscore
;;          :cursor-type (hbar . 3)
;;          :blink-cursor-blinks 50)
;;         (underscore-thin-other-window
;;          :inherit underscore
;;          :cursor-in-non-selected-windows (hbar . 1))
;;         (t ; the default values
;;          :cursor-type box
;;          :cursor-in-non-selected-windows hollow
;;          :blink-cursor-mode 1
;;          :blink-cursor-blinks 10
;;          :blink-cursor-interval 0.2
;;          :blink-cursor-delay 0.2))
;;       ;; Omitting the doc string for demo purposes
;;       )
;;
;; When called from Lisp, the `cursory-set-preset' command requires a
;; PRESET argument, such as:
;;
;;     (cursory-set-preset 'bar)
;;
;; The function `cursory-store-latest-preset' is used to save the last
;; selected style in the `cursory-latest-state-file'.  The value can then
;; be restored with the `cursory-restore-latest-preset' function.

;;; Code:

(eval-when-compile (require 'subr-x))

(defgroup cursory ()
  "Manage cursor styles using presets."
  :group 'cursor
  :link '(info-link "(cursory) Top"))

;; NOTE 2025-07-20: This is what `use-package' does with its own
;; theme, so it is probably the right approach for us too.
(eval-and-compile
  ;; Declare a synthetic theme for :custom variables.
  ;; Necessary in order to avoid having those variables saved by custom.el.
  (deftheme cursory "Special theme for Cursory modifications."))

(enable-theme 'cursory)
;; Remove the synthetic cursory theme from the enabled themes, so
;; iterating over them to "disable all themes" won't disable it.
(setq custom-enabled-themes (remq 'cursory custom-enabled-themes))

(defcustom cursory-presets
  '((box
     :blink-cursor-interval 0.8)
    (box-no-blink
     :blink-cursor-mode -1)
    (bar
     :cursor-type (bar . 2)
     :blink-cursor-interval 0.5)
    (bar-no-other-window
     :inherit bar
     :cursor-in-non-selected-windows nil)
    (underscore
     :cursor-type (hbar . 3)
     :blink-cursor-blinks 50)
    (underscore-thin-other-window
     :inherit underscore
     :cursor-in-non-selected-windows (hbar . 1))
    (t ; the default values
     :cursor-color unspecified
     :cursor-type box
     :cursor-in-non-selected-windows hollow
     :blink-cursor-mode 1
     :blink-cursor-blinks 10
     :blink-cursor-interval 0.2
     :blink-cursor-delay 0.2))
  "Alist of preset configurations for `blink-cursor-mode'.

The car of each cons cell is an arbitrary, user-specified key
that broadly describes the set (e.g. slow-blinking-box or
fast-blinking-bar).

A preset whose car is t is treated as the default option.  This
makes it possible to specify multiple presets without duplicating
their properties.  The other presets beside t act as overrides of
the defaults and, as such, need only consist of the properties
that change from the default.  See the original value of this
variable for how that is done.

The `cdr' is a plist which specifies the cursor type and blink
properties.  In particular, it accepts the following properties:

    :cursor-color
    :cursor-type
    :cursor-in-non-selected-windows
    :blink-cursor-blinks
    :blink-cursor-interval
    :blink-cursor-delay

They correspond to built-in variables: `cursor-type',
`cursor-in-non-selected-windows', `blink-cursor-blinks',
`blink-cursor-interval', `blink-cursor-delay'.  The value each of them
accepts is the same as the variable it references.

A property of `:blink-cursor-mode' is also available.  It is a numeric
value of either 1 or -1 and is given to the function
`blink-cursor-mode' (1 is to enable, -1 is to disable the mode).

The `:cursor-color' specifies the color value applied to the `cursor'
face.  When the value is nil or `unspecified', no changes to the
`cursor' face are made.  When the value is a hexadecimal RGB color
value, like #123456 it is used as-is.  Same if it is a named color among
those produced by the command `list-colors-display'.  When the value is
the symbol of a face (unquoted), then the foreground of that face is
used for the `cursor' face, falling back to `default'.

The plist optionally takes the special `:inherit' property.  Its value
contains the name of another named preset (unquoted).  This tells the
relevant Cursory functions to get the properties of that given preset
and blend them with those of the current one.  The properties of the
current preset take precedence over those of the inherited one, thus
overriding them.  In practice, this is a way to have something like an
underscore style with a hallow cursor for the other window and the same
with a thin underscore for the other window (see the default value of
this user option for concrete examples).  Remember that all named
presets fall back to the preset whose name is t.  The `:inherit' is not
a substitute for that generic fallback but rather an extra method of
specifying font configuration presets."
  :group 'cursory
  :package-version '(cursory . "1.2.0")
  :type `(alist
          :value-type
          (plist :options
                 (((const :tag "Cursor color" :cursor-color)
                   (choice (const :tag "Do not modify the `cursor' face" unspecified)
                           (string :tag "Hexademical RGB color value (e.g. #123456) or named color (e.g. red)")
                           (face :tag "A face whose foreground is used (falling back to `default'")))
                  ((const :tag "Cursor type"
                          :cursor-type)
                   ,(get 'cursor-type 'custom-type))
                  ((const :tag "Cursor in non-selected windows"
                          :cursor-in-non-selected-windows)
                   ,(get 'cursor-in-non-selected-windows 'custom-type))
                  ((const :tag "Number of blinks"
                          :blink-cursor-blinks)
                   ,(get 'blink-cursor-blinks 'custom-type))
                  ((const :tag "Blink interval"
                          :blink-cursor-interval)
                   ,(get 'blink-cursor-interval 'custom-type))
                  ((const :tag "Blink delay"
                          :blink-cursor-delay)
                   ,(get 'blink-cursor-delay 'custom-type))
                  ((const :tag "Blink Cursor Mode"
                          :blink-cursor-mode)
                   (choice :value 1
                           (const :tag "Enable" 1)
                           (const :tag "Disable" -1)))
                  ((const :tag "Inherit another preset" :inherit) symbol)))
          :key-type symbol))

(defcustom cursory-latest-state-file
  (locate-user-emacs-file "cursory-latest-state.eld")
  "File to save the value of `cursory-set-preset'.
Saving is done by the `cursory-store-latest-preset' function."
  :type 'file
  :package-version '(cursory . "0.1.0")
  :group 'cursory)

(defcustom cursory-set-preset-hook nil
  "Normal hook that runs after `cursory-set-preset'."
  :type 'hook
  :package-version '(cursory . "1.1.0")
  :group 'cursory)

(defconst cursory-fallback-preset
  '(cursory-defaults
    :cursor-color unspecified ; use the theme's original
    :cursor-type box
    :cursor-in-non-selected-windows hollow
    :blink-cursor-mode 1
    :blink-cursor-blinks 10
    :blink-cursor-interval 0.2
    :blink-cursor-delay 0.2)
  "Fallback preset configuration like `cursory-presets'.")

(defun cursory-get-presets ()
  "Return consolidated `cursory-presets' and `cursory-fallback-preset'."
  (append (list cursory-fallback-preset) cursory-presets))

(defun cursory--get-preset-symbols ()
  "Return the `car' of each named entry in `cursory-presets'."
  (delq t (mapcar #'car (cursory-get-presets))))

(defun cursory--preset-p (preset)
  "Return non-nil if PRESET is one of the named `cursory-presets'."
  (if-let* ((presets (cursory--get-preset-symbols)))
      (memq preset presets)
    (error "There are no named presets in `cursory-presets'")))

;; NOTE 2025-07-21: In principle, this should work recursively but it
;; feels overkill for such a minor feature.
(defun cursory--get-inherit-name (preset)
  "Get the `:inherit' value of PRESET."
  (when-let* ((presets (cursory-get-presets))
              (inherit (plist-get (alist-get preset presets) :inherit))
              (cursory--preset-p inherit))
    inherit))

(defun cursory--get-preset-properties (preset)
  "Return list of properties for PRESET in `cursory-presets'."
  (let ((presets (cursory-get-presets)))
    (append (alist-get preset presets)
            (when-let* ((inherit (cursory--get-inherit-name preset)))
              (alist-get inherit presets))
            (alist-get t presets))))

(defun cursory--get-preset-symbols-as-strings ()
  "Convert `fontaine--get-preset-symbols' return value to list of string."
  (mapcar #'symbol-name (cursory--get-preset-symbols)))

(defvar cursory-last-selected-preset nil
  "The last value of `cursory-set-preset'.")

(defun cursory--get-first-non-current-preset (history)
  "Return the first element of HISTORY which is not `cursory-last-selected-preset'.
Only consider elements that are still part of the `cursory-presets'."
  (catch 'first
    (dolist (element history)
      (when (symbolp element)
        (setq element (symbol-name element)))
      (when (and (not (string= element cursory-last-selected-preset))
                 (member element (cursory--get-preset-symbols-as-strings)))
        (throw 'first element)))))

(define-obsolete-variable-alias
  'cursory--style-hist
  'cursory-preset-history
  "1.2.0")

(defvar cursory-preset-history nil
  "Minibuffer history of `cursory-set-preset-prompt'.")

(define-obsolete-function-alias
  'cursory--set-cursor-prompt
  'cursory-set-preset-prompt
  "1.2.0")

(defun cursory-set-preset-prompt ()
  "Promp for `cursory-presets' (used by `cursory-set-preset')."
  (let ((default (cursory--get-first-non-current-preset cursory-preset-history)))
    (completing-read
     (format-prompt "Apply cursor configurations from PRESET" default)
     (cursory--get-preset-symbols)
     nil t nil 'cursory-preset-history default)))

(defun cursory--get-preset-as-symbol (preset)
  "Return PRESET as a symbol."
  (if (stringp preset)
      (intern preset)
    preset))

(defun cursory--get-cursor-color (color-value)
  "Return the color of the `cursor' face based on VALUE.
COLOR-VALUE can be a string, representing a color by name or hexadecimal
RGB, a symbol of a face, the symbol `unspecified' or nil."
  (cond
    ((stringp color-value) color-value)
    ((facep color-value) (face-foreground color-value nil 'default))
    (t nil)))

(defun cursory--set-cursor (color-value)
  "Set the cursor style given COLOR-VALUE.
When FRAME is a frame object, only do it for it.  Otherwise, apply the
effect to all frames."
  (let ((color (cursory--get-cursor-color color-value))
        (custom--inhibit-theme-enable nil))
    (if color
        (custom-theme-set-faces 'cursory `(cursor ((t :background ,color))))
      (custom-theme-set-faces 'cursory '(cursor (( )))))))

(defun cursory--set-preset-subr (preset)
  "Set PRESET of `cursory-presets' to the global scope."
  (if-let* ((styles (cursory--get-preset-properties preset)))
      ;; We do not include this in the `if-let*' because we also accept
      ;; nil values for :cursor-type, :cursor-in-non-selected-windows.
      (let ((color-value (plist-get styles :cursor-color))
            (type (plist-get styles :cursor-type))
            (type-no-select (plist-get styles :cursor-in-non-selected-windows))
            (blinks (plist-get styles :blink-cursor-blinks))
            (interval (plist-get styles :blink-cursor-interval))
            (delay (plist-get styles :blink-cursor-delay)))
        (setq cursory-last-selected-preset preset)
        ;; Wipe out any locally applied preset in this buffer.
        (cursory--kill-local-preset)
        (cursory--set-cursor color-value)
        (setq-default cursor-type type
                      cursor-in-non-selected-windows type-no-select
                      blink-cursor-blinks blinks
                      blink-cursor-interval interval
                      blink-cursor-delay delay)
        ;; We only want to save global values in `cursory-store-latest-preset'.
        (add-to-history 'cursory-preset-history (format "%s" preset))
        (blink-cursor-mode (plist-get styles :blink-cursor-mode))
        (run-hooks 'cursory-set-preset-hook))
    (user-error "Cannot determine styles of preset `%s'" preset)))

(defun cursory--set-local-preset-subr (preset)
  "Set PRESET of `cursory-presets' to the local scope."
  (if-let* ((styles (cursory--get-preset-properties preset)))
      ;; We do not include this in the `if-let*' because we also accept
      ;; nil values for :cursor-type, :cursor-in-non-selected-windows.
      (let ((color-value (plist-get styles :cursor-color))
            (type (plist-get styles :cursor-type))
            (type-no-select (plist-get styles :cursor-in-non-selected-windows))
            (blinks (plist-get styles :blink-cursor-blinks))
            (interval (plist-get styles :blink-cursor-interval))
            (delay (plist-get styles :blink-cursor-delay)))
        (cursory--set-cursor color-value)
        (setq-local cursor-type type
                    cursor-in-non-selected-windows type-no-select
                    blink-cursor-blinks blinks
                    blink-cursor-interval interval
                    blink-cursor-delay delay)
        (blink-cursor-mode (plist-get styles :blink-cursor-mode))
        (run-hooks 'cursory-set-preset-hook))
    (user-error "Cannot determine styles of preset `%s'" preset)))

(defun cursory--kill-local-preset ()
  "Clear any local preset if one exists."
  ;; Kill the local variables, ignoring any errors if they were unset
  (ignore-errors
    (mapcar 'kill-local-variable '(cursor-type
                                   cursor-in-non-selected-windows
                                   blink-cursor-blinks
                                   blink-cursor-interval
                                   blink-cursor-delay))))

;;;###autoload
(defun cursory-set-preset (style)
  "Set cursor preset associated with STYLE.

STYLE is a symbol that represents the car of a list in
`cursory-presets'.

Call `cursory-set-preset-hook' as a final step."
  (interactive (list (cursory-set-preset-prompt)))
  (if-let* ((preset (cursory--get-preset-as-symbol style)))
      (cursory--set-preset-subr preset)
    (user-error "Cannot determine preset `%s'" preset)))

;;;###autoload
(defun cursory-set-local-preset (style)
  "Set local cursor preset associated with STYLE.

STYLE is a symbol that represents the car of a list in
`cursory-presets'.

Call `cursory-set-preset-hook' as a final step.

This does not update `cursory-last-selected-preset' or
`cursory-store-latest-preset'.

CAUTION: setting cursor color or enabling/disabling blink mode using
this function sets those attributes GLOBALLY."
  (interactive (list (cursory-set-preset-prompt)))
  (if-let* ((preset (cursory--get-preset-as-symbol style)))
      (cursory--set-local-preset-subr preset)
    (user-error "Cannot determine preset `%s'" preset)))

;;;###autoload
(defun cursory-set-last-or-fallback ()
  "Set the `cursory-last-selected-preset' or fall back to whatever known values.
This function is useful when starting up Emacs, such as in the
`after-init-hook'."
  (cursory-set-preset
   (cond
    ((when-let* ((last-preset (cursory-restore-latest-preset))
                 (_ (cursory--preset-p last-preset)))
       last-preset))
    ((cursory--preset-p 'box)
     'box)
    (t
     'cursory-defaults))))

;;;###autoload
(defun cursory-store-latest-preset ()
  "Write latest cursor state to `cursory-latest-state-file'.
Can be assigned to `kill-emacs-hook'."
  (when-let* ((hist cursory-preset-history))
    (with-temp-file cursory-latest-state-file
      (insert ";; Auto-generated file; don't edit -*- mode: "
              (if (<= 28 emacs-major-version)
                  "lisp-data"
                "emacs-lisp")
              " -*-\n")
      (pp (intern (car hist)) (current-buffer)))))

(defvar cursory-recovered-preset nil
  "Recovered value of latest store cursor preset.")

;;;###autoload
(defun cursory-restore-latest-preset ()
  "Restore latest cursor style."
  (when-let* ((file cursory-latest-state-file)
              ((file-exists-p file)))
    (setq cursory-recovered-preset
          (unless (zerop
                   (or (file-attribute-size (file-attributes file))
                       0))
            (with-temp-buffer
              (insert-file-contents file)
              (read (current-buffer)))))))

(defun cursory-set-faces (&rest _)
  "Set Cursory faces.
Add this to the `enable-theme-functions'."
  (when-let* ((last cursory-last-selected-preset)
              (styles (cursory--get-preset-properties last))
              (color-value (plist-get styles :cursor-color)))
    (cursory--set-cursor color-value)))

;;;###autoload
(define-minor-mode cursory-mode
  "Persist Cursory presets and other styles."
  :global t
  (if cursory-mode
      (progn
        (add-hook 'kill-emacs-hook #'cursory-store-latest-preset)
        (add-hook 'cursory-set-preset-hook #'cursory-store-latest-preset)
        (add-hook 'enable-theme-functions #'cursory-set-faces))
    (remove-hook 'kill-emacs-hook #'cursory-store-latest-preset)
    (remove-hook 'cursory-set-preset-hook #'cursory-store-latest-preset)
    (remove-hook 'enable-theme-functions #'cursory-set-faces)))

(provide 'cursory)
;;; cursory.el ends here
