@echo off
echo ============================================
echo  HyperDrop - Fix Firewall for iPhone Access
echo ============================================
echo Removing old rules...
netsh advfirewall firewall delete rule name="HyperDrop Web Port 3000" >nul 2>&1
netsh advfirewall firewall delete rule name="HyperDrop Port 3000 Inbound" >nul 2>&1
netsh advfirewall firewall delete rule name="HyperDrop Port 3000 Outbound" >nul 2>&1

echo Adding inbound TCP rule for port 3000...
netsh advfirewall firewall add rule name="HyperDrop Port 3000 Inbound" protocol=TCP dir=in localport=3000 action=allow profile=any enable=yes

echo Adding outbound TCP rule for port 3000...
netsh advfirewall firewall add rule name="HyperDrop Port 3000 Outbound" protocol=TCP dir=out localport=3000 action=allow profile=any enable=yes

echo Adding node.exe application rule...
netsh advfirewall firewall add rule name="Node.js HyperDrop" dir=in action=allow program="C:\Program Files\nodejs\node.exe" enable=yes profile=any >nul 2>&1

echo.
echo ============================================
echo  DONE! Port 3000 is now open for iPhone.
echo  Your iPhone must be on the SAME Wi-Fi.
echo ============================================
echo.
pause
