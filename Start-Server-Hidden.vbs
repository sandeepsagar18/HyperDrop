Set WshShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")
appDir = FSO.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = appDir

nodeExe = "node"
If FSO.FileExists(appDir & "\node.exe") Then
    nodeExe = """" & appDir & "\node.exe"""
End If

WshShell.Run nodeExe & " server/index.js", 0, False
