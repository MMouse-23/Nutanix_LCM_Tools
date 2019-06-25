Run:

$Clusters = REST-Get-Clusters -datagen $datagen -datavar $datavar -mode "PC"
Select the cluster from $clusters
Get the UUID

Populate the variables in the top, including the UUID

Run the first half of the script to populate $versions and $updates.

Ignore the count messages in the above calls.

Make sure $updates only contains the updates you wish to install
then run 

REST-LCM-BuildPlan -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

REST-LCM-Install -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

Script has been modified to work with LCM 2.2
But also, to work with PE 5.6. meaning all V3 API calls run through PC.
Iventory etc is sent directly, but group calls are all proxied through PC.
