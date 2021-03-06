function ExecRetry($command, $maxRetryCount = 10, $retryInterval=2)
{
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try 
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function GitClonePull($path, $url, $branch="master")
{
    if (!(Test-Path -path $path))
    {
        ExecRetry {
            git clone $url $path
            if ($LastExitCode) { throw "git clone failed" }
        }
        (git checkout $branch) -Or (git checkout master)
        if ($LastExitCode) { throw "git checkout failed" }
    }else{
        pushd $path
        try
        {
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$path\*"
            ExecRetry {
                git clone $url $path
                if ($LastExitCode) { throw "git clone failed" }
            }
            ExecRetry {
                (git checkout $branch) -Or (git checkout master)
                if ($LastExitCode) { throw "git checkout failed" }
            }

            Get-ChildItem . -Include *.pyc -Recurse | foreach ($_) {Remove-Item $_.fullname}

            git reset --hard
            if ($LastExitCode) { throw "git reset failed" }

            git clean -f -d
            if ($LastExitCode) { throw "git clean failed" }

            ExecRetry {
                git pull
                if ($LastExitCode) { throw "git pull failed" }
            }
        }
        finally
        {
            popd
        }
    }
}

function dumpeventlog($path){
	
	Get-Eventlog -list | Where-Object { $_.Entries -ne '0' } | ForEach-Object {
		$logFileName = $_.LogDisplayName
		$exportFileName =$path + "\eventlog_" + $logFileName + ".evt"
		$exportFileName = $exportFileName.replace(" ","_")
		$logFile = Get-WmiObject Win32_NTEventlogFile | Where-Object {$_.logfilename -eq $logFileName}
		try{
			$logFile.backupeventlog($exportFileName)
		} catch {
			Write-Host "Could not dump $_.LogDisplayName (it might not exist)."
		}
	}
}

function exporteventlog($path){

	Get-Eventlog -list | Where-Object { $_.Entries -ne '0' } | ForEach-Object {
		$logfilename = "eventlog_" + $_.LogDisplayName + ".txt"
		$logfilename = $logfilename.replace(" ","_")
		Get-EventLog -Logname $_.LogDisplayName | fl | out-file $path\$logfilename -ErrorAction SilentlyContinue
	}
}

function exporthtmleventlog($path){
	$css = Get-Content $eventlogcsspath -Raw
	$js = Get-Content $eventlogjspath -Raw
	$HTMLHeader = @"
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<script type="text/javascript">$js</script>
<style type="text/css">$css</style>
"@

	foreach ($i in (Get-EventLog -List | Where-Object { $_.Entries -ne '0' }).Log) {
		$Report = Get-EventLog $i
		$Report = $Report | ConvertTo-Html -Title "${i}" -Head $HTMLHeader -As Table
		$Report = $Report | ForEach-Object {$_ -replace "<body>", '<body id="body">'}
		$Report = $Report | ForEach-Object {$_ -replace "<table>", '<table class="sortable" id="table" cellspacing="0">'}
		$logName = "eventlog_" + $i + ".html"
		$logName = $logName.replace(" ","_")
		$bkup = Join-Path $path $logName
		$Report = $Report | Set-Content $bkup
	}
}

function cleareventlog(){
	Get-Eventlog -list | ForEach-Object {
		Clear-Eventlog $_.LogDisplayName -ErrorAction SilentlyContinue
	}
}

function destroy_planned_vms() {
    $planned_vms = [array] (gwmi -ns root/virtualization/v2 -class Msvm_PlannedComputerSystem)
    $svc = gwmi -ns root/virtualization/v2 -class Msvm_VirtualSystemManagementService

    $pvm_count = $planned_vms.Count
    log_message "Found $pvm_count planned vms."
    foreach($pvm in $planned_vms) {
        $svc.DestroySystem($pvm)
    }
}

function log_message($message){
    echo "[$(Get-Date)] $message"
}

function unarchive($archive_path, $dest_dir){
    # This could be updated sometime to atomically handle .tar.gz archives.
    Write-Host "Unarchiving $archive_path to $dest_dir"
    & 'C:\Program Files\7-Zip\7z.exe' -o"$dest_dir" x -y "$archive_path"
}
