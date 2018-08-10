####### Collect some counters for vmnic's on hosts which are PoweredOn and where vmnic is connected #######
#Collects metrics and pushes them into vRops related HostSystem.
#v1.0 vMan.ch, 15.07.2018 - Initial Version

param
(
    [String]$vRopsAddress,
    [String]$vcAddress,
    [String]$vRopsCreds,
    [String]$vcCreds 
)

# Usage
# .\CustomNetStats-API2vROPS -vRopsAddress 'vRops.vMan.ch' -vc 'vc.vMan.ch' -vRopsCreds 'vRops' -vcCreds 'vc'


#Functions

#Get vRops ResourceID from Name
Function GetObject([String]$vRopsObjName, [String]$resourceKindKey, [String]$vRopsServer, $vRopsCredentials){

    $vRopsObjName = $vRopsObjName -replace ' ','%20'

    [xml]$Checker = Invoke-RestMethod -Method Get -Uri "https://$vRopsServer/suite-api/api/resources?resourceKind=$resourceKindKey&name=$vRopsObjName" -Credential $vRopsCredentials -Headers $header -ContentType $ContentType

#Check if we get 0

    if ([Int]$Checker.resources.pageInfo.totalCount -eq '0'){

    Return $CheckerOutput = ''

    }

    else {

        # Check if we get more than 1 result and apply some logic
            If ([Int]$Checker.resources.pageInfo.totalCount -gt '1') {

                $DataReceivingCount = $Checker.resources.resource.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'

                    If ($DataReceivingCount.count -gt 1){

                     If ($Checker.resources.resource.ResourceKey.name -eq $vRopsObjName){

                        ForEach ($Result in $Checker.resources.resource){

                            IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                            }   
                        }

                      }
                    }
            
                    Else 
                    {

                    ForEach ($Result in $Checker.resources.resource){

                        IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                        }   
                    }
            }  
         }

        else {
    
            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Checker.resources.resource.identifier; resourceKindKey=$Checker.resources.resource.resourceKey.resourceKindKey}

            Return $CheckerOutput

            }
        }
}

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName

if($vRopsCreds -gt ""){

    $vRopsCred = Import-Clixml -Path "$ScriptPath\config\$vRopsCreds.xml"

    }
    else
    {
    echo "vRops Credentials not specified, stop hammer time!"
    Exit
    }

if($vcCreds -gt ""){

    $vcCred = Import-Clixml -Path "$ScriptPath\config\$vcCreds.xml"

    }
    else
    {
    echo "VC Credentials not specified, stop hammer time!"
    Exit
    }



[DateTime]$NowDate = (Get-date)
[int64]$NowDateEpoc = Get-Date -Date $NowDate.ToUniversalTime() -UFormat %s
$NowDateEpoc = $NowDateEpoc * 1000

#Take all certs.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls

#Stuff for Invoke-RestMethod
$ContentType = "application/xml"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')
$header.Add("User-Agent", 'vRopsPowershellMetricExtractor/1.0')


#Connect to VC's
Connect-viserver -Server $vcAddress -Credential $vcCred -Force

$Report = @()
    $esxihosts = Get-VMHost | Sort-Object

    foreach ($esxihost in $esxihosts | Where-Object {$_.ConnectionState -match "Connected" -and $_.PowerState -match "PoweredOn"}) {

        $esxcli = Get-Esxcli -v2 -VMHost $esxihost 

        foreach ($Nic in $esxcli ){ 
        
            ForEach ($N in $Nic.network.nic.list.Invoke() | Where-Object {$_.Link -match "Up"}){

            $NicData = $esxcli.network.nic.stats.get.invoke(@{nicname = $N.Name}) 

                $Report += New-Object PSObject -Property @{
                        
                    "ESXiHost"            = $esxihost.name
                    "VMNIC"               = $N.Name
                    "ReceiveCRCerrors"  = $NicData.ReceiveCRCerrors
                    "ReceiveFIFOerrors"	= $NicData.ReceiveFIFOerrors
                    "Receiveframeerrors"	= $NicData.Receiveframeerrors
                    "Receivelengtherrors"	= $NicData.Receivelengtherrors
                    "Receivemissederrors"	= $NicData.Receivemissederrors
                    "Receiveovererrors"	= $NicData.Receiveovererrors
                    "Receivepacketsdropped"	= $NicData.Receivepacketsdropped
                    "TotalReceiveerrors"	= $NicData.TotalReceiveerrors
                    "Totaltransmiterrors"	= $NicData.Totaltransmiterrors
                    "TransmitFIFOerrors"	= $NicData.TransmitFIFOerrors
                    "Transmitabortederrors"	= $NicData.Transmitabortederrors
                    "Transmitcarriererrors"	= $NicData.Transmitcarriererrors
                    "Transmitheartbeaterrors"	= $NicData.Transmitheartbeaterrors
                    "Transmitpacketsdropped"	= $NicData.Transmitpacketsdropped
                    "Transmitwindowerrors"	= $NicData.Transmitwindowerrors
                    "Date"                = $NowDateEpoc
                        
                }
            
            }
        
        
        }
       
    }


#Push in Metrics
$HostList = @()

$HostList = $Report.ESXiHost | unique

     $MetricXML = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ops:stat-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">')
 

ForEach ($Hst in $HostList){

    $resourceid = GetObject $Hst 'HostSystem' $vRopsAddress $vRopsCred    

    ForEach ($MetricInsert in $Report | where {$_.ESXiHost -eq $Hst}){

        If($resourceid.resourceId -gt '') {


        $MetricXML += @('<ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|ReceiveMissedErrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.ReceiveMissedErrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Receivepacketsdropped">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Receivepacketsdropped+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Transmitpacketsdropped">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Transmitpacketsdropped+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Transmitwindowerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Transmitwindowerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Transmitheartbeaterrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Transmitheartbeaterrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|TransmitFIFOerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.TransmitFIFOerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Transmitabortederrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Transmitheartbeaterrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Receiveovererrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Receiveovererrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|ReceiveCRCerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.ReceiveCRCerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|TotalReceiveerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.TotalReceiveerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Receiveframeerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Receiveframeerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|ReceiveFIFOerrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.ReceiveFIFOerrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Transmitcarriererrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Transmitcarriererrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Totaltransmiterrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Totaltransmiterrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>
                <ops:stat-content statKey="vMAN|net|'+$MetricInsert.VMNIC+'|Receivelengtherrors">
                  <ops:timestamps>'+$MetricInsert.Date+'</ops:timestamps>
                    <ops:data>'+$MetricInsert.Receivelengtherrors+'</ops:data>
                    <ops:unit>num</ops:unit>
                </ops:stat-content>')

}
    }
    
    $MetricXML += @('</ops:stat-contents>')
    
    [xml]$MetricXML = $MetricXML

    $vRopsMetricURL = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+$resourceid.Resourceid+'/stats'

    Invoke-RestMethod -Method POST -uri $vRopsMetricURL -Body $MetricXML -Credential $vRopsCred -ContentType "application/xml;charset=utf-8"
        
    Remove-Variable vRopsMetricURL -ErrorAction SilentlyContinue
    Remove-Variable MetricXML -ErrorAction SilentlyContinue
    Remove-Variable MetricInsert -ErrorAction SilentlyContinue

}

Disconnect-viserver -server $vcAddress -Force -Confirm:$false