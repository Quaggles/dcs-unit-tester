# Debugger to test the output of missions run with assertions
param(
	[int] $Port = 1337
)
$retry = $true
while ($retry -eq $true) {
	try {
		# Set up endpoint and start listening
		$endpoint = new-object System.Net.IPEndPoint([ipaddress]::any, $Port) 
		$listener = new-object System.Net.Sockets.TcpListener $EndPoint
		$listener.start()

		# Wait for an incoming connection, if no connection occurs 
		$task = $listener.AcceptTcpClientAsync()
		while (-not $task.AsyncWaitHandle.WaitOne(100)) { }
		$data = $task.GetAwaiter().GetResult()
		Write-Host "Successful TCP connection" -ForegroundColor Green -BackgroundColor Black

		# Stream setup
		$stream = $data.GetStream() 
		$bytes = New-Object System.Byte[] 1024

		# Read data from stream and write it to host
		while (($i = $stream.Read($bytes,0,$bytes.Length)) -ne 0){
			$EncodedText = New-Object System.Text.ASCIIEncoding
			$data = $EncodedText.GetString($bytes,0, $i)
			Write-Host $data
		}
	} catch {
		Write-Host $_.ToString() -ForegroundColor Red -BackgroundColor Black
	} finally {		 
		# Close TCP connection and stop listening
		if ($listener) { $listener.stop() }
		if ($stream) { $stream.close() }
	}
}
if ((Get-ExecutionPolicy -Scope Process) -eq 'Bypass'){
	Read-Host "Press enter to exit"
}