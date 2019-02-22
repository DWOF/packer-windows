#Start MDT Capture
net use s: '\\QAHMDT01\win10capture$' /user:DOMAIN\SVC_QAHmdtCapture 'Password'
Set-Location -Path S:\Scripts\
cscript .\litetouch.vbs
Exit