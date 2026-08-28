Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = "D:\HyperDrop"
WshShell.Run "node server/index.js", 0, False
