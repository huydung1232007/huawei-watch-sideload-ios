Option Explicit
Dim shell, files, folder, command
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
command = "pythonw.exe " & Chr(34) & folder & "\pc_remote.py" & Chr(34)
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
  MsgBox "Khong mo duoc Python. Can Python 3.9+ va giai nen day du thu muc PC Remote.", 48, "PC Remote"
End If
