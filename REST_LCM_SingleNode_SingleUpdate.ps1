



#Input Data

$BuildAccount  = "admin"
$PEAdmin       = "admin"
$PEPass        = ""
$PCCLIP        = ""
$PEClIP        = ""

$ClusterUUID   = ""


$datagen = New-Object PSObject;
$datagen | add-member Noteproperty BuildAccount        $BuildAccount    
$datagen | add-member Noteproperty PCClusterIP         $PCCLIP;
$datagen | add-member Noteproperty targetclusteruuid   $ClusterUUID;         

$datavar = New-Object PSObject;
$datavar | add-member Noteproperty PEAdmin             $PEAdmin;
$datavar | add-member Noteproperty PEPass              $PEPass    
$datavar | add-member Noteproperty PEClusterIP         $PECLIP;

##Functions



## Loading assemblies
add-type @"
  using System.Net;
  using System.Security.Cryptography.X509Certificates;
  public class TrustAllCertsPolicy : ICertificatePolicy {
      public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,
                                        WebRequest request, int certificateProblem) {
          return true;
      }
   }
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Ssl3, [Net.SecurityProtocolType]::Tls, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls12

Function REST-LCM-Install {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode,
    [object] $Updates
  )
  if ($mode -eq "PC"){
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Executing LCM List Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/genesis?proxyClusterUuid=$($datagen.targetclusteruuid)"

  write-log -message "Using URL $URL"

  $Start= '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_update\",\"args\":[\"http://download.nutanix.com/lcm/2.0\",['
  $End = ']]}}"}'
  
  foreach ($item in $updates){
    $update = "[\`"$($item.uuid)\`",\`"$($item.version)\`"],"
    $start = $start + $update
  }
  $start = $start.Substring(0,$start.Length-1)
  $start = $start + $end
  [string]$json = $start
  write-log -message "Using URL $json"

  try{
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  }

  Return $task
}


Function write-log {
  param (
  $message,
  $sev = "INFO",
  $slacklevel = 0
  )
  if ($sev -eq "INFO"){
    write-host "$(get-date -format "hh:mm:ss") | INFO  | $message"
  } elseif ($sev -eq "WARN"){
    write-host "$(get-date -format "hh:mm:ss") | WARN  | $message"
  } elseif ($sev -eq "ERROR"){
    write-host "$(get-date -format "hh:mm:ss") | ERROR | $message"
  } elseif ($sev -eq "CHAPTER"){
    write-host "`n`n### $message`n`n"
  }
} 



  
  Function Wait-Task{
    do {
      try{
        $counter++
        write-log -message "Wait for inventory Cycle $counter out of 25(minutes)."
    
        $PCtasks = REST-Get-AOS-LegacyTask -datagen $datagen -datavar $datavar -mode "PE"
        $LCMTasks = $PCtasks.entities | where { $_.operation -match "LcmRootTask"}
        $Inventorycount = 0
        [array]$Results = $null
        foreach ($item in $LCMTasks){
          if ( $item.percentage_complete -eq 100) {
            $Results += "Done"
     
            write-log -message "Inventory $($item.uuid) is completed."
          } elseif ($item.percentage_complete -ne 100){
            $Inventorycount ++
    
            write-log -message "Inventory $($item.uuid) is still running."
            write-log -message "We found 1 task $($item.status) and is $($item.percentage_complete) % complete"
    
            $Results += "BUSY"
    
          }
        }
        if ($Results -notcontains "BUSY" -or !$LCMTasks){

          write-log -message "Inventory is done."
     
          $Inventorycheck = "Success"
     
        } else{
          sleep 60
        }
    
      }catch{
        write-log -message "Error caught in loop."
      }
    } until ($Inventorycheck -eq "Success" -or $counter -ge 10)
  }



Function REST-Get-AOS-LegacyTask {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $class =  "PC"
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $class =  "PE"
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }
  #output suppressed for task loopers
  #write-log -message "Executing LCM List Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/progress_monitors?proxyClusterUuid=$($datagen.targetclusteruuid)"

   # write-log -message "Using URL $URL"


  try{
    $task = Invoke-RestMethod -Uri $URL -method "get" -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "get"  -headers $headers;
  }

  Return $task
} 


Function REST-LCMV2-Query-Versions {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $class =  "PC"
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $class =  "PE"
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Executing LCM List Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/genesis?proxyClusterUuid=$($datagen.targetclusteruuid)"

  write-log -message "Using URL $URL"

$Payload= @"
{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"v3_group_api\",\"args\":[\"{\\\"entity_type\\\":\\\"lcm_entity_v2\\\",\\\"group_member_count\\\":500,\\\"group_member_attributes\\\":[{\\\"attribute\\\":\\\"id\\\"},{\\\"attribute\\\":\\\"uuid\\\"},{\\\"attribute\\\":\\\"entity_model\\\"},{\\\"attribute\\\":\\\"version\\\"},{\\\"attribute\\\":\\\"location_id\\\"},{\\\"attribute\\\":\\\"entity_class\\\"},{\\\"attribute\\\":\\\"description\\\"},{\\\"attribute\\\":\\\"last_updated_time_usecs\\\"},{\\\"attribute\\\":\\\"request_version\\\"},{\\\"attribute\\\":\\\"_master_cluster_uuid_\\\"},{\\\"attribute\\\":\\\"entity_type\\\"},{\\\"attribute\\\":\\\"single_group_uuid\\\"}],\\\"query_name\\\":\\\"lcm:EntityGroupModel\\\",\\\"grouping_attribute\\\":\\\"location_id\\\",\\\"filter_criteria\\\":\\\"entity_type==firmware\\\"}\"]}}"}
"@ 

  $JSON = $Payload 
  try{
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  }
  
  $object = ($task.value | ConvertFrom-Json).".return"
  write-log -message "We found $($object.group_results.entity_results.count) items."
  Return $object
} 



Function REST-Get-Clusters {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $clusterip = $datavar.PEClusterIP
  }  
  write-log -message "Debug level is $debug";
  write-log -message "Building Credential object"
  $credPair = "$($datagen.buildaccount):$($datavar.pepass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Building Cluster Query JSON"

  $URL = "https://$($clusterip):9440/api/nutanix/v3/clusters/list"
  $Payload= @{
    kind="cluster"
    offset=0
    length=999
  } 

  $JSON = $Payload | convertto-json
  try{
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  } catch {
    sleep 10
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  }
  if ($task.entities.count -eq 0){

    write-log -message "0? Let me try that again after a small nap."

    do {
      $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
      sleep 30
      $count++

      write-log -message "Cycle $count Getting Clusters, current items found is $($task.entities.count)"
    } until ($count -ge 10 -or $task.entities.count -ge 1)
  }
  write-log -message "We found $($task.entities.count) clusters"
  return $task
} 


Function REST-LCMV2-Query-Updates {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $class =  "PC"
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $class =  "PE"
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Executing LCM List Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/genesis?proxyClusterUuid=$($datagen.targetclusteruuid)"

  write-log -message "Using URL $URL"

$Payload= @"
{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"v3_group_api\",\"args\":[\"{\\\"entity_type\\\":\\\"lcm_available_version_v2\\\",\\\"group_member_count\\\":500,\\\"group_member_attributes\\\":[{\\\"attribute\\\":\\\"uuid\\\"},{\\\"attribute\\\":\\\"entity_uuid\\\"},{\\\"attribute\\\":\\\"entity_class\\\"},{\\\"attribute\\\":\\\"status\\\"},{\\\"attribute\\\":\\\"version\\\"},{\\\"attribute\\\":\\\"dependencies\\\"},{\\\"attribute\\\":\\\"single_group_uuid\\\"},{\\\"attribute\\\":\\\"_master_cluster_uuid_\\\"},{\\\"attribute\\\":\\\"order\\\"}],\\\"query_name\\\":\\\"lcm:VersionModel\\\"}\"]}}"}
"@ 

  $JSON = $Payload 
  try{
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  }

  $object = ($task.value | ConvertFrom-Json).".return"
  write-log -message "We found $($object.group_results.entity_results.count) items."
  Return $object
} 


Function REST-LCM-BuildPlan {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode,
    [object] $Updates
  )
  if ($mode -eq "PC"){
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Executing LCM List Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/genesis?proxyClusterUuid=$($datagen.targetclusteruuid)"

  write-log -message "Using URL $URL"

  $Start= '{"value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"generate_plan\",\"args\":[\"http://download.nutanix.com/lcm/2.0\",['
  $End = ']]}}"}'
  
  foreach ($item in $updates){
    $update = "[\`"$($item.uuid)\`",\`"$($item.version)\`"],"
    $start = $start + $update
  }
  $start = $start.Substring(0,$start.Length-1)
  $start = $start + $end
  [string]$json = $start
  write-log -message "Using URL $json"

  try{
    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "post" -body $JSON -ContentType 'application/json' -headers $headers;
  }

  Return $task
} 
function Get-FunctionName {
  param (
    [int]$StackNumber = 1
  ) 
    return [string]$(Get-PSCallStack)[$StackNumber].FunctionName
}

Function REST-LCM-Perform-Inventory {
  Param (
    [object] $datavar,
    [object] $datagen,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.pepass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }
  write-log -message "Connecting to $clusterip"
  write-log -message "Mode is $mode"
  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/genesis?proxyClusterUuid=$($datagen.targetclusteruuid)"
  $json1 = @"
{
    "value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"configure\",\"args\":[\"http://download.nutanix.com/lcm/2.0\",null,null,true]}}"
}
"@
  $json2 = @"
{
    "value":"{\".oid\":\"LifeCycleManager\",\".method\":\"lcm_framework_rpc\",\".kwargs\":{\"method_class\":\"LcmFramework\",\"method\":\"perform_inventory\",\"args\":[\"http://download.nutanix.com/lcm/2.0\"]}}"
}
"@
  try{
    $setAutoUpdate = Invoke-RestMethod -Uri $URL -method "post" -body $JSON1 -ContentType 'application/json' -headers $headers;
    $Inventory = Invoke-RestMethod -Uri $URL -method "post" -body $JSON2 -ContentType 'application/json' -headers $headers;
  
    write-log -message "AutoUpdated set and Inventory started"
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"
    $setAutoUpdate = Invoke-RestMethod -Uri $URL -method "post" -body $JSON1 -ContentType 'application/json' -headers $headers;
    $Inventory = Invoke-RestMethod -Uri $URL -method "post" -body $JSON2 -ContentType 'application/json' -headers $headers;
  }
  Return $Inventory

} 

Function REST-PE-Get-Hosts {
  Param (
    [object] $datagen,
    [object] $datavar,
    [string] $mode
  )
  if ($mode -eq "PC"){
    $clusterIP = $datagen.PCClusterIP
  }  else {
    $clusterip = $datavar.PEClusterIP
  }  
  $credPair = "$($datagen.buildaccount):$($datavar.PEPass)"
  $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
  $headers = @{ Authorization = "Basic $encodedCredentials" }

  write-log -message "Executing Get Hosts Query"

  $URL = "https://$($clusterip):9440/PrismGateway/services/rest/v1/hosts?proxyClusterUuid=$($datagen.targetclusteruuid)"

  write-log -message "Using URL $URL"


  $JSON = $Payload 
  try{
    $task = Invoke-RestMethod -Uri $URL -method "GET" -headers $headers;
  } catch {
    sleep 10
    $FName = Get-FunctionName;write-log -message "Error Caught on function $FName" -sev "WARN"

    $task = Invoke-RestMethod -Uri $URL -method "GET" -headers $headers;
  }

  Return $task
} 


$Clusters = REST-Get-Clusters -datagen $datagen -datavar $datavar -mode "PC"

### use the cluster ID and set it in the above code

#Logic Inventory

REST-LCM-Perform-Inventory -datavar $datavar -datagen $datagen -mode "PC"


#Logic Current

  write-log -message "Checking Which version we have now."
  $groupcal = 0
  do {
    $groupcall ++
    sleep 10
    $names = REST-LCMV2-Query-Versions -datagen $datagen -datavar $datavar -mode "PC"
  } until ($names.group_results.entity_results.count -ge $minimalupdates -or $groupcall -ge $maxgroupcallLoops)
  $UUIDS = $names.group_results.entity_results.data.values.values | where {$_ -match ".*-.*-.*" -and $_ -notmatch "PC"}
  
  $versions = $null
  foreach ($app in $UUIDS){
    $nodeUUID = (((($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "location_id"}).values.values | select -last 1) -split ":")[1]
    $PHhost = $hosts.entities | where {$_.uuid -match $nodeuuid}
    $Entity = [PSCustomObject]@{
      Version     = (($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "version"}).values.values | select -last 1
      Class       = (($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "entity_class"}).values.values | select -last 1
      Name        = (($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "entity_model"}).values.values | select -last 1
      UUID        = $app
      HostName    = $PHhost.name
    }
    [array]$versions += $entity     
  }  
  write-log -message "Getting Last Calm Version" 




do {
    $counter2++
    
    write-log -message "Checking Results"
    sleep 60
    $result = REST-LCMV2-Query-Updates -datagen $datagen -datavar $datavar -mode "PC"
  
    if ($result.total_entity_count -lt 1){ 
  
      write-log -message "There are no updates, retry $counter2 out of 16"
      
      Wait-Task
      sleep 110
      $result = REST-LCMV2-Query-Updates -datagen $datagen -datavar $datavar -mode "PC"
    }
    if ($result.total_entity_count -lt 1 -and $counter2 -lt 2){

      write-log -message "Running LCM Inventory Again"

      REST-LCM-Perform-Inventory -datavar $datavar -datagen $datagen -mode "PC"
      sleep 115      
    }
    if ($counter2 -eq 5 -or $counter2 -eq 12){

      write-log -message "Running LCM Inventory Again"

      REST-LCM-Perform-Inventory -datavar $datavar -datagen $datagen -mode "PC"
      sleep 115
    }
  } until ($result.total_entity_count -ge 1 -or $counter2 -ge 16)

  $UUIDs = ($result.group_results.entity_results.data |where {$_.name -eq "entity_uuid"}).values.values | sort -unique

  write-log -message "We have $($uuids.count) applications to be updated, seeking version"
  $names = REST-LCMV2-Query-Versions -datagen $datagen -datavar $datavar -mode "PC"
  $hosts = REST-PE-Get-Hosts -datagen $datagen -datavar $datavar 
  $Updates = $null
  foreach ($app in $UUIDs){
    $nodeUUID = (((($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "location_id"}).values.values | select -last 1) -split ":")[1]
    $PHhost = $hosts.entities | where {$_.uuid -match $nodeuuid}
    $Entity = [PSCustomObject]@{
      UUID        = $app
      Version     = (($result.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "version"}).values.values | select -last 1
      Class       = (($result.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "entity_class"}).values.values | select -last 1
      Name        = (($names.group_results.entity_results | where {$_.data.values.values -eq $app}).data | where {$_.name -eq "entity_model"}).values.values | select -last 1
      HostUUID    = $nodeUUID
      HostName    = $PHhost.name
    }
    [array]$Updates += $entity     
  }

## Stop testing beyond here


$versions


$updates


## Play and manipulate $Updates before sending it into the functions below.

write-log -message "Building a LCM update Plan" -slacklevel 1

REST-LCM-BuildPlan -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

write-log -message "Installing Updates" -slacklevel 1

REST-LCM-Install -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

