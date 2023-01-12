Param(
    [Parameter(Mandatory=$true)] $ServerList,
    )

$servers = Get-Content $ServerList

Write-Host "`n`n`n`n`n`n`n`n Checking credentials..." -ForegroundColor Yellow

$credfolder = Get-Item $env:UserProfile/DecomScriptCreds -ErrorAction SilentlyContinue
If (!$credfolder){
        New-Item -Path $env:UserProfile/DecomScriptCreds -ItemType Directory | Out-Null
        }

$environments = @(
    "PRD","DEV","QUT","SBX","TRN","PCP"
)
Foreach ($e in $environments){
$credfile = Get-Item $env:UserProfile/DecomScriptCreds/$e.xml -ErrorAction SilentlyContinue
If ((!$credfile) -or ($credfile.LastWriteTime -lt (Get-Date).AddDays(-1))){
        $cred = Get-Credential -Message "Please enter credentials for the PRD environment"
        $cred | Export-CliXml -Path $env:UserProfile/DecomScriptCreds/$e.xml 
}}

$domaintbl = @(
    [pscustomobject] @{
        "domain"="network.lan";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/PRD.xml}
    [pscustomobject] @{
        "domain"="network.dev";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/DEV.xml}
    [pscustomobject] @{
        "domain"="network.qut";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/QUT.xml}
    [pscustomobject] @{
        "domain"="network.sbx";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/SBX.xml}
    [pscustomobject] @{
        "domain"="network.trn";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/TRN.xml}
    [pscustomobject] @{
        "domain"="network.pcp";
        "cred"=Import-CliXml -Path $env:UserProfile/DecomScriptCreds/PCP.xml}
)

Write-Host "`n Finding server data. Please wait. This may take a while." -ForegroundColor Green
$srvcount = $servers.count
$maintbl = @()
$ct = 1
Foreach ($s in $servers){
    $percent = [int](($ct / $srvcount) * 100)
    Write-Progress -Activity "Gathering server info" -Status "$percent% Complete" -PercentComplete $percent
    $ct++
    Foreach ($d in $domaintbl){
        $obj = Get-AdComputer -Filter 'Name -eq $s' -Server $d.domain -Credential $d.cred
        If ($obj) {
            $zones = Get-DNSServerZone -ComputerName $d.domain | Where-Object ZoneType -eq "Primary"
            $fwd = $zones | Where-Object IsReverseLookupZone -eq $false
            $rev = $zones | Where-Object IsReverseLookupZone -eq $true
            $dnstbl = @()
                Foreach ($f in $fwd) {
                    $a = Get-DNSServerResourceRecord -ComputerName $d.domain -ZoneName $f.ZoneName -Name $s -ErrorAction SilentlyContinue| Select-Object HostName -ExpandProperty RecordData
                    If ($a) {
                    $line = [pscustomobject] @{
                        "ZoneName"=$f.ZoneName;
                        "HostName"=$a.HostName;
                        "RecordData"=($a.Ipv4Address).ToString()}
                    $dnstbl += $line}}
                Foreach ($r in $rev) {
                    $ptr = Get-DNSServerResourceRecord -ComputerName $d.domain -ZoneName $r.ZoneName -RRType PTR -ErrorAction SilentlyContinue | Where-Object {$_.RecordData.PtrDomainName -like "*$s*"} | Select-Object HostName -ExpandProperty RecordData
                    If ($ptr) {
                    $line = [pscustomobject] @{
                        "ZoneName"=$r.ZoneName;
                        "HostName"=$ptr.HostName;
                        "RecordData"=$ptr.PtrDomainName}
                    $dnstbl += $line}}
            $sccmgrp = Get-ADPrincipalGroupMembership -Server $d.domain -Credential $d.cred -Identity $obj | Where-Object Name -like "SCCM*" | Select-Object Name
            
            $line = [pscustomobject] @{
                "Name"=$s;
                "Domain"=$d.domain;
                "DNS"=$dnstbl;
                "SCCM"=$sccmgrp.Name}
            $maintbl += $line
            }
            }
            }

$maintbl | Out-GridView -Title "Decom Script Output"
Write-Host "`n Table has been output in a separate window. Please review." -ForegroundColor Green
$rem = Read-Host -Prompt "`n Do you want to remove these items? (y/n)"

If (($rem).ToLower() -eq "y"){
    Write-Host "`n Removing items. Please wait." -ForegroundColor Yellow
    Foreach ($i in $maintbl){
        Remove-ADComputer -Server $i.Domain -Credential ($domaintbl | Where-Object domain -eq $i.domain).cred -Identity $i.Name -Whatif
        Foreach ($d in $dns){Remove-DNSServerResourceRecord -ComputerName $i.domain -ZoneName $d.ZoneName -Name $d.HostName -Whatif}
        }
        }


