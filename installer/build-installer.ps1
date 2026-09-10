param()
$ErrorActionPreference = 'Stop'

$src = 'C:\Users\asus\AppData\Local\Programs\HyperDrop'
$zipPath = 'D:\My_Project\HyperDrop\installer\payload.zip'

if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Write-Host "Creating payload.zip from $src..."
Compress-Archive -Path "$src\*" -DestinationPath $zipPath -CompressionLevel Optimal

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$icon = 'D:\My_Project\HyperDrop\flutter\windows\runner\resources\app_icon.ico'
$outExe = 'C:\Users\asus\Desktop\HyperDrop-Setup.exe'
$csSource = 'D:\My_Project\HyperDrop\installer\Installer.cs'

Write-Host "Compiling setup installer with csc..."
& $csc /target:winexe "/reference:System.IO.Compression.dll,System.IO.Compression.FileSystem.dll,System.Windows.Forms.dll,System.Drawing.dll" "/win32icon:$icon" "/resource:$zipPath,payload.zip" "/out:$outExe" "$csSource"

Copy-Item 'C:\Users\asus\Desktop\HyperDrop-Setup.exe' 'D:\My_Project\HyperDrop\HyperDrop-Setup.exe' -Force
Write-Host "Setup installer successfully built and updated on Desktop!"
