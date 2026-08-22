; ============================================================================
;  TargetManager.au3
;
;  Keeps MindAR trigger images in a stable, predictable order and keeps
;  index.html in sync — for the householderc-testAR project.
;
;  This version does NOT drive the browser at all. Earlier versions tried
;  to automate clicking through the compile tool, and that turned out to
;  be genuinely fragile (calibrated screen coordinates going stale as the
;  page layout shifted, native dialogs needing careful handling, no clean
;  way to detect "compile finished"). None of that was actually the hard
;  part of this problem. The hard part was just: how do you guarantee the
;  SAME order every time you drag files into the compile tool, including
;  after adding new ones later? This script solves exactly that, and
;  nothing else — you still do the drag-and-drop and clicking yourself.
;
;  HOW ORDER IS GUARANTEED:
;  Every file in /targets gets a zero-padded numeric prefix - "01_",
;  "02_", etc. Windows' native multi-select file dialog (and Explorer in
;  general) sorts alphabetically, and a zero-padded numeric prefix sorts
;  exactly the way you'd expect (01, 02, ... 10, 11, not 1, 10, 11, 2).
;  So selecting ALL files in /targets and dragging them into the compile
;  tool always uploads them in prefix order - which is also the exact
;  order this script uses to assign targetIndex values in index.html.
;
;  New trigger images just get the next available number appended.
;  Existing prefixed files are NEVER renumbered, so old targetIndex
;  assignments (and their hand-tuned scale/position) never shift around
;  just because you added one more image.
;
;  WORKFLOW EACH RUN:
;   1. Scans /targets. Any file that doesn't already have a "NN_" prefix
;      is treated as new and gets renamed with the next available number.
;   2. For any trigger image not yet in target-settings.ini (matched by
;      filename with the prefix stripped off, so renaming doesn't lose
;      its settings), opens a small GUI: shows a thumbnail, lets you pick
;      an overlay from /overlays, and set position/rotation/scale.
;   3. Backs up the current targets.mind and index.html into /backups.
;   4. Rewrites index.html between the AUTOGEN markers to match the
;      current on-disk file order. Everything else in the file (styles,
;      the start button script, etc.) is left completely alone.
;   5. Opens the compile tool in your browser and opens the /targets
;      folder in Explorer, so you can immediately select-all and drag
;      them in. From there, compiling and downloading targets.mind is
;      exactly the same manual process you were already doing.
;
;  FIRST RUN NOTE: your 6 existing images have no prefix yet, so the
;  first run will rename all of them (in their current alphabetical
;  order) and, if target-settings.ini doesn't already have entries for
;  them, ask you to configure each one once.
;
;  SETUP REQUIRED BEFORE RUNNING:
;   - Install AutoIt3 (https://www.autoitscript.com/) if you haven't.
;   - Check the CONFIG section below and adjust paths if this script ever
;     moves to a different machine/folder.
;   - No extra AutoIt libraries needed - just a standard install.
; ============================================================================

#include <Array.au3>
#include <File.au3>
#include <Math.au3>
#include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#include <ComboConstants.au3>
#include <GuiListBox.au3>

; ---------------------------------------------------------------------------
; CONFIG - adjust these if the project ever moves
; ---------------------------------------------------------------------------
Global Const $PROJECT_ROOT   = "C:\Users\house\OneDrive\Documents\GitHub\householderc-testAR"
Global Const $TARGETS_DIR    = $PROJECT_ROOT & "\targets"
Global Const $OVERLAYS_DIR   = $PROJECT_ROOT & "\overlays"
Global Const $INDEX_HTML     = $PROJECT_ROOT & "\index.html"
Global Const $TARGETS_MIND   = $PROJECT_ROOT & "\targets.mind"
Global Const $SETTINGS_INI   = $PROJECT_ROOT & "\target-settings.ini"
Global Const $BACKUP_DIR     = $PROJECT_ROOT & "\backups"
Global Const $THUMB_TMP      = @TempDir & "\mindar_thumb.png"
Global Const $COMPILE_URL    = "https://hiukim.github.io/mind-ar-js-doc/tools/compile/"

Global Const $ASSET_EXTENSIONS = "png|jpg|jpeg"
Global Const $PREFIX_DIGITS = 2 ; "01_", "02_", ... up to 99 targets

Opt("MustDeclareVars", 0)

; ---------------------------------------------------------------------------
; MAIN
; ---------------------------------------------------------------------------
_Main()

Func _Main()
	If Not FileExists($TARGETS_DIR) Then
		MsgBox(16, "TargetManager", "Can't find targets folder:" & @CRLF & $TARGETS_DIR)
		Exit
	EndIf
	If Not FileExists($OVERLAYS_DIR) Then
		MsgBox(16, "TargetManager", "Can't find overlays folder:" & @CRLF & $OVERLAYS_DIR)
		Exit
	EndIf
	If Not FileExists($BACKUP_DIR) Then DirCreate($BACKUP_DIR)

	; --- Step 1: assign order-prefixes to any new (unprefixed) images -----
	_AssignPrefixesToNewFiles()

	Local $aTargets = _GetSortedFiles($TARGETS_DIR)
	If UBound($aTargets) = 0 Then
		MsgBox(16, "TargetManager", "No images found in:" & @CRLF & $TARGETS_DIR)
		Exit
	EndIf

	Local $aOverlays = _GetSortedFiles($OVERLAYS_DIR)
	If UBound($aOverlays) = 0 Then
		MsgBox(16, "TargetManager", "No images found in:" & @CRLF & $OVERLAYS_DIR)
		Exit
	EndIf

	; --- Step 2: review, configure, or edit any target's settings ---------
	; Handles brand-new (unconfigured) targets AND lets you reopen the
	; config GUI for any already-configured one - this is the "edit
	; without hand-editing index.html" entry point.
	_ManageTargetsLoop($aTargets, $aOverlays)

	Local $iConfirm = MsgBox(35, "TargetManager", "This order is now locked in for " & UBound($aTargets) & _
		" target(s):" & @CRLF & @CRLF & _ArrayToString($aTargets, @CRLF) & @CRLF & @CRLF & _
		"index.html will be rewritten to match (a backup is made first). Continue?")
	If $iConfirm <> 6 Then ; 6 = Yes
		Exit
	EndIf

	; --- Step 3: back up current targets.mind and index.html --------------
	If FileExists($TARGETS_MIND) Then
		Local $sBackupName = "targets_" & @YEAR & @MON & @MDAY & "_" & @HOUR & @MIN & @SEC & ".mind"
		FileCopy($TARGETS_MIND, $BACKUP_DIR & "\" & $sBackupName, 1)
	EndIf

	; --- Step 4: regenerate index.html -------------------------------------
	_RegenerateIndexHtml($aTargets)

	; --- Step 5: hand off to you for the manual compile step ---------------
	Run(@ComSpec & ' /c start "" "' & $COMPILE_URL & '"', "", @SW_HIDE)
	Run("explorer.exe """ & $TARGETS_DIR & """")

	MsgBox(64, "TargetManager", "index.html is updated and matches this order:" & @CRLF & @CRLF & _
		_ArrayToString($aTargets, @CRLF) & @CRLF & @CRLF & _
		"I opened the compile tool and the targets folder for you. In the targets folder," & @CRLF & _
		"press Ctrl+A to select all files, then drag them into the compile tool - they'll" & @CRLF & _
		"land in exactly this order because of the number prefixes. Click Start, wait for it" & @CRLF & _
		"to finish, click Download compiled, and save over:" & @CRLF & $TARGETS_MIND)
EndFunc

; ---------------------------------------------------------------------------
; Order-prefix helpers
; ---------------------------------------------------------------------------

; A prefix is exactly N digits followed by an underscore at the very start
; of the filename, e.g. "01_frontdoor.png" -> prefix "01".
Func _HasPrefix($sFilename)
	Return StringRegExp($sFilename, "^\d{" & $PREFIX_DIGITS & "}_")
EndFunc

Func _GetPrefixNumber($sFilename)
	Local $a = StringRegExp($sFilename, "^(\d{" & $PREFIX_DIGITS & "})_", 1)
	If @error Then Return -1
	Return Number($a[0])
EndFunc

; Strips a "NN_" prefix if present; otherwise returns the filename
; unchanged. This is the key used to look up target-settings.ini, so
; settings survive a file being renamed to add/keep its order prefix.
Func _StripPrefix($sFilename)
	If _HasPrefix($sFilename) Then
		Return StringRegExpReplace($sFilename, "^\d{" & $PREFIX_DIGITS & "}_", "")
	EndIf
	Return $sFilename
EndFunc

Func _ZeroPad($iNum)
	Return StringFormat("%0" & $PREFIX_DIGITS & "i", $iNum)
EndFunc

; Renames any file in /targets that doesn't already have an order-prefix,
; assigning the next available number after whatever's already in use.
; Existing prefixed files are never touched, so their targetIndex (and
; any hand-tuned scale/position tied to it) never shifts.
Func _AssignPrefixesToNewFiles()
	Local $aAll = _GetSortedFiles($TARGETS_DIR)
	If UBound($aAll) = 0 Then Return

	Local $iHighest = 0
	Local $aUnprefixed[0]
	For $i = 0 To UBound($aAll) - 1
		If _HasPrefix($aAll[$i]) Then
			Local $iNum = _GetPrefixNumber($aAll[$i])
			If $iNum > $iHighest Then $iHighest = $iNum
		Else
			_ArrayAdd($aUnprefixed, $aAll[$i])
		EndIf
	Next

	If UBound($aUnprefixed) = 0 Then Return ; nothing new to number

	_ArraySort($aUnprefixed) ; deterministic order among the new ones

	Local $sSummary = ""
	Local $iNext = $iHighest + 1
	For $i = 0 To UBound($aUnprefixed) - 1
		Local $sOld = $aUnprefixed[$i]
		Local $sNew = _ZeroPad($iNext) & "_" & $sOld
		Local $bOk = FileMove($TARGETS_DIR & "\" & $sOld, $TARGETS_DIR & "\" & $sNew)
		If Not $bOk Then
			MsgBox(16, "TargetManager", "Couldn't rename:" & @CRLF & $sOld & " -> " & $sNew & @CRLF & @CRLF & _
				"Make sure the file isn't open elsewhere, then run the script again.")
			Exit
		EndIf
		$sSummary &= $sOld & "  ->  " & $sNew & @CRLF
		$iNext += 1
	Next

	MsgBox(64, "TargetManager", "Assigned order to " & UBound($aUnprefixed) & " new image(s):" & @CRLF & @CRLF & $sSummary)
EndFunc

; ---------------------------------------------------------------------------
; File listing helpers
; ---------------------------------------------------------------------------
Func _GetSortedFiles($sDir)
	Local $aList = _FileListToArray($sDir, "*.*", $FLTA_FILES)
	If @error Then
		Local $aEmpty[0]
		Return $aEmpty
	EndIf

	Local $aFiltered[0]
	For $i = 1 To $aList[0]
		Local $sExt = StringLower(StringRegExpReplace($aList[$i], "^.*\.", ""))
		If StringInStr("|" & $ASSET_EXTENSIONS & "|", "|" & $sExt & "|") Then
			_ArrayAdd($aFiltered, $aList[$i])
		EndIf
	Next
	If UBound($aFiltered) > 0 Then _ArraySort($aFiltered)
	Return $aFiltered
EndFunc

; ---------------------------------------------------------------------------
; target-settings.ini helpers (keyed by BASE filename, prefix stripped -
; so renaming a file to add/keep its order prefix never loses its settings)
; ---------------------------------------------------------------------------
Func _HasSettings($sBaseFile)
	Local $s = IniRead($SETTINGS_INI, $sBaseFile, "Overlay", "")
	Return $s <> ""
EndFunc

Func _SaveSettings($sBaseFile, $sOverlay, $sPos, $sRot, $sScale, $sWidth, $sHeight)
	IniWrite($SETTINGS_INI, $sBaseFile, "Overlay", $sOverlay)
	IniWrite($SETTINGS_INI, $sBaseFile, "Position", $sPos)
	IniWrite($SETTINGS_INI, $sBaseFile, "Rotation", $sRot)
	IniWrite($SETTINGS_INI, $sBaseFile, "Scale", $sScale)
	IniWrite($SETTINGS_INI, $sBaseFile, "Width", $sWidth)
	IniWrite($SETTINGS_INI, $sBaseFile, "Height", $sHeight)
EndFunc

; ---------------------------------------------------------------------------
; Per-image config GUI (overlay picker + position/rotation/scale fields)
; $sCurrentFile is the actual on-disk name (with prefix) - used to load the
; thumbnail. Settings are saved under the prefix-stripped base name.
; ---------------------------------------------------------------------------
; Shows the config GUI for one target, pre-filled with its existing
; settings if it already has any (editing), or sensible defaults if not
; (first-time configuring). Returns True if the user saved, False if they
; closed the window without saving - the caller decides what that means
; rather than this function exiting the whole script.
Func _ShowConfigGUI($sCurrentFile, $aOverlays)
	Local $sBaseFile = _StripPrefix($sCurrentFile)
	Local $sImgPath = $TARGETS_DIR & "\" & $sCurrentFile
	Local $aDim = _CreateThumbnail($sImgPath, $THUMB_TMP, 260)

	Local $sExistingOverlay = IniRead($SETTINGS_INI, $sBaseFile, "Overlay", "")
	Local $sExistingPos = IniRead($SETTINGS_INI, $sBaseFile, "Position", "0 0 0")
	Local $sExistingRot = IniRead($SETTINGS_INI, $sBaseFile, "Rotation", "0 0 0")
	Local $sExistingScale = IniRead($SETTINGS_INI, $sBaseFile, "Scale", "0.5 0.5 0.5")
	Local $sExistingWidth = IniRead($SETTINGS_INI, $sBaseFile, "Width", "1")
	Local $sExistingHeight = IniRead($SETTINGS_INI, $sBaseFile, "Height", "1")
	Local $bIsEdit = ($sExistingOverlay <> "")

	Local $sTitle = $bIsEdit ? ("Edit: " & $sBaseFile) : ("Configure: " & $sBaseFile)
	Local $hGui = GUICreate($sTitle, 420, 560)

	GUICtrlCreateLabel("Trigger image: " & $sBaseFile & "  (" & $sCurrentFile & ")", 15, 10, 390, 20)
	GUICtrlCreatePic($THUMB_TMP, 15, 35, $aDim[0], $aDim[1])

	Local $iPicBottom = 35 + $aDim[1] + 15

	GUICtrlCreateLabel("Overlay to show:", 15, $iPicBottom, 150, 20)
	Local $idOverlayCombo = GUICtrlCreateCombo("", 15, $iPicBottom + 20, 390, 25, $CBS_DROPDOWNLIST)
	Local $sOverlayList = _ArrayToString($aOverlays, "|")
	Local $sDefaultOverlay = $sExistingOverlay
	If $sDefaultOverlay = "" And UBound($aOverlays) > 0 Then $sDefaultOverlay = $aOverlays[0]
	GUICtrlSetData($idOverlayCombo, $sOverlayList, $sDefaultOverlay)

	Local $iRow = $iPicBottom + 55

	GUICtrlCreateLabel("Position (x y z):", 15, $iRow, 150, 20)
	Local $idPos = GUICtrlCreateInput($sExistingPos, 170, $iRow - 3, 235, 22)
	$iRow += 30

	GUICtrlCreateLabel("Rotation (x y z):", 15, $iRow, 150, 20)
	Local $idRot = GUICtrlCreateInput($sExistingRot, 170, $iRow - 3, 235, 22)
	$iRow += 30

	GUICtrlCreateLabel("Scale (x y z):", 15, $iRow, 150, 20)
	Local $idScale = GUICtrlCreateInput($sExistingScale, 170, $iRow - 3, 235, 22)
	$iRow += 30

	GUICtrlCreateLabel("Width:", 15, $iRow, 150, 20)
	Local $idWidth = GUICtrlCreateInput($sExistingWidth, 170, $iRow - 3, 100, 22)
	$iRow += 30

	GUICtrlCreateLabel("Height (auto from overlay aspect):", 15, $iRow, 220, 20)
	Local $idHeight = GUICtrlCreateInput($sExistingHeight, 170, $iRow - 3, 100, 22)
	$iRow += 40

	; If this is a brand-new target (no existing height yet), seed it from
	; the default overlay's aspect ratio. If editing, leave whatever's
	; already saved alone until they actually change the overlay.
	If Not $bIsEdit And UBound($aOverlays) > 0 Then
		Local $fH = _OverlayAspectHeight($OVERLAYS_DIR & "\" & $sDefaultOverlay)
		GUICtrlSetData($idHeight, $fH)
	EndIf

	Local $sSaveLabel = $bIsEdit ? "Save Changes" : "Next / Save"
	Local $idSave = GUICtrlCreateButton($sSaveLabel, 140, $iRow, 140, 32)

	GUISetState(@SW_SHOW, $hGui)

	Local $sLastOverlay = $sDefaultOverlay
	Local $bSaved = False

	While 1
		Local $sCur = GUICtrlRead($idOverlayCombo)
		If $sCur <> $sLastOverlay And $sCur <> "" Then
			$sLastOverlay = $sCur
			Local $fH = _OverlayAspectHeight($OVERLAYS_DIR & "\" & $sCur)
			GUICtrlSetData($idHeight, $fH)
		EndIf

		Local $msg = GUIGetMsg()
		Select
			Case $msg = $GUI_EVENT_CLOSE
				$bSaved = False
				ExitLoop
			Case $msg = $idSave
				Local $sOverlay = GUICtrlRead($idOverlayCombo)
				If $sOverlay = "" Then
					MsgBox(48, "TargetManager", "Pick an overlay first.")
					ContinueLoop
				EndIf
				_SaveSettings($sBaseFile, $sOverlay, GUICtrlRead($idPos), GUICtrlRead($idRot), _
					GUICtrlRead($idScale), GUICtrlRead($idWidth), GUICtrlRead($idHeight))
				$bSaved = True
				ExitLoop
		EndSelect
		Sleep(30)
	WEnd

	GUIDelete($hGui)
	Return $bSaved
EndFunc

; ---------------------------------------------------------------------------
; Target management list - shows every current target and its overlay,
; lets you pick any one to edit (reopens _ShowConfigGUI pre-filled with its
; current values), and won't let you Continue until every target has been
; configured at least once. This is the whole answer to "how do I change
; index.html without hand-editing it" - edit here, then Continue rewrites
; index.html for you.
; ---------------------------------------------------------------------------
Func _ManageTargetsLoop($aTargets, $aOverlays)
	Local $hGui = GUICreate("Manage Targets", 480, 420)

	GUICtrlCreateLabel("Select a target and click Edit to change its overlay/position/scale." & @CRLF & _
		"Everything must be configured at least once before you can Continue.", 15, 10, 450, 35)

	Local $idList = GUICtrlCreateList("", 15, 55, 450, 290)
	_RefreshTargetList($idList, $aTargets)

	Local $idEdit = GUICtrlCreateButton("Edit Selected", 15, 355, 140, 32)
	Local $idContinue = GUICtrlCreateButton("Continue", 340, 355, 125, 32)

	GUISetState(@SW_SHOW, $hGui)

	While 1
		Local $msg = GUIGetMsg()
		Select
			Case $msg = $GUI_EVENT_CLOSE
				MsgBox(16, "TargetManager", "Cancelled - no changes were made to index.html.")
				Exit
			Case $msg = $idEdit
				Local $sSelected = GUICtrlRead($idList)
				If $sSelected = "" Then
					MsgBox(48, "TargetManager", "Select a target from the list first.")
					ContinueLoop
				EndIf
				Local $sCurrentFile = _ExtractFilenameFromRow($sSelected)
				_ShowConfigGUI($sCurrentFile, $aOverlays)
				_RefreshTargetList($idList, $aTargets) ; reflect whatever just changed
			Case $msg = $idContinue
				Local $iUnconfigured = 0
				For $i = 0 To UBound($aTargets) - 1
					If Not _HasSettings(_StripPrefix($aTargets[$i])) Then $iUnconfigured += 1
				Next
				If $iUnconfigured > 0 Then
					MsgBox(48, "TargetManager", $iUnconfigured & " target(s) still need configuring" & _
						" (shown as 'NOT SET' in the list). Edit each one before continuing.")
					ContinueLoop
				EndIf
				ExitLoop
		EndSelect
		Sleep(30)
	WEnd

	GUIDelete($hGui)
EndFunc

; Rebuilds the list's row text for every target: "filename | overlay: X"
; or "filename | overlay: NOT SET" for anything not configured yet.
Func _RefreshTargetList($idList, $aTargets)
	; GUICtrlSetData ADDS items to a list control rather than replacing
	; them, so we have to explicitly reset it first or every refresh would
	; pile duplicate rows on top of the old ones.
	_GUICtrlListBox_ResetContent($idList)
	Local $sRows = ""
	For $i = 0 To UBound($aTargets) - 1
		Local $sFile = $aTargets[$i]
		Local $sBase = _StripPrefix($sFile)
		Local $sOverlay = IniRead($SETTINGS_INI, $sBase, "Overlay", "")
		If $sOverlay = "" Then $sOverlay = "NOT SET"
		Local $sRow = $sFile & " | overlay: " & $sOverlay
		If $i > 0 Then $sRows &= "|"
		$sRows &= $sRow
	Next
	GUICtrlSetData($idList, $sRows)
EndFunc

; Row format is "filename | overlay: X" - the filename is always the part
; before the first " | ", so this just recovers it.
Func _ExtractFilenameFromRow($sRow)
	Local $iPos = StringInStr($sRow, " | ")
	If $iPos = 0 Then Return $sRow
	Return StringLeft($sRow, $iPos - 1)
EndFunc

; Returns the height an a-plane should use if width=1, based on the
; overlay's real pixel aspect ratio.
Func _OverlayAspectHeight($sImgPath)
	_GDIPlus_Startup()
	Local $hImage = _GDIPlus_ImageLoadFromFile($sImgPath)
	Local $iW = _GDIPlus_ImageGetWidth($hImage)
	Local $iH = _GDIPlus_ImageGetHeight($hImage)
	_GDIPlus_ImageDispose($hImage)
	_GDIPlus_Shutdown()
	If $iW = 0 Then Return 1
	Return Round($iH / $iW, 3)
EndFunc

; Creates a scaled-down copy for display in the GUI (source images can be
; multiple MB / very high resolution). Returns [width, height] of the
; thumbnail actually written.
Func _CreateThumbnail($sSrcImage, $sDestPath, $iMaxDim = 260)
	_GDIPlus_Startup()
	Local $hImage = _GDIPlus_ImageLoadFromFile($sSrcImage)
	Local $iW = _GDIPlus_ImageGetWidth($hImage)
	Local $iH = _GDIPlus_ImageGetHeight($hImage)
	Local $fScale = $iMaxDim / _Max($iW, $iH)
	Local $iNewW = Round($iW * $fScale)
	Local $iNewH = Round($iH * $fScale)
	If $iNewW < 1 Then $iNewW = 1
	If $iNewH < 1 Then $iNewH = 1

	Local $hBitmap = _GDIPlus_BitmapCreateFromScan0($iNewW, $iNewH)
	Local $hGraphic = _GDIPlus_ImageGetGraphicsContext($hBitmap)
	_GDIPlus_GraphicsSetInterpolationMode($hGraphic, 7) ; HighQualityBicubic
	_GDIPlus_GraphicsDrawImageRect($hGraphic, $hImage, 0, 0, $iNewW, $iNewH)

	If FileExists($sDestPath) Then FileDelete($sDestPath)
	_GDIPlus_ImageSaveToFile($hBitmap, $sDestPath)

	_GDIPlus_GraphicsDispose($hGraphic)
	_GDIPlus_BitmapDispose($hBitmap)
	_GDIPlus_ImageDispose($hImage)
	_GDIPlus_Shutdown()

	Local $aRet[2] = [$iNewW, $iNewH]
	Return $aRet
EndFunc

; ---------------------------------------------------------------------------
; index.html regeneration
; ---------------------------------------------------------------------------
Func _RegenerateIndexHtml($aTargets)
	Local $sHtml = FileRead($INDEX_HTML)
	If @error Then
		MsgBox(16, "TargetManager", "Couldn't read " & $INDEX_HTML)
		Exit
	EndIf

	Local $sAssets = _BuildAssetsBlock($aTargets)
	Local $sTargets = _BuildTargetsBlock($aTargets)

	$sHtml = _ReplaceBetweenMarkers($sHtml, "<!-- AUTOGEN:ASSETS:START - do not hand-edit between these markers, TargetManager.au3 rewrites this block -->", "<!-- AUTOGEN:ASSETS:END -->", $sAssets)
	$sHtml = _ReplaceBetweenMarkers($sHtml, "<!-- AUTOGEN:TARGETS:START - do not hand-edit between these markers, TargetManager.au3 rewrites this block -->", "<!-- AUTOGEN:TARGETS:END -->", $sTargets)
	$sHtml = _BumpVersion($sHtml)

	; Back up the previous index.html alongside the .mind backups
	Local $sBackupName = "index_" & @YEAR & @MON & @MDAY & "_" & @HOUR & @MIN & @SEC & ".html"
	FileCopy($INDEX_HTML, $BACKUP_DIR & "\" & $sBackupName, 1)

	Local $hFile = FileOpen($INDEX_HTML, 2) ; overwrite
	FileWrite($hFile, $sHtml)
	FileClose($hFile)
EndFunc

; Bumps the minor version number in <button id="startButton">Revela Occulta vX.Y</button>
; every time index.html is regenerated (v1.1 -> v1.2 -> v1.3, ...). No cap/rollover.
; Isolates the substitution to the button's own text and avoids regex backreferences
; in the replacement string entirely, so there's no ambiguity between a backreference
; and a following literal digit.
Func _BumpVersion($sHtml)
	Local $sOpenTag = '<button id="startButton">'
	Local $iOpenPos = StringInStr($sHtml, $sOpenTag)
	If $iOpenPos = 0 Then Return $sHtml ; button not found, leave file alone

	Local $iTextStart = $iOpenPos + StringLen($sOpenTag)
	Local $iCloseTagPos = StringInStr($sHtml, "</button>", 0, 1, $iTextStart)
	If $iCloseTagPos = 0 Then Return $sHtml

	Local $sButtonText = StringMid($sHtml, $iTextStart, $iCloseTagPos - $iTextStart)

	Local $aVer = StringRegExp($sButtonText, "v(\d+)\.(\d+)", 1)
	If @error Then Return $sHtml ; no "vX.Y" pattern found, leave alone

	Local $iMajor = Number($aVer[0])
	Local $iMinor = Number($aVer[1]) + 1
	Local $sNewButtonText = StringRegExpReplace($sButtonText, "v\d+\.\d+", "v" & $iMajor & "." & $iMinor)

	Return StringLeft($sHtml, $iTextStart - 1) & $sNewButtonText & StringMid($sHtml, $iCloseTagPos)
EndFunc

Func _BuildAssetsBlock($aTargets)
	Local $s = @CRLF & "    <a-assets>" & @CRLF
	For $i = 0 To UBound($aTargets) - 1
		Local $sBase = _StripPrefix($aTargets[$i])
		Local $sOverlay = IniRead($SETTINGS_INI, $sBase, "Overlay", "")
		Local $sId = ($i = 0) ? "overlay" : ("overlay" & ($i + 1))
		$s &= "      <img id=""" & $sId & """ src=""./overlays/" & $sOverlay & """ />" & @CRLF
	Next
	$s &= "    </a-assets>" & @CRLF
	Return $s
EndFunc

Func _BuildTargetsBlock($aTargets)
	Local $s = @CRLF
	For $i = 0 To UBound($aTargets) - 1
		Local $sFile = $aTargets[$i]
		Local $sBase = _StripPrefix($sFile)
		Local $sId = ($i = 0) ? "overlay" : ("overlay" & ($i + 1))
		Local $sPos = IniRead($SETTINGS_INI, $sBase, "Position", "0 0 0")
		Local $sRot = IniRead($SETTINGS_INI, $sBase, "Rotation", "0 0 0")
		Local $sScale = IniRead($SETTINGS_INI, $sBase, "Scale", "0.5 0.5 0.5")
		Local $sWidth = IniRead($SETTINGS_INI, $sBase, "Width", "1")
		Local $sHeight = IniRead($SETTINGS_INI, $sBase, "Height", "1")

		$s &= "    <a-entity mindar-image-target=""targetIndex: " & $i & """>" & @CRLF
		$s &= "      <!-- trigger: " & $sFile & " -->" & @CRLF
		$s &= "      <a-plane" & @CRLF
		$s &= "        src=""#" & $sId & """" & @CRLF
		$s &= "        width=""" & $sWidth & """" & @CRLF
		$s &= "        height=""" & $sHeight & """" & @CRLF
		$s &= "        position=""" & $sPos & """" & @CRLF
		$s &= "        rotation=""" & $sRot & """" & @CRLF
		$s &= "        scale=""" & $sScale & """" & @CRLF
		$s &= "        material=""transparent: true; alphaTest: 0.1;""" & @CRLF
		$s &= "      ></a-plane>" & @CRLF
		$s &= "    </a-entity>" & @CRLF & @CRLF
	Next
	Return $s
EndFunc

Func _ReplaceBetweenMarkers($sContent, $sStartMarker, $sEndMarker, $sNewInner)
	Local $iStart = StringInStr($sContent, $sStartMarker)
	Local $iEnd = StringInStr($sContent, $sEndMarker)
	If $iStart = 0 Or $iEnd = 0 Or $iEnd < $iStart Then
		MsgBox(16, "TargetManager", "Couldn't find markers in index.html:" & @CRLF & $sStartMarker & @CRLF & _
			"index.html was NOT modified. Check that the markers are still intact.")
		Exit
	EndIf
	Local $iStartOfInner = $iStart + StringLen($sStartMarker)
	Local $sBefore = StringLeft($sContent, $iStartOfInner)
	Local $sAfter = StringMid($sContent, $iEnd)
	Return $sBefore & $sNewInner & "    " & $sAfter
EndFunc
