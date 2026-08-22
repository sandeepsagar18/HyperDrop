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

echo Adding inbound TCP rule for transfer port 8080...
netsh advfirewall firewall add rule name="HyperDrop Port 8080 Inbound" protocol=TCP dir=in localport=8080 action=allow profile=any enable=yes

echo Adding inbound UDP rule for discovery port 35432...
netsh advfirewall firewall add rule name="HyperDrop UDP Discovery Inbound" protocol=UDP dir=in localport=35432 action=allow profile=any enable=yes

echo Adding outbound UDP rule for discovery port 35432...
netsh advfirewall firewall add rule name="HyperDrop UDP Discovery Outbound" protocol=UDP dir=out localport=35432 action=allow profile=any enable=yes

echo Adding Flutter executable rule...
netsh advfirewall firewall add rule name="HyperDrop Flutter App" dir=in action=allow program="%~dp0flutter\build\windows\x64\runner\Release\hyperdrop_flutter.exe" enable=yes profile=any >nul 2>&1
netsh advfirewall firewall add rule name="HyperDrop Flutter App Local" dir=in action=allow program="D:\hyperdrop_flutter\build\windows\x64\runner\Release\hyperdrop_flutter.exe" enable=yes profile=any >nul 2>&1

echo.
echo ============================================
echo  DONE! All ports (3000, 8080, 35432) are now open!
echo  Your laptops and phones can now auto-discover.
echo ============================================
echo.
pause
