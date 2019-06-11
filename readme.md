Run the first half of the script to populate $updates.
Make sure $updates only contains the updates you wish to install
then run 

REST-LCM-BuildPlan -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

REST-LCM-Install -datavar $datavar -datagen $datagen -mode "PC" -updates $Updates

Please note since 10 June, LCM has been updated to 2.2, LCM will auto update once an inventory is run.
This script will be updated to support 2.1 asap, but does not atm. 
