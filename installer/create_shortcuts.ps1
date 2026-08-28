$w = New-Object -ComObject WScript.Shell
$d = [Environment]::GetFolderPath('Desktop')

$s1 = $w.CreateShortcut("$d\HyperDrop-Server.lnk")
$s1.TargetPath = "wscript.exe"
$s1.Arguments = """D:\HyperDrop\Start-Server-Hidden.vbs"""
$s1.WorkingDirectory = "D:\HyperDrop"
$s1.Description = "Start HyperDrop Server in Background"
$s1.Save()

$s2 = $w.CreateShortcut("$d\HyperDrop.lnk")
$s2.TargetPath = "D:\HyperDrop\flutter\build\windows\x64\runner\Release\hyperdrop_flutter.exe"
$s2.WorkingDirectory = "D:\HyperDrop\flutter\build\windows\x64\runner\Release"
$s2.Description = "HyperDrop - High Speed File Transfer"
$s2.Save()

Write-Host "Created Desktop Shortcuts Successfully!"
