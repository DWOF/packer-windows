#Start MDT Capture
net use s: '\\QAHMDT01\DeploymentShare$' /user:QAHMDT01\SVC_mdtImageCapture 'Password1$'
Set-Location -Path S:\Scripts\
cscript .\litetouch.vbs
Exit