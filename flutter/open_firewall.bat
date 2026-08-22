@echo off
echo Adding HyperDrop firewall rules...
netsh advfirewall firewall add rule name="HyperDrop Web Port 3000" dir=in action=allow protocol=TCP localport=3000
netsh advfirewall firewall add rule name="HyperDrop LAN Port 8080" dir=in action=allow protocol=TCP localport=8080
netsh advfirewall firewall add rule name="HyperDrop UDP Discovery" dir=in action=allow protocol=UDP localport=35432
echo.
echo Done! All HyperDrop ports are now open.
echo Port 3000 = Web App (QR Code)
echo Port 8080 = Flutter LAN Transfer
echo Port 35432 = Device Discovery
pause
